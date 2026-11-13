export type BubblePhase = 'idle' | 'arming' | 'listening' | 'thinking' | 'answer' | 'error'

export type HotkeyMode = 'single_tap' | 'double_tap'

export type AnalysisStrategy = 'multimodal' | 'transcribe_first'

export type TriggerSource = 'hotkey' | 'dashboard' | 'bubble'

export interface HotkeyKeyOption {
  id: string
  label: string
  glyph: string
  keycode: number | null
  hint?: string
}

export interface AppSettings {
  version: number
  ai: {
    baseUrl: string
    model: string
    sttModel: string
    strategy: AnalysisStrategy
    systemPrompt: string
    reasoningEffort: 'default' | 'minimal' | 'low' | 'medium' | 'high'
    maxTokens: number
    timeoutMs: number
  }
  hotkey: {
    enabled: boolean
    mode: HotkeyMode
    keyId: string
    customKeycode: number | null
    customKeyLabel: string
    fallbackShortcut: string
    fallbackEnabled: boolean
  }
  capture: {
    includeScreenshot: boolean
    maxWidth: number
    jpegQuality: number
    maxRecordSeconds: number
    display: 'cursor' | 'primary'
    deviceId: string
    beepOnToggle: boolean
  }
  overlay: {
    autoCollapseSeconds: number
    showTranscript: boolean
    x: number | null
    y: number | null
    scale: number
  }
  general: {
    keepHistoryCount: number
    launchAtLogin: boolean
    startHidden: boolean
  }
}

export const DEFAULT_SETTINGS: AppSettings = {
  version: 1,
  ai: {
    baseUrl: '',
    model: '',
    sttModel: 'whisper-1',
    strategy: 'multimodal',
    systemPrompt:
      'Bạn là AI Bubble: một trợ lý nhìn thấy màn hình và nghe thấy giọng nói của người dùng.\n' +
      'Người dùng vừa bấm phím nóng, nên bạn nhận được ảnh chụp màn hình tại ĐÚNG khoảnh khắc đó, kèm ghi âm câu hỏi của họ (nếu có).\n' +
      '- Trả lời bằng ngôn ngữ người dùng vừa nói. Nếu chỉ có ảnh, dùng ngôn ngữ của nội dung trên màn hình; nếu vẫn không rõ thì dùng tiếng Việt.\n' +
      '- Dòng đầu tiên là kết luận trong một câu. Chỉ thêm tối đa 3 gạch đầu dòng khi thật sự cần.\n' +
      '- Không mô tả lại màn hình nếu không được hỏi; trích xuất đúng dữ liệu người dùng cần.\n' +
      '- Nếu thiếu dữ kiện để trả lời, nói rõ còn thiếu gì thay vì đoán.',
    reasoningEffort: 'default',
    maxTokens: 800,
    timeoutMs: 45000
  },
  hotkey: {
    enabled: true,
    mode: 'double_tap',
    keyId: 'auto',
    customKeycode: null,
    customKeyLabel: '',
    fallbackShortcut: 'Alt+Shift+Space',
    fallbackEnabled: true
  },
  capture: {
    includeScreenshot: true,
    maxWidth: 1600,
    jpegQuality: 82,
    maxRecordSeconds: 60,
    display: 'cursor',
    deviceId: 'default',
    beepOnToggle: false
  },
  overlay: {
    autoCollapseSeconds: 24,
    showTranscript: true,
    x: null,
    y: null,
    scale: 1
  },
  general: {
    keepHistoryCount: 120,
    launchAtLogin: false,
    startHidden: false
  }
}

export const HOTKEY_KEYS: HotkeyKeyOption[] = [
  { id: 'auto', label: 'Tự động theo hệ điều hành', glyph: '⌘ / ⇧', keycode: null },
  { id: 'shift', label: 'Shift', glyph: '⇧', keycode: 42 },
  { id: 'shiftright', label: 'Shift phải', glyph: '⇧', keycode: 54 },
  { id: 'command', label: 'Command / Win / Super', glyph: '⌘', keycode: 3675 },
  { id: 'commandright', label: 'Command / Win phải', glyph: '⌘', keycode: 3676 },
  {
    id: 'fn',
    label: 'Fn (cần học phím)',
    glyph: 'fn',
    keycode: null,
    hint: 'macOS và nhiều bàn phím Windows không chuyển phím Fn cho ứng dụng. Bấm "Học phím" rồi nhấn Fn; nếu hệ thống không gửi tín hiệu, hãy dùng Command hoặc phím dự phòng.'
  },
  { id: 'ctrl', label: 'Ctrl', glyph: '⌃', keycode: 29 },
  { id: 'alt', label: 'Alt / Option', glyph: '⌥', keycode: 56 },
  { id: 'custom', label: 'Phím tuỳ chọn (bấm để học)', glyph: '🎯', keycode: null }
]

export interface ScreenshotMeta {
  file: string
  width: number
  height: number
  displayId: string
  bytes: number
}

export interface AudioMeta {
  file: string
  durationMs: number
  bytes: number
  peak: number
}

export interface CaptureRecord {
  id: string
  createdAt: number
  source: TriggerSource
  triggerLabel: string
  status: 'done' | 'error'
  strategyUsed: AnalysisStrategy
  screenshot: ScreenshotMeta | null
  audio: AudioMeta | null
  question: string
  transcript: string
  answer: string
  error: string | null
  usage: { promptTokens: number; completionTokens: number } | null
  timings: { captureMs: number; sttMs: number; aiMs: number; totalMs: number }
  pinned: boolean
}

export interface SessionSnapshot {
  phase: BubblePhase
  startedAt: number | null
  recordingMs: number
  audioLevel: number
  hasScreenshot: boolean
  hasAudio: boolean
  question: string
  transcript: string
  answer: string
  error: string | null
  lastRecordId: string | null
  triggerLabel: string
  autoCollapseSeconds: number
  showTranscript: boolean
}

export const EMPTY_SESSION: SessionSnapshot = {
  phase: 'idle',
  startedAt: null,
  recordingMs: 0,
  audioLevel: 0,
  hasScreenshot: false,
  hasAudio: false,
  question: '',
  transcript: '',
  answer: '',
  error: null,
  lastRecordId: null,
  triggerLabel: '',
  autoCollapseSeconds: DEFAULT_SETTINGS.overlay.autoCollapseSeconds,
  showTranscript: DEFAULT_SETTINGS.overlay.showTranscript
}

export interface HealthReport {
  checkedAt: number
  platform: string
  sessionType: string
  key: { ok: boolean; source: 'vault' | 'env' | 'none'; detail: string }
  ai: { ok: boolean; detail: string; models: number }
  mic: { ok: boolean; detail: string; devices: number }
  screen: { ok: boolean; detail: string; displays: number }
  hotkey: { ok: boolean; engine: string; detail: string }
}

export interface ModelListing {
  ok: boolean
  error: string | null
  models: Array<{ id: string; vision: boolean }>
}

export interface HotkeyStatusView {
  engine: string
  ok: boolean
  detail: string
  keyLabel: string
  shortcut: string
  listening: boolean
}

export interface DisplayView {
  id: string
  label: string
  scaleFactor: number
  isPrimary: boolean
  isCursor: boolean
}

export interface RuntimeInfo {
  platform: string
  arch: string
  appVersion: string
  electron: string
  chrome: string
  userData: string
  assetBase: string
  keySource: 'vault' | 'env' | 'none'
  hasKey: boolean
  secureStorage: boolean
  effectiveBaseUrl: string
  effectiveModel: string
  sessionType: string
  trayAvailable: boolean
  hotkey: HotkeyStatusView
  displays: DisplayView[]
}

export interface SettingsBundle {
  settings: AppSettings
  runtime: RuntimeInfo
}

export interface ConnectionTest {
  ok: boolean
  latencyMs: number
  models: number
  detail: string
}
export interface UsageInfo {
  promptTokens: number
  completionTokens: number
}

export interface MicReport {
  devices: number
  labels: string[]
  permission: string
  at: number
}
