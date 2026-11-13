export const ASSET_SCHEME = 'aibubble'

/** main -> overlay */
export const OVERLAY_STATE = 'bubble:state'
export const OVERLAY_CMD = 'bubble:cmd'

/** overlay -> main */
export const OVERLAY_READY = 'bubble:ready'
export const OVERLAY_LEVEL = 'bubble:level'
export const OVERLAY_AUDIO = 'bubble:audio'
export const OVERLAY_MIC = 'bubble:microphone-report'
export const OVERLAY_RECORD_ERROR = 'bubble:record-error'
export const OVERLAY_ASK_TEXT = 'bubble:ask-text'
export const OVERLAY_INTERACTIVE = 'bubble:interactive'
export const OVERLAY_DRAG = 'bubble:drag'
export const OVERLAY_REQUEST = 'bubble:request'

/** main -> dashboard */
export const DASH_STATE = 'dash:state'
export const DASH_RECORDS = 'dash:records'
export const DASH_SETTINGS = 'dash:settings'
export const DASH_KEYCODE = 'dash:keycode'

/** renderers -> main (request/response) */
export const API = {
  getState: 'api:state',
  getSnapshot: 'api:snapshot',
  toggle: 'api:toggle',
  cancel: 'api:cancel',
  askText: 'api:ask-text',
  listHistory: 'api:history:list',
  deleteRecord: 'api:history:delete',
  clearHistory: 'api:history:clear',
  exportHistory: 'api:history:export',
  togglePin: 'api:history:pin',
  getSettings: 'api:settings:get',
  saveSettings: 'api:settings:save',
  setApiKey: 'api:key:set',
  clearApiKey: 'api:key:clear',
  listModels: 'api:models',
  testConnection: 'api:test',
  health: 'api:health',
  learnKeyStart: 'api:learn-key:start',
  learnKeyStop: 'api:learn-key:stop',
  moveOverlay: 'api:overlay:move',
  showOverlay: 'api:overlay:show',
  openDashboard: 'api:dashboard:open',
  assetUrl: 'api:asset-url',
  openDataFolder: 'api:open-data-folder',
  appInfo: 'api:app-info'
} as const

export type OverlayCommand =
  | { type: 'start' }
  | { type: 'stop' }
  | { type: 'collapse' }
  | { type: 'focus-input' }

export interface AudioPayload {
  /** Complete 16-bit mono WAV container produced by the overlay recorder. */
  wav: ArrayBuffer
  durationMs: number
  peak: number
  sampleRate: number
}

export interface AppInfo {
  version: string
  platform: NodeJS.Platform
  electron: string
  chrome: string
  userData: string
  secureStorage: boolean
  assetBase: string
}
