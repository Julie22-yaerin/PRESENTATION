import type { AnalysisStrategy, AppSettings, ConnectionTest, ModelListing, UsageInfo } from '../shared/types'
import { envBaseUrl, getApiKey, type KeySource } from './store'

/**
 * Default only: the model catalog changes over time, so Settings always offers a
 * "load models from endpoint" action and the chosen id is stored per machine.
 * The GPT-5 family is intentionally avoided because it is being retired.
 */
export const FALLBACK_MODEL = 'gpt-6-luna'

export interface ResolvedAi {
  baseUrl: string
  apiKey: string
  keySource: KeySource
  model: string
  sttModel: string
  strategy: AnalysisStrategy
  systemPrompt: string
  maxTokens: number
  timeoutMs: number
  reasoningEffort: string
}

export interface ChatContentPart {
  type: 'text' | 'image_url' | 'input_audio'
  text?: string
  image_url?: { url: string; detail?: 'auto' | 'low' | 'high' }
  input_audio?: { data: string; format: string }
}

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant'
  content: string | ChatContentPart[]
}

export class AiError extends Error {
  status: number

  constructor(message: string, status = 0) {
    super(message)
    this.name = 'AiError'
    this.status = status
  }

  /** True when the provider rejected the audio part, i.e. we should transcribe first. */
  get audioRejected(): boolean {
    return /audio|input_audio|modalit|unsupported|not support|invalid content|unknown content/i.test(this.message)
  }

  get effortRejected(): boolean {
    return /effort|reasoning/i.test(this.message)
  }
}

export async function resolveAi(settings: AppSettings): Promise<ResolvedAi> {
  const { key, source } = await getApiKey()
  const fromEnv = process.env.AIBUBBLE_MODEL?.trim()
  return {
    baseUrl: settings.ai.baseUrl || envBaseUrl() || 'https://api.openai.com/v1',
    apiKey: key,
    keySource: source,
    model: settings.ai.model || fromEnv || FALLBACK_MODEL,
    sttModel: settings.ai.sttModel,
    strategy: settings.ai.strategy,
    systemPrompt: settings.ai.systemPrompt,
    maxTokens: settings.ai.maxTokens,
    timeoutMs: settings.ai.timeoutMs,
    reasoningEffort: settings.ai.reasoningEffort
  }
}

function openAiFamily(model: string): boolean {
  return /^(gpt-|o[134]|chatgpt|davinci)/i.test(model)
}

function tokenField(model: string): 'max_completion_tokens' | 'max_tokens' {
  return openAiFamily(model) ? 'max_completion_tokens' : 'max_tokens'
}

async function errorMessage(res: Response): Promise<string> {
  const text = await res.text().catch(() => '')
  try {
    const parsed: unknown = JSON.parse(text)
    if (parsed && typeof parsed === 'object' && 'error' in parsed) {
      const err = (parsed as { error: unknown }).error
      if (typeof err === 'string') return err
      if (err && typeof err === 'object' && 'message' in err) return String((err as { message: unknown }).message)
    }
  } catch {
    /* body was not JSON */
  }
  return text.slice(0, 400) || `${res.status} ${res.statusText}`
}

async function readJson(res: Response, onDelta?: (fullText: string) => void): Promise<{ text: string; usage: UsageInfo | null }> {
  const payload: unknown = await res.json()
  assertNoInlineError(payload)
  const choice = (payload as { choices?: Array<{ message?: { content?: string } }> }).choices?.[0]
  const usageRaw = (payload as { usage?: { prompt_tokens?: number; completion_tokens?: number } }).usage
  const text = (choice?.message?.content ?? '').trim()
  if (!text) {
    const reason = (choice as { finish_reason?: string } | undefined)?.finish_reason
    throw new AiError(reason === 'length' ? 'Model hết token trước khi trả lời (tăng Max tokens).' : 'Câu trả lời rỗng từ model', res.status)
  }
  onDelta?.(text)
  return {
    text,
    usage: usageRaw
      ? { promptTokens: usageRaw.prompt_tokens ?? 0, completionTokens: usageRaw.completion_tokens ?? 0 }
      : null
  }
}

/** Some compatible proxies answer HTTP 200 with an { error } body. */
function assertNoInlineError(payload: unknown): void {
  if (!payload || typeof payload !== 'object' || !('error' in payload)) return
  const err = (payload as { error: unknown }).error
  const message =
    typeof err === 'string'
      ? err
      : err && typeof err === 'object'
        ? String((err as { message?: string }).message ?? 'unknown')
        : 'unknown'
  throw new AiError(message, 200)
}

function authHeaders(apiKey: string, extra: Record<string, string> = {}): Record<string, string> {
  return { ...extra, ...(apiKey ? { authorization: `Bearer ${apiKey}` } : {}) }
}

interface ChatRequestOptions {
  cfg: ResolvedAi
  messages: ChatMessage[]
  onDelta?: (fullText: string) => void
  effortOverride?: string | null
}

async function chatOnce(options: ChatRequestOptions): Promise<{ text: string; usage: UsageInfo | null }> {
  const { cfg, messages, onDelta } = options
  const effort = options.effortOverride === undefined ? cfg.reasoningEffort : options.effortOverride

  const body: Record<string, unknown> = {
    model: cfg.model,
    messages,
    [tokenField(cfg.model)]: cfg.maxTokens
  }
  if (effort && effort !== 'default' && openAiFamily(cfg.model)) {
    body.reasoning = { effort }
  }

  // Gateways differ: some stream only on request, others refuse SSE outright. When they
  // refuse, the same call is retried once without the flag so answers still arrive.
  const attempts = onDelta ? [true, false] : [false]
  let lastError: unknown = null
  for (const stream of attempts) {
    try {
      return await requestChat(cfg, body, stream, onDelta)
    } catch (error) {
      lastError = error
      const refused = error instanceof AiError && /stream/i.test(error.message)
      if (stream && refused) continue
      throw error
    }
  }
  throw lastError instanceof Error ? lastError : new AiError('Lượt gọi AI thất bại')
}

async function requestChat(
  cfg: ResolvedAi,
  body: Record<string, unknown>,
  stream: boolean,
  onDelta?: (fullText: string) => void
): Promise<{ text: string; usage: UsageInfo | null }> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), cfg.timeoutMs)
  try {
    const res = await fetch(`${cfg.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: authHeaders(cfg.apiKey, { 'content-type': 'application/json' }),
      body: JSON.stringify(stream ? { ...body, stream: true } : body),
      signal: controller.signal
    })
    if (!res.ok) throw new AiError(await errorMessage(res), res.status)
    // Many compatible gateways answer HTTP 200 + JSON even when streaming was refused,
    // so the shape is decided by the content type instead of by what we requested.
    const contentType = res.headers.get('content-type') ?? ''
    if (stream && contentType.includes('text/event-stream') && onDelta) return await readStream(res, onDelta)
    return await readJson(res, onDelta)
  } catch (error) {
    if (error instanceof AiError) throw error
    const message =
      error instanceof Error ? (error.name === 'AbortError' ? `Hết thời gian chờ sau ${cfg.timeoutMs} ms` : error.message) : String(error)
    throw new AiError(message)
  } finally {
    clearTimeout(timer)
  }
}

async function readStream(res: Response, onDelta: (full: string) => void): Promise<{ text: string; usage: UsageInfo | null }> {
  if (!res.body) throw new AiError('Endpoint không trả về stream', res.status)
  const reader = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''
  let full = ''

  for (;;) {
    const { value, done } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    let newline = buffer.indexOf('\n')
    while (newline >= 0) {
      const line = buffer.slice(0, newline).trim()
      buffer = buffer.slice(newline + 1)
      newline = buffer.indexOf('\n')
      if (!line.startsWith('data:')) continue
      const payload = line.slice(5).trim()
      if (!payload || payload === '[DONE]') continue
      try {
        const parsed: unknown = JSON.parse(payload)
        assertNoInlineError(parsed)
        const delta = (parsed as { choices?: Array<{ delta?: { content?: string } }> }).choices?.[0]?.delta?.content
        if (typeof delta === 'string' && delta) {
          full += delta
          onDelta(full)
        }
      } catch {
        /* ignore keep-alive and partial frames */
      }
    }
  }

  if (!full.trim()) throw new AiError('Stream không có nội dung', 204)
  return { text: full.trim(), usage: null }
}

async function transcribeOnce(cfg: ResolvedAi, wav: Uint8Array): Promise<{ text: string; language: string }> {
  const form = new FormData()
  form.append('file', new Blob([Buffer.from(wav)], { type: 'audio/wav' }), 'bubble.wav')
  form.append('model', cfg.sttModel)
  form.append('response_format', 'json')

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), Math.max(cfg.timeoutMs, 30000))
  try {
    const res = await fetch(`${cfg.baseUrl}/audio/transcriptions`, {
      method: 'POST',
      headers: authHeaders(cfg.apiKey),
      body: form,
      signal: controller.signal
    })
    if (!res.ok) throw new AiError(await errorMessage(res), res.status)
    const payload: unknown = await res.json()
    assertNoInlineError(payload)
    const record = payload as { text?: string; language?: string }
    return { text: (record.text ?? '').trim(), language: record.language ?? '' }
  } catch (error) {
    if (error instanceof AiError) throw error
    throw new AiError(error instanceof Error ? error.message : String(error))
  } finally {
    clearTimeout(timer)
  }
}

export async function listModels(cfg: ResolvedAi): Promise<ModelListing> {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 15000)
  try {
    const res = await fetch(`${cfg.baseUrl}/models`, { headers: authHeaders(cfg.apiKey), signal: controller.signal })
    if (!res.ok) return { ok: false, error: await errorMessage(res), models: [] }
    const payload: unknown = await res.json()
    assertNoInlineError(payload)
    const data = (payload as { data?: Array<{ id?: string; capabilities?: { supports_vision?: boolean } }> }).data ?? []
    const models = data
      .filter((item): item is { id: string; capabilities?: { supports_vision?: boolean } } => typeof item.id === 'string')
      .map((item) => ({ id: item.id, vision: item.capabilities?.supports_vision !== false }))
      .sort((a, b) => a.id.localeCompare(b.id))
    return { ok: true, error: null, models }
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error), models: [] }
  } finally {
    clearTimeout(timer)
  }
}

export interface AnalysisInput {
  question: string
  screenshotDataUrl?: string | null
  audioWav?: Uint8Array | null
  audioDurationMs?: number
}

export interface AnalysisResult {
  answer: string
  transcript: string
  strategyUsed: AnalysisStrategy
  usage: UsageInfo | null
  sttMs: number
  aiMs: number
  warnings: string[]
}

function userText(input: AnalysisInput, transcript: string): string {
  const parts: string[] = []
  if (transcript) parts.push(`Giọng nói của người dùng (bản ghi thành chữ): "${transcript}"`)
  if (input.question.trim()) parts.push(`Câu hỏi người dùng gõ: "${input.question.trim()}"`)
  if (!parts.length) {
    parts.push('Người dùng bấm phím nóng nhưng không nói gì. Đọc màn hình và nêu ngắn gọn thứ họ có thể cần ngay lúc này (tối đa 2 câu).')
  }
  if (input.screenshotDataUrl) parts.push('Ảnh chụp màn hình tại đúng khoảnh khắc bấm phím nóng được đính kèm.')
  return parts.join('\n')
}

function userContent(input: AnalysisInput, transcript: string, withAudio: boolean): ChatContentPart[] {
  const content: ChatContentPart[] = [{ type: 'text', text: userText(input, transcript) }]
  if (input.screenshotDataUrl) {
    content.push({ type: 'image_url', image_url: { url: input.screenshotDataUrl, detail: 'auto' } })
  }
  if (withAudio && input.audioWav) {
    content.push({
      type: 'input_audio',
      input_audio: { data: toBase64(input.audioWav), format: 'wav' }
    })
  }
  return content
}

function toBase64(bytes: Uint8Array): string {
  return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength).toString('base64')
}

function messagesFor(input: AnalysisInput, cfg: ResolvedAi, transcript: string, withAudio: boolean): ChatMessage[] {
  return [
    { role: 'system', content: cfg.systemPrompt },
    { role: 'user', content: userContent(input, transcript, withAudio) }
  ]
}

/**
 * One analysis turn. `multimodal` sends audio + screenshot in a single call and
 * degrades to transcription when the endpoint refuses the audio part.
 */
export async function analyze(
  cfg: ResolvedAi,
  input: AnalysisInput,
  onDelta?: (full: string) => void
): Promise<AnalysisResult> {
  const warnings: string[] = []
  let sttMs = 0
  let transcript = ''

  if (cfg.strategy === 'multimodal' && input.audioWav) {
    const aiStart = Date.now()
    try {
      const result = await chatOnce({ cfg, messages: messagesFor(input, cfg, '', true), onDelta })
      return {
        answer: result.text,
        transcript: '',
        strategyUsed: 'multimodal',
        usage: result.usage,
        sttMs: 0,
        aiMs: Date.now() - aiStart,
        warnings
      }
    } catch (error) {
      if (!(error instanceof AiError)) throw error
      warnings.push(`Lượt gọi đa phương thức thất bại (${error.message}); thử lại theo đường ghi âm → chữ.`)
    }
  }

  if (input.audioWav && !transcript) {
    const sttStart = Date.now()
    try {
      const spoken = await transcribeOnce(cfg, input.audioWav)
      transcript = spoken.text
      if (!transcript) warnings.push('Ghi âm không ra chữ (im lặng, quá ngắn hoặc quá nhiễu).')
    } catch (error) {
      warnings.push(`Không chuyển được ghi âm thành chữ: ${error instanceof Error ? error.message : String(error)}`)
    }
    sttMs = Date.now() - sttStart
  }

  const aiStart = Date.now()
  try {
    const result = await chatOnce({ cfg, messages: messagesFor(input, cfg, transcript, false), onDelta })
    return {
      answer: result.text,
      transcript,
      strategyUsed: cfg.strategy,
      usage: result.usage,
      sttMs,
      aiMs: Date.now() - aiStart,
      warnings
    }
  } catch (error) {
    if (error instanceof AiError && error.effortRejected && cfg.reasoningEffort !== 'default') {
      warnings.push(`Model không nhận reasoning effort "${cfg.reasoningEffort}"; đã thử lại mà không dùng.`)
      const retry = await chatOnce({
        cfg,
        messages: messagesFor(input, cfg, transcript, false),
        onDelta,
        effortOverride: null
      })
      return {
        answer: retry.text,
        transcript,
        strategyUsed: cfg.strategy,
        usage: retry.usage,
        sttMs,
        aiMs: Date.now() - aiStart,
        warnings
      }
    }
    throw error
  }
}

export async function testConnection(cfg: ResolvedAi): Promise<ConnectionTest> {
  const started = Date.now()
  const listing = await listModels(cfg)
  if (!listing.ok) {
    return { ok: false, latencyMs: Date.now() - started, models: 0, detail: listing.error ?? 'Không đọc được danh sách model' }
  }
  const probe: ResolvedAi = { ...cfg, maxTokens: 64, reasoningEffort: 'default' }
  try {
    const result = await chatOnce({
      cfg: probe,
      messages: [
        { role: 'system', content: 'Reply with exactly: OK' },
        { role: 'user', content: 'ping' }
      ]
    })
    return {
      ok: true,
      latencyMs: Date.now() - started,
      models: listing.models.length,
      detail: `${cfg.model} trả lời: "${result.text.slice(0, 40) || '(rỗng)'}"`
    }
  } catch (error) {
    return {
      ok: false,
      latencyMs: Date.now() - started,
      models: listing.models.length,
      detail: error instanceof Error ? error.message : String(error)
    }
  }
}
