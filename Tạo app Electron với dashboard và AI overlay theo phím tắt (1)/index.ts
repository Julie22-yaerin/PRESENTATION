import { contextBridge, ipcRenderer } from 'electron'
import {
  API,
  DASH_KEYCODE,
  DASH_RECORDS,
  DASH_STATE,
  OVERLAY_ASK_TEXT,
  OVERLAY_AUDIO,
  OVERLAY_CMD,
  OVERLAY_DRAG,
  OVERLAY_INTERACTIVE,
  OVERLAY_LEVEL,
  OVERLAY_MIC,
  OVERLAY_READY,
  OVERLAY_RECORD_ERROR,
  OVERLAY_REQUEST,
  OVERLAY_STATE
} from '../shared/ipc'
import type { AudioPayload } from '../shared/ipc'
import type { AudioDeviceInfo, BubbleBridge, WindowRole } from '../shared/bridge'
import type { AppSettings, CaptureRecord, MicReport, SessionSnapshot, SettingsBundle } from '../shared/types'

const role: WindowRole = /overlay\.html/.test(location.href) ? 'overlay' : 'dashboard'

function subscribe<T>(channel: string, cb: (payload: T) => void): () => void {
  const listener = (_event: Electron.IpcRendererEvent, payload: T): void => cb(payload)
  ipcRenderer.on(channel, listener)
  return () => ipcRenderer.removeListener(channel, listener)
}

/**
 * Device labels only exist in the web layer, and only after microphone access has been
 * granted once, so enumeration happens here instead of in the main process.
 */
async function enumerateMicrophones(): Promise<AudioDeviceInfo[]> {
  try {
    const devices = await navigator.mediaDevices.enumerateDevices()
    return devices
      .filter((device) => device.kind === 'audioinput')
      .map((device, index) => ({ deviceId: device.deviceId, label: device.label || `Micro ${index + 1}` }))
  } catch {
    return []
  }
}

const bridge: BubbleBridge = {
  role,
  platform: process.platform,

  appInfo: () => ipcRenderer.invoke(API.appInfo),
  snapshot: (): Promise<SessionSnapshot> => ipcRenderer.invoke(API.getSnapshot),
  toggle: (origin) => ipcRenderer.invoke(API.toggle, origin),
  cancel: () => ipcRenderer.invoke(API.cancel),
  askText: (text) => ipcRenderer.invoke(API.askText, text),

  history: (): Promise<CaptureRecord[]> => ipcRenderer.invoke(API.listHistory),
  deleteRecord: (id) => ipcRenderer.invoke(API.deleteRecord, id),
  clearHistory: () => ipcRenderer.invoke(API.clearHistory),
  togglePin: (id, pinned) => ipcRenderer.invoke(API.togglePin, id, pinned),
  exportHistory: () => ipcRenderer.invoke(API.exportHistory),

  settings: (): Promise<SettingsBundle> => ipcRenderer.invoke(API.getSettings),
  saveSettings: (patch: Partial<AppSettings>) => ipcRenderer.invoke(API.saveSettings, patch),
  setApiKey: (key) => ipcRenderer.invoke(API.setApiKey, key),
  clearApiKey: () => ipcRenderer.invoke(API.clearApiKey),
  listModels: () => ipcRenderer.invoke(API.listModels),
  testConnection: () => ipcRenderer.invoke(API.testConnection),
  health: () => ipcRenderer.invoke(API.health),
  audioDevices: () => enumerateMicrophones(),

  learnKeyStart: () => ipcRenderer.invoke(API.learnKeyStart),
  learnKeyStop: () => ipcRenderer.invoke(API.learnKeyStop),

  assetUrl: (ref) => ipcRenderer.invoke(API.assetUrl, ref),
  moveOverlay: (position) => ipcRenderer.invoke(API.moveOverlay, position),
  showOverlay: (visible) => ipcRenderer.invoke(API.showOverlay, visible),
  openDashboard: () => ipcRenderer.invoke(API.openDashboard),
  openDataFolder: () => ipcRenderer.invoke(API.openDataFolder),

  copyText: async (text) => {
    await navigator.clipboard.writeText(text)
  },

  onSession: (cb) => subscribe(DASH_STATE, cb),
  onRecords: (cb) => subscribe(DASH_RECORDS, cb),
  onKeycode: (cb) => subscribe(DASH_KEYCODE, cb),
  onFocusRecord: (cb) => subscribe('dash:focus-record', cb),

  onCommand: (cb) => subscribe<{ type: string }>(OVERLAY_CMD, cb),
  overlayReady: () => ipcRenderer.send(OVERLAY_READY),
  reportLevel: (level, elapsedMs) => ipcRenderer.send(OVERLAY_LEVEL, level, elapsedMs),
  reportAudio: (payload: AudioPayload) => ipcRenderer.send(OVERLAY_AUDIO, payload),
  reportRecordError: (message) => ipcRenderer.send(OVERLAY_RECORD_ERROR, message),
  reportMic: (report: MicReport) => ipcRenderer.send(OVERLAY_MIC, report),
  askFromBubble: (text) => ipcRenderer.send(OVERLAY_ASK_TEXT, text),
  setHover: (hovering) => ipcRenderer.send(OVERLAY_INTERACTIVE, hovering),
  drag: (delta) => ipcRenderer.send(OVERLAY_DRAG, delta),
  request: (action) => ipcRenderer.send(OVERLAY_REQUEST, action)
}

contextBridge.exposeInMainWorld('bubble', bridge)

// The overlay renders from the session channel named for bubbles.
if (role === 'overlay') {
  subscribe<SessionSnapshot>(OVERLAY_STATE, (payload) => {
    window.dispatchEvent(new CustomEvent('bubble:state', { detail: payload }))
  })
}
