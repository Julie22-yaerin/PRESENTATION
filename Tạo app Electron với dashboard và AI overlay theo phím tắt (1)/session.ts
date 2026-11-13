import { randomUUID } from 'node:crypto'
import { EventEmitter } from 'node:events'
import { shell } from 'electron'
import { OVERLAY_CMD, OVERLAY_STATE, DASH_RECORDS, DASH_STATE } from '../shared/ipc'
import type { AudioPayload } from '../shared/ipc'
import {
  DEFAULT_SETTINGS,
  EMPTY_SESSION,
  type AppSettings,
  type CaptureRecord,
  type SessionSnapshot,
  type MicReport,
  type TriggerSource
} from '../shared/types'
import { analyze, resolveAi, type AnalysisInput } from './ai'
import { captureScreen } from './capture'
import type { DashboardWindow } from './dashboard'
import type { HotkeyService } from './hotkeys'
import type { OverlayController } from './overlay'
import * as store from './store'

interface SessionDeps {
  overlay: OverlayController
  dashboard: DashboardWindow
  hotkeys: HotkeyService
}

interface PendingAudio {
  resolve: (payload: AudioPayload | null) => void
  timer: NodeJS.Timeout
}

interface ShotState {
  dataUrl: string
  width: number
  height: number
  displayId: string
  bytes: number
  label: string
}

const BROADCAST_THROTTLE_MS = 55
const AUDIO_REQUEST_TIMEOUT_MS = 4000

/** Records store paths relative to userData so they survive a moved profile folder. */
function artifactRef(id: string, name: string): string {
  return `captures/${id}/${name}`
}

/**
 * Owns the whole hotkey → capture → AI → answer cycle. Both windows render from the
 * same snapshot so the dashboard always mirrors what the bubble is doing.
 */
export class CaptureSession extends EventEmitter {
  private state: SessionSnapshot = { ...EMPTY_SESSION }
  private settings: AppSettings = structuredClone(DEFAULT_SETTINGS)
  private shot: ShotState | null = null
  private recordId = ''
  private sessionStartedAt = 0
  private captureMs = 0
  private recordTimer: NodeJS.Timeout | null = null
  private collapseTimer: NodeJS.Timeout | null = null
  private pendingAudio: PendingAudio | null = null
  private lastBroadcast = 0
  private trailingBroadcast: NodeJS.Timeout | null = null
  private micReport: MicReport | null = null

  constructor(private readonly deps: SessionDeps) {
    super()
  }

  async loadSettings(): Promise<void> {
    this.settings = await store.getSettings()
    this.state.autoCollapseSeconds = this.settings.overlay.autoCollapseSeconds
  }

  get currentSettings(): AppSettings {
    return this.settings
  }

  applySettings(next: AppSettings): void {
    this.settings = next
    this.state.autoCollapseSeconds = next.overlay.autoCollapseSeconds
    this.broadcast()
  }

  snapshot(): SessionSnapshot {
    return { ...this.state, recordingMs: this.isRecording ? Date.now() - (this.state.startedAt ?? Date.now()) : this.state.recordingMs }
  }

  private get isRecording(): boolean {
    return this.state.phase === 'listening'
  }

  /** Single entry point for the hotkey, the tray and the dashboard button. */
  async toggle(source: TriggerSource, label: string): Promise<void> {
    if (this.state.phase === 'listening' || this.state.phase === 'arming') {
      await this.end(source, label)
      return
    }
    if (this.state.phase === 'thinking') {
      this.flashStatus('Đang phân tích lượt trước, hãy chờ vài giây.')
      return
    }
    await this.begin(source, label)
  }

  private clearTimers(): void {
    if (this.recordTimer) clearTimeout(this.recordTimer)
    this.recordTimer = null
    if (this.collapseTimer) clearTimeout(this.collapseTimer)
    this.collapseTimer = null
  }

  private async begin(source: TriggerSource, label: string): Promise<void> {
    this.clearTimers()
    this.recordId = randomUUID()
    this.shot = null
    this.sessionStartedAt = Date.now()
    this.captureMs = 0

    this.state = {
      ...EMPTY_SESSION,
      phase: 'arming',
      startedAt: this.sessionStartedAt,
      triggerLabel: label,
      autoCollapseSeconds: this.settings.overlay.autoCollapseSeconds
    }
    this.deps.overlay.setExpanded(true)
    this.broadcast(true)
    if (this.settings.capture.beepOnToggle) shell.beep()

    // Start the microphone first: the screenshot is taken while the recorder warms up.
    this.deps.overlay.send(OVERLAY_CMD, { type: 'start' })

    if (this.settings.capture.includeScreenshot) {
      const started = Date.now()
      try {
        const shot = await captureScreen({
          maxWidth: this.settings.capture.maxWidth,
          quality: this.settings.capture.jpegQuality,
          display: this.settings.capture.display
        })
        await store.writeScreenshot(this.recordId, shot.jpeg)
        this.shot = {
          dataUrl: `data:image/jpeg;base64,${shot.jpeg.toString('base64')}`,
          width: shot.width,
          height: shot.height,
          displayId: shot.displayId,
          bytes: shot.bytes,
          label: shot.label
        }
        this.state.hasScreenshot = true
      } catch (error) {
        this.state.error = error instanceof Error ? error.message : String(error)
      }
      this.captureMs = Date.now() - started
    }

    if (this.state.phase !== 'arming') return

    this.state.phase = 'listening'
    this.state.startedAt = Date.now()
    this.state.recordingMs = 0
    this.broadcast(true)

    this.recordTimer = setTimeout(() => {
      if (this.state.phase === 'listening') {
        this.flashStatus('Đã đạt giới hạn thời lượng ghi âm.')
        void this.end(source, label)
      }
    }, this.settings.capture.maxRecordSeconds * 1000)
  }

  private async end(source: TriggerSource, label: string): Promise<void> {
    if (this.recordTimer) clearTimeout(this.recordTimer)
    this.recordTimer = null
    if (this.state.phase !== 'listening' && this.state.phase !== 'arming') return

    const recordingMs = this.state.startedAt ? Date.now() - this.state.startedAt : 0
    this.state.phase = 'thinking'
    this.state.recordingMs = recordingMs
    this.broadcast(true)
    if (this.settings.capture.beepOnToggle) shell.beep()

    const payload = await this.requestAudio()
    if (payload?.wav.byteLength) {
      const buffer = Buffer.from(payload.wav)
      try {
        await store.writeAudio(this.recordId, buffer)
        this.state.hasAudio = true
      } catch {
        /* analysis still works with the in-memory buffer */
      }
      await this.runAnalysis({
        audioWav: new Uint8Array(buffer),
        audio: {
          file: 'audio.wav',
          durationMs: payload.durationMs || recordingMs,
          bytes: buffer.byteLength,
          peak: payload.peak
        },
        source,
        label,
        question: this.state.question
      })
      return
    }

    if (!this.state.question.trim()) {
      this.state.phase = 'error'
      this.state.error = payload === null
        ? 'Không lấy được ghi âm từ overlay (mic có thể bị chặn hoặc chưa có quyền).'
        : 'Không có âm thanh nào được ghi.'
      await this.finalizeError(label, source)
      this.broadcast(true)
      return
    }

    await this.runAnalysis({ audioWav: null, audio: null, source, label, question: this.state.question })
  }

  private requestAudio(): Promise<AudioPayload | null> {
    return new Promise((resolve) => {
      if (this.pendingAudio) clearTimeout(this.pendingAudio.timer)
      this.deps.overlay.send(OVERLAY_CMD, { type: 'stop' })
      const timer = setTimeout(() => {
        this.pendingAudio = null
        resolve(null)
      }, AUDIO_REQUEST_TIMEOUT_MS)
      this.pendingAudio = { resolve, timer }
    })
  }

  onAudioResult(payload: AudioPayload): void {
    const pending = this.pendingAudio
    this.pendingAudio = null
    if (!pending) return
    clearTimeout(pending.timer)
    pending.resolve(payload)
  }

  onRecordError(message: string): void {
    const pending = this.pendingAudio
    this.state.error = message
    if (!pending) return
    this.pendingAudio = null
    clearTimeout(pending.timer)
    pending.resolve(null)
  }

  /** The overlay measures real device access; the dashboard health card shows it. */
  reportMic(report: MicReport): void {
    this.micReport = report
  }

  get microphoneReport(): MicReport | null {
    return this.micReport
  }

  onLevel(level: number, elapsedMs: number): void {
    if (this.state.phase !== 'listening') return
    this.state.audioLevel = Math.max(0, Math.min(1, level))
    this.state.recordingMs = elapsedMs
    this.broadcast()
  }

  async cancel(): Promise<void> {
    this.clearTimers()
    if (this.state.phase === 'listening' || this.state.phase === 'arming') {
      this.deps.overlay.send(OVERLAY_CMD, { type: 'collapse' })
      this.pendingAudio = null
    }
    this.state = {
      ...EMPTY_SESSION,
      autoCollapseSeconds: this.settings.overlay.autoCollapseSeconds,
      lastRecordId: this.state.lastRecordId
    }
    this.deps.overlay.setExpanded(false)
    this.broadcast(true)
  }

  /** Text question: captures the screen when enabled, never needs the microphone. */
  async askText(text: string, source: TriggerSource = 'bubble'): Promise<void> {
    const question = text.trim()
    if (!question) return
    if (this.state.phase === 'listening') {
      this.state.question = question
      this.broadcast(true)
      await this.end(source, this.state.triggerLabel || 'nhập chữ')
      return
    }
    if (this.state.phase === 'thinking' || this.state.phase === 'arming') return

    this.clearTimers()
    this.recordId = randomUUID()
    this.shot = null
    this.sessionStartedAt = Date.now()
    this.captureMs = 0
    this.state = {
      ...EMPTY_SESSION,
      phase: 'thinking',
      startedAt: this.sessionStartedAt,
      question,
      triggerLabel: 'nhập chữ',
      autoCollapseSeconds: this.settings.overlay.autoCollapseSeconds
    }
    this.deps.overlay.setExpanded(true)
    this.broadcast(true)

    if (this.settings.capture.includeScreenshot) {
      const started = Date.now()
      try {
        const shot = await captureScreen({
          maxWidth: this.settings.capture.maxWidth,
          quality: this.settings.capture.jpegQuality,
          display: this.settings.capture.display
        })
        await store.writeScreenshot(this.recordId, shot.jpeg)
        this.shot = {
          dataUrl: `data:image/jpeg;base64,${shot.jpeg.toString('base64')}`,
          width: shot.width,
          height: shot.height,
          displayId: shot.displayId,
          bytes: shot.bytes,
          label: shot.label
        }
        this.state.hasScreenshot = true
      } catch (error) {
        this.state.error = error instanceof Error ? error.message : String(error)
      }
      this.captureMs = Date.now() - started
    }

    await this.runAnalysis({ audioWav: null, audio: null, source, label: 'nhập chữ', question })
  }

  private async runAnalysis(args: {
    audioWav: Uint8Array | null
    audio: CaptureRecord['audio']
    source: TriggerSource
    label: string
    question: string
  }): Promise<void> {
    const settings = this.settings
    const cfg = await resolveAi(settings)

    if (!cfg.apiKey) {
      this.state.phase = 'error'
      this.state.error =
        'Chưa có API key. Mở Dashboard → Cài đặt → AI để lưu key (mã hoá theo máy) hoặc đặt biến môi trường AIBUBBLE_API_KEY.'
      await this.finalizeError(args.label, args.source)
      this.broadcast(true)
      return
    }

    const input: AnalysisInput = {
      question: args.question,
      screenshotDataUrl: this.shot?.dataUrl ?? null,
      audioWav: args.audioWav,
      audioDurationMs: args.audio?.durationMs ?? 0
    }
    if (!input.screenshotDataUrl && !input.audioWav && !input.question.trim()) {
      this.state.phase = 'error'
      this.state.error = 'Không có gì để gửi cho AI (màn hình, âm thanh và câu hỏi đều trống).'
      await this.finalizeError(args.label, args.source)
      this.broadcast(true)
      return
    }

    try {
      const result = await analyze(cfg, input, (full) => {
        this.state.answer = full
        this.broadcast()
      })
      this.state.answer = result.answer
      this.state.transcript = result.transcript
      this.state.error = result.warnings.length ? result.warnings.join(' · ') : null
      this.state.phase = 'answer'

      const record: CaptureRecord = {
        id: this.recordId,
        createdAt: Date.now(),
        source: args.source,
        triggerLabel: args.label,
        status: 'done',
        strategyUsed: result.strategyUsed,
        screenshot: this.shot
          ? {
              file: artifactRef(this.recordId, 'screen.jpg'),
              width: this.shot.width,
              height: this.shot.height,
              displayId: this.shot.displayId,
              bytes: this.shot.bytes
            }
          : null,
        audio: args.audio ? { ...args.audio, file: artifactRef(this.recordId, 'audio.wav') } : null,
        question: args.question,
        transcript: result.transcript,
        answer: result.answer,
        error: result.warnings.length ? result.warnings.join(' · ') : null,
        usage: result.usage,
        timings: {
          captureMs: this.captureMs,
          sttMs: result.sttMs,
          aiMs: result.aiMs,
          totalMs: Date.now() - this.sessionStartedAt
        },
        pinned: false
      }
      await store.addRecord(record)
      this.state.lastRecordId = record.id
      this.deps.dashboard.send(DASH_RECORDS, await store.listRecords())
    } catch (error) {
      this.state.phase = 'error'
      this.state.error = error instanceof Error ? error.message : String(error)
      await this.finalizeError(args.label, args.source)
    }

    this.broadcast(true)
    this.scheduleCollapse()
  }

  private async finalizeError(label: string, source: TriggerSource): Promise<void> {
    const record: CaptureRecord = {
      id: this.recordId || randomUUID(),
      createdAt: Date.now(),
      source,
      triggerLabel: label,
      status: 'error',
      strategyUsed: this.settings.ai.strategy,
      screenshot: this.shot
        ? {
            file: artifactRef(this.recordId, 'screen.jpg'),
            width: this.shot.width,
            height: this.shot.height,
            displayId: this.shot.displayId,
            bytes: this.shot.bytes
          }
        : null,
      audio: null,
      question: this.state.question,
      transcript: this.state.transcript,
      answer: '',
      error: this.state.error ?? 'Không rõ nguyên nhân',
      usage: null,
      timings: { captureMs: this.captureMs, sttMs: 0, aiMs: 0, totalMs: Date.now() - this.sessionStartedAt },
      pinned: false
    }
    await store.addRecord(record).catch(() => undefined)
    this.deps.dashboard.send(DASH_RECORDS, await store.listRecords().catch(() => []))
    this.scheduleCollapse()
  }

  private scheduleCollapse(): void {
    if (this.collapseTimer) clearTimeout(this.collapseTimer)
    this.collapseTimer = setTimeout(() => {
      if (this.state.phase === 'answer' || this.state.phase === 'error') {
        this.deps.overlay.setExpanded(false)
        this.state = {
          ...EMPTY_SESSION,
          autoCollapseSeconds: this.settings.overlay.autoCollapseSeconds,
          lastRecordId: this.state.lastRecordId
        }
        this.broadcast(true)
      }
    }, this.settings.overlay.autoCollapseSeconds * 1000)
  }

  private flashStatus(message: string): void {
    this.state.error = message
    this.broadcast(true)
    setTimeout(() => {
      if (this.state.error === message) {
        this.state.error = null
        this.broadcast(true)
      }
    }, 3500)
  }

  private broadcast(immediate = false): void {
    const payload = this.snapshot()
    const send = (): void => {
      this.deps.overlay.send(OVERLAY_STATE, payload)
      this.deps.dashboard.send(DASH_STATE, payload)
    }
    if (immediate) {
      if (this.trailingBroadcast) clearTimeout(this.trailingBroadcast)
      this.trailingBroadcast = null
      this.lastBroadcast = Date.now()
      send()
      return
    }
    const since = Date.now() - this.lastBroadcast
    if (since >= BROADCAST_THROTTLE_MS) {
      this.lastBroadcast = Date.now()
      send()
    } else if (!this.trailingBroadcast) {
      this.trailingBroadcast = setTimeout(() => {
        this.trailingBroadcast = null
        this.lastBroadcast = Date.now()
        send()
      }, BROADCAST_THROTTLE_MS - since)
    }
  }
}
