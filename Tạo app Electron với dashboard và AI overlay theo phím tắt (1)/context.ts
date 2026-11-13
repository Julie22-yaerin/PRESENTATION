import { createContext, useContext } from 'react'
import type { CaptureRecord, HealthReport, ModelListing, SessionSnapshot, SettingsBundle } from '../../../shared/types'

export type TabId = 'overview' | 'history' | 'settings' | 'guide'

export interface Toast {
  message: string
  tone: 'info' | 'ok' | 'warn'
}

export interface AppState {
  bundle: SettingsBundle | null
  health: HealthReport | null
  records: CaptureRecord[]
  snapshot: SessionSnapshot
  models: ModelListing | null
  busy: string | null
  toast: Toast | null
  /** True while the main process waits for the user to press a key to bind. */
  learning: boolean
  selectedId: string | null
  tab: TabId
  setTab: (tab: TabId) => void
  select: (id: string | null) => void
  notify: (message: string, tone?: Toast['tone']) => void
  actions: {
    save: (patch: Parameters<Window['bubble']['saveSettings']>[0]) => Promise<void>
    setApiKey: (key: string) => Promise<void>
    clearApiKey: () => Promise<void>
    loadModels: () => Promise<void>
    testConnection: () => Promise<void>
    refreshHealth: () => Promise<void>
    toggleSession: () => Promise<void>
    cancelSession: () => Promise<void>
    askText: (text: string) => Promise<void>
    removeRecord: (id: string) => Promise<void>
    clearRecords: () => Promise<void>
    pinRecord: (id: string, pinned: boolean) => Promise<void>
    exportRecords: () => Promise<void>
    openDataFolder: () => Promise<void>
    showOverlay: (visible: boolean) => Promise<void>
    resetOverlayPosition: () => Promise<void>
    learnKey: (enable: boolean) => Promise<void>
  }
}

export const AppContext = createContext<AppState | null>(null)

export function useApp(): AppState {
  const value = useContext(AppContext)
  if (!value) throw new Error('useApp must be used inside AppProvider')
  return value
}
