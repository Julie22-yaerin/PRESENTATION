import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { AppContext, type AppState, type TabId, type Toast } from './context'
import { Overview } from './views/Overview'
import { History } from './views/History'
import { Settings } from './views/Settings'
import { Guide } from './views/Guide'
import { PHASE_LABEL, formatDuration, guessKeyName } from '../lib/format'
import { EMPTY_SESSION, type CaptureRecord, type HealthReport, type ModelListing, type SessionSnapshot, type SettingsBundle } from '../../../shared/types'

const TABS: Array<{ id: TabId; label: string; hint: string }> = [
  { id: 'overview', label: 'Tổng quan', hint: 'Trạng thái và sức khỏe' },
  { id: 'history', label: 'Lịch sử', hint: 'Ảnh, giọng nói, kết quả' },
  { id: 'settings', label: 'Cài đặt', hint: 'AI, phím nóng, bong bóng' },
  { id: 'guide', label: 'Hướng dẫn', hint: 'macOS · Windows · Linux' }
]

export function App() {
  const [tab, setTab] = useState<TabId>('overview')
  const [bundle, setBundle] = useState<SettingsBundle | null>(null)
  const [health, setHealth] = useState<HealthReport | null>(null)
  const [records, setRecords] = useState<CaptureRecord[]>([])
  const [snapshot, setSnapshot] = useState<SessionSnapshot>(EMPTY_SESSION)
  const [models, setModels] = useState<ModelListing | null>(null)
  const [busy, setBusy] = useState<string | null>(null)
  const [toast, setToast] = useState<Toast | null>(null)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [learning, setLearning] = useState(false)
  const learningRef = useRef(false)
  const toastTimer = useRef<number | null>(null)

  const notify = useCallback((message: string, tone: Toast['tone'] = 'info'): void => {
    setToast({ message, tone })
    if (toastTimer.current) window.clearTimeout(toastTimer.current)
    toastTimer.current = window.setTimeout(() => setToast(null), 4200)
  }, [])

  useEffect(() => {
    let cancelled = false
    void Promise.all([window.bubble.snapshot(), window.bubble.history(), window.bubble.settings(), window.bubble.health()]).then(
      ([nextSnapshot, nextRecords, nextBundle, nextHealth]) => {
        if (cancelled) return
        setSnapshot(nextSnapshot)
        setRecords(nextRecords)
        setBundle(nextBundle)
        setHealth(nextHealth)
      }
    )
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    const offSession = window.bubble.onSession(setSnapshot)
    const offRecords = window.bubble.onRecords(setRecords)
    const offFocus = window.bubble.onFocusRecord((id) => {
      setSelectedId(id)
      setTab('history')
    })
    return () => {
      offSession()
      offRecords()
      offFocus()
    }
  }, [])

  const refreshHealth = useCallback(async (): Promise<void> => {
    setBusy('health')
    try {
      setHealth(await window.bubble.health())
    } finally {
      setBusy(null)
    }
  }, [])

  const persist = useCallback(
    async (patch: Partial<SettingsBundle['settings']>): Promise<void> => {
      setBusy('save')
      try {
        const next = await window.bubble.saveSettings(patch)
        setBundle(next)
        setHealth(await window.bubble.health())
      } catch (error) {
        notify(`Không lưu được: ${error instanceof Error ? error.message : String(error)}`, 'warn')
      } finally {
        setBusy(null)
      }
    },
    [notify]
  )

  const learnKey = useCallback(
    async (enable: boolean): Promise<void> => {
      learningRef.current = enable
      setLearning(enable)
      if (!enable) {
        await window.bubble.learnKeyStop()
        return
      }
      await window.bubble.learnKeyStart()
      notify('Hãy bấm phím bạn muốn gán trong 12 giây tới', 'info')
      window.setTimeout(() => {
        if (learningRef.current) void learnKey(false)
      }, 12000)
    },
    [notify]
  )

  // Learn-key: the observer in main echoes exactly one keycode, then binding is saved.
  useEffect(() => {
    return window.bubble.onKeycode(async ({ keycode }) => {
      if (!learningRef.current) return
      learningRef.current = false
      setLearning(false)
      await window.bubble.learnKeyStop()
      const current = bundle?.settings
      if (!current) return
      await persist({
        hotkey: { ...current.hotkey, keyId: 'custom', customKeycode: keycode, customKeyLabel: guessKeyName(keycode) }
      })
      notify(`Đã gán ${guessKeyName(keycode)} (mã ${keycode}) — đừng quên Lưu kiểu bấm`, 'ok')
    })
  }, [bundle?.settings, notify, persist])

  const runSession = useCallback(
    async (action: 'toggle' | 'cancel'): Promise<void> => {
      setBusy('session')
      try {
        if (action === 'toggle') await window.bubble.toggle('dashboard')
        else await window.bubble.cancel()
        setSnapshot(await window.bubble.snapshot())
      } finally {
        setBusy(null)
      }
    },
    []
  )

  const value = useMemo<AppState>(
    () => ({
      bundle,
      health,
      records,
      snapshot,
      models,
      busy,
      toast,
      learning,
      selectedId,
      tab,
      setTab,
      select: setSelectedId,
      notify,
      actions: {
        save: persist,
        setApiKey: async (key) => {
          setBusy('key')
          try {
            const result = await window.bubble.setApiKey(key)
            setBundle((current) => (current ? { ...current, runtime: result.runtime } : current))
            setHealth(await window.bubble.health())
          } finally {
            setBusy(null)
          }
        },
        clearApiKey: async () => {
          const result = await window.bubble.clearApiKey()
          setBundle((current) => (current ? { ...current, runtime: result.runtime } : current))
          setHealth(await window.bubble.health())
        },
        loadModels: async () => {
          setBusy('models')
          try {
            const listing = await window.bubble.listModels()
            setModels(listing)
            if (!listing.ok) notify(`Không tải được model: ${listing.error}`, 'warn')
            else notify(`Tìm thấy ${listing.models.length} model tại endpoint`, 'ok')
          } finally {
            setBusy(null)
          }
        },
        testConnection: async () => {
          setBusy('test')
          try {
            const result = await window.bubble.testConnection()
            notify(result.ok ? `Kết nối OK · ${result.latencyMs}ms` : `Kết nối lỗi · ${result.detail}`, result.ok ? 'ok' : 'warn')
          } finally {
            setBusy(null)
          }
        },
        refreshHealth,
        toggleSession: () => runSession('toggle'),
        cancelSession: () => runSession('cancel'),
        askText: async (text) => {
          await window.bubble.askText(text)
        },
        removeRecord: async (id) => {
          setRecords(await window.bubble.deleteRecord(id))
          if (selectedId === id) setSelectedId(null)
        },
        clearRecords: async () => {
          setRecords(await window.bubble.clearHistory())
          setSelectedId(null)
          notify('Đã xoá toàn bộ lịch sử và tệp đi kèm', 'ok')
        },
        pinRecord: async (id, pinned) => {
          setRecords(await window.bubble.togglePin(id, pinned))
        },
        exportRecords: async () => {
          const result = await window.bubble.exportHistory()
          if (result.ok) notify(`Đã xuất ra ${result.path}`, 'ok')
        },
        openDataFolder: async () => {
          const message = await window.bubble.openDataFolder()
          if (!message.startsWith('/') && !message.includes(':\\')) notify(message, 'warn')
        },
        showOverlay: async (visible) => {
          await window.bubble.showOverlay(visible)
        },
        resetOverlayPosition: async () => {
          await window.bubble.moveOverlay('reset')
          notify('Đã đưa bong bóng về góc dưới phải', 'ok')
        },
        learnKey
      }
    }),
    [bundle, health, records, snapshot, models, busy, toast, learning, selectedId, tab, notify, persist, refreshHealth, runSession, learnKey]
  )

  const activeSession = snapshot.phase !== 'idle'

  return (
    <AppContext.Provider value={value}>
      <div className="app">
        <aside className="sidebar">
          <div className="brand">
            <span className="brand-mark" aria-hidden>
              <svg viewBox="0 0 32 32" width="24" height="24">
                <circle cx="16" cy="16" r="10" fill="none" stroke="currentColor" strokeWidth="2.4" strokeDasharray="46 17" strokeLinecap="round" />
                <circle cx="16" cy="16" r="2.8" fill="currentColor" />
              </svg>
            </span>
            <div>
              <p className="brand-name">AI Bubble</p>
              <p className="brand-sub">nghe · nhìn · trả lời</p>
            </div>
          </div>

          <nav className="nav">
            {TABS.map((item) => (
              <button key={item.id} type="button" className={`nav-item ${tab === item.id ? 'is-active' : ''}`} onClick={() => setTab(item.id)}>
                <span className="nav-label">{item.label}</span>
                <span className="nav-hint">{item.hint}</span>
              </button>
            ))}
          </nav>

          <div className={`side-status ${activeSession ? 'is-live' : ''}`}>
            <span className={`hero-dot tone-${snapshot.phase}`} />
            <div>
              <p className="side-status-title">{PHASE_LABEL[snapshot.phase]}</p>
              <p className="side-status-sub">
                {snapshot.phase === 'listening' ? formatDuration(snapshot.recordingMs) : `Bong bóng ${bundle?.runtime.trayAvailable ? '· có tray' : ''}`}
              </p>
            </div>
          </div>

          <p className="side-version">
            v{bundle?.runtime.appVersion ?? '0.1.0'} · Electron {bundle?.runtime.electron ?? '—'}
          </p>
        </aside>

        <main className="main">
          <header className="topbar">
            <div>
              <h1 className="page-title">{TABS.find((item) => item.id === tab)?.label}</h1>
              <p className="page-sub">{TABS.find((item) => item.id === tab)?.hint}</p>
            </div>
            <div className="topbar-actions">
              {snapshot.phase === 'listening' ? (
                <span className="live-chip">
                  <span className="live-dot" /> đang ghi {formatDuration(snapshot.recordingMs)}
                </span>
              ) : null}
              <button
                type="button"
                className="quick-toggle"
                onClick={() => void runSession('toggle')}
                disabled={snapshot.phase === 'thinking' || busy === 'session'}
              >
                {snapshot.phase === 'listening' ? 'Dừng & gửi AI' : 'Bắt đầu phiên mới'}
              </button>
            </div>
          </header>

          <div className="content">
            {tab === 'overview' ? <Overview /> : null}
            {tab === 'history' ? <History /> : null}
            {tab === 'settings' ? <Settings /> : null}
            {tab === 'guide' ? <Guide /> : null}
          </div>
        </main>

        {toast ? <div className={`toast tone-${toast.tone}`}>{toast.message}</div> : null}
      </div>
    </AppContext.Provider>
  )
}
