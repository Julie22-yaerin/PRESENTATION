import type { AppSettings, CaptureRecord, HealthReport, ModelListing, SessionSnapshot, SettingsBundle } from './types'
import type { MicReport } from './types'
import type { ConnectionTest } from './types'
import type { AudioPayload } from './ipc'

export type WindowRole = 'dashboard' | 'overlay'

export interface AudioDeviceInfo {
  deviceId: string
  label: string
}

export interface KeyLearningResult {
  keycode: number
  at: number
}

/** Surface exposed to both renderers as `window.bubble`. */
export interface BubbleBridge {
  role: WindowRole
  platform: string

  appInfo(): Promise<SettingsBundle['runtime']>
  snapshot(): Promise<SessionSnapshot>
  toggle(origin: 'dashboard' | 'bubble'): Promise<void>
  cancel(): Promise<void>
  askText(text: string): Promise<void>

  history(): Promise<CaptureRecord[]>
  deleteRecord(id: string): Promise<CaptureRecord[]>
  clearHistory(): Promise<CaptureRecord[]>
  togglePin(id: string, pinned: boolean): Promise<CaptureRecord[]>
  exportHistory(): Promise<{ ok: boolean; path: string }>

  settings(): Promise<SettingsBundle>
  saveSettings(patch: Partial<AppSettings>): Promise<SettingsBundle>
  setApiKey(key: string): Promise<{ source: string; runtime: SettingsBundle['runtime'] }>
  clearApiKey(): Promise<{ source: string; runtime: SettingsBundle['runtime'] }>
  listModels(): Promise<ModelListing>
  testConnection(): Promise<ConnectionTest>
  health(): Promise<HealthReport>
  /** Enumerated in the renderer: only the web layer can see real device labels. */
  audioDevices(): Promise<AudioDeviceInfo[]>

  learnKeyStart(): Promise<{ started: boolean; expires: number }>
  learnKeyStop(): Promise<boolean>

  assetUrl(ref: string): Promise<string>
  moveOverlay(position: { x: number; y: number } | 'reset'): Promise<{ x: number; y: number }>
  showOverlay(visible: boolean): Promise<boolean>
  openDashboard(): Promise<boolean>
  openDataFolder(): Promise<string>

  copyText(text: string): Promise<void>

  onSession(cb: (snapshot: SessionSnapshot) => void): () => void
  onRecords(cb: (records: CaptureRecord[]) => void): () => void
  onKeycode(cb: (result: KeyLearningResult) => void): () => void
  onFocusRecord(cb: (id: string) => void): () => void

  /** overlay only */
  onCommand(cb: (command: { type: string }) => void): () => void
  overlayReady(): void
  reportLevel(level: number, elapsedMs: number): void
  reportAudio(payload: AudioPayload): void
  reportRecordError(message: string): void
  reportMic(report: MicReport): void
  askFromBubble(text: string): void
  setHover(hovering: boolean): void
  drag(delta: { dx: number; dy: number; done?: boolean }): void
  request(action: 'toggle' | 'collapse' | 'focus-input' | 'open-dashboard'): void
}
