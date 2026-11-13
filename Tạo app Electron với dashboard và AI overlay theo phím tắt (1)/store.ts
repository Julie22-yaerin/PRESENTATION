import { app, safeStorage } from 'electron'
import { existsSync } from 'node:fs'
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { DEFAULT_SETTINGS, type AppSettings, type CaptureRecord } from '../shared/types'

const SETTINGS_FILE = 'settings.json'
const HISTORY_FILE = 'history.json'
const SECRET_FILE = 'ai-secret.bin'

let root = ''

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function mergeInto<T>(base: T, patch: unknown): T {
  if (!isRecord(base)) return (patch === undefined ? base : (patch as T))
  if (!isRecord(patch)) return base
  const out: Record<string, unknown> = { ...base }
  for (const [key, value] of Object.entries(patch)) {
    const current = out[key]
    out[key] = isRecord(current) && isRecord(value) ? mergeInto(current, value) : value
  }
  return out as T
}

/** Strip keys that are not part of the schema so a corrupted file cannot poison settings. */
function sanitize(settings: AppSettings): AppSettings {
  const cleaned = mergeInto(structuredClone(DEFAULT_SETTINGS), settings) as AppSettings
  cleaned.ai.baseUrl = cleaned.ai.baseUrl.trim().replace(/\/+$/, '')
  cleaned.ai.model = cleaned.ai.model.trim()
  cleaned.ai.sttModel = cleaned.ai.sttModel.trim() || DEFAULT_SETTINGS.ai.sttModel
  cleaned.capture.maxWidth = Math.min(7680, Math.max(480, Math.round(cleaned.capture.maxWidth)))
  cleaned.capture.jpegQuality = Math.min(98, Math.max(40, Math.round(cleaned.capture.jpegQuality)))
  cleaned.capture.maxRecordSeconds = Math.min(300, Math.max(3, Math.round(cleaned.capture.maxRecordSeconds)))
  cleaned.overlay.autoCollapseSeconds = Math.min(300, Math.max(4, Math.round(cleaned.overlay.autoCollapseSeconds)))
  cleaned.overlay.scale = Math.min(1.6, Math.max(0.8, Number(cleaned.overlay.scale) || 1))
  cleaned.general.keepHistoryCount = Math.min(1000, Math.max(10, Math.round(cleaned.general.keepHistoryCount)))
  cleaned.ai.maxTokens = Math.min(8000, Math.max(128, Math.round(cleaned.ai.maxTokens)))
  cleaned.version = DEFAULT_SETTINGS.version
  return cleaned
}

export async function initStore(): Promise<string> {
  root = app.getPath('userData')
  await mkdir(root, { recursive: true })
  await mkdir(artifactRoot(), { recursive: true })
  return root
}

export function userDataDir(): string {
  return root || app.getPath('userData')
}

export function artifactRoot(): string {
  return path.join(userDataDir(), 'captures')
}

export function artifactDir(id: string): string {
  return path.join(artifactRoot(), id)
}

let settingsCache: AppSettings | null = null

export async function getSettings(): Promise<AppSettings> {
  if (settingsCache) return settingsCache
  let loaded: AppSettings = structuredClone(DEFAULT_SETTINGS)
  try {
    const raw = await readFile(path.join(userDataDir(), SETTINGS_FILE), 'utf8')
    loaded = sanitize(mergeInto(structuredClone(DEFAULT_SETTINGS), JSON.parse(raw)))
  } catch {
    loaded = structuredClone(DEFAULT_SETTINGS)
  }
  settingsCache = loaded
  return loaded
}

export async function saveSettings(patch: Partial<AppSettings>): Promise<AppSettings> {
  const current = await getSettings()
  const next = sanitize(mergeInto(structuredClone(current), patch))
  settingsCache = next
  await writeFile(path.join(userDataDir(), SETTINGS_FILE), JSON.stringify(next, null, 2), 'utf8')
  return next
}

export async function replaceSettings(next: AppSettings): Promise<AppSettings> {
  const sanitized = sanitize(next)
  settingsCache = sanitized
  await writeFile(path.join(userDataDir(), SETTINGS_FILE), JSON.stringify(sanitized, null, 2), 'utf8')
  return sanitized
}

let historyCache: CaptureRecord[] | null = null

export async function listRecords(): Promise<CaptureRecord[]> {
  if (historyCache) return historyCache
  let records: CaptureRecord[] = []
  try {
    const raw = await readFile(path.join(userDataDir(), HISTORY_FILE), 'utf8')
    const parsed: unknown = JSON.parse(raw)
    if (Array.isArray(parsed)) records = parsed as CaptureRecord[]
  } catch {
    records = []
  }
  historyCache = records
  return records
}

async function persistRecords(records: CaptureRecord[]): Promise<CaptureRecord[]> {
  historyCache = records
  await writeFile(path.join(userDataDir(), HISTORY_FILE), JSON.stringify(records, null, 2), 'utf8')
  return records
}

export async function addRecord(record: CaptureRecord): Promise<CaptureRecord[]> {
  const records = await listRecords()
  const settings = await getSettings()
  const cap = Math.max(10, settings.general.keepHistoryCount)
  // The new record takes one slot, so everything from index cap-1 onward is dropped.
  const stale = records.slice(Math.max(0, cap - 1))
  const next = [record, ...records].slice(0, cap)
  for (const dropped of stale) await removeArtifacts(dropped.id)
  return persistRecords(next)
}

export async function removeRecord(id: string): Promise<CaptureRecord[]> {
  const records = await listRecords()
  await removeArtifacts(id)
  return persistRecords(records.filter((item) => item.id !== id))
}

export async function clearRecords(): Promise<CaptureRecord[]> {
  const records = await listRecords()
  for (const record of records) await removeArtifacts(record.id)
  return persistRecords([])
}

export async function setPinned(id: string, pinned: boolean): Promise<CaptureRecord[]> {
  const records = await listRecords()
  return persistRecords(records.map((item) => (item.id === id ? { ...item, pinned } : item)))
}

async function removeArtifacts(id: string): Promise<void> {
  await rm(artifactDir(id), { recursive: true, force: true }).catch(() => undefined)
}

export async function writeScreenshot(id: string, jpeg: Buffer): Promise<string> {
  const dir = artifactDir(id)
  await mkdir(dir, { recursive: true })
  const file = path.join(dir, 'screen.jpg')
  await writeFile(file, jpeg)
  return file
}

export async function writeAudio(id: string, wav: Buffer): Promise<string> {
  const dir = artifactDir(id)
  await mkdir(dir, { recursive: true })
  const file = path.join(dir, 'audio.wav')
  await writeFile(file, wav)
  return file
}

export type KeySource = 'vault' | 'env' | 'none'

export function secretStorageAvailable(): boolean {
  try {
    return safeStorage.isEncryptionAvailable()
  } catch {
    return false
  }
}

function envKey(): string {
  return (process.env.AIBUBBLE_API_KEY ?? process.env.OPENAI_API_KEY ?? '').trim()
}

/**
 * The API key never lands in settings.json. It is stored encrypted with the
 * OS credential store when available, otherwise only kept for this run.
 */
export async function getApiKey(): Promise<{ key: string; source: KeySource }> {
  const file = path.join(userDataDir(), SECRET_FILE)
  if (secretStorageAvailable() && existsSync(file)) {
    try {
      const decrypted = safeStorage.decryptString(await readFile(file))
      if (decrypted) return { key: decrypted, source: 'vault' }
    } catch {
      // Encrypted blob from another machine/user: fall through to env.
    }
  }
  const fromEnv = envKey()
  if (fromEnv) return { key: fromEnv, source: 'env' }
  return { key: '', source: 'none' }
}

export async function setApiKey(key: string): Promise<KeySource> {
  const trimmed = key.trim()
  const file = path.join(userDataDir(), SECRET_FILE)
  if (!trimmed) {
    await rm(file, { force: true }).catch(() => undefined)
    return envKey() ? 'env' : 'none'
  }
  if (!secretStorageAvailable()) return 'none'
  await writeFile(file, safeStorage.encryptString(trimmed))
  return 'vault'
}

export function envBaseUrl(): string {
  return (process.env.AIBUBBLE_BASE_URL ?? process.env.OPENAI_API_BASE ?? '').trim().replace(/\/+$/, '')
}
