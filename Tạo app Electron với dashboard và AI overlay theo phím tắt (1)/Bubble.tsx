import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { EMPTY_SESSION, type SessionSnapshot } from '../../../shared/types'
import { PHASE_LABEL } from '../lib/format'
import { Markdown } from '../lib/markdown'
import { useRecorder } from './useRecorder'

interface KeycapInfo {
  label: string
  shortcut: string
}

export function Bubble() {
  const [snapshot, setSnapshot] = useState<SessionSnapshot>(EMPTY_SESSION)
  const [keycap, setKeycap] = useState<KeycapInfo>({ label: '⇧⇧', shortcut: 'Alt+Shift+Space' })
  const [copied, setCopied] = useState(false)
  const [draft, setDraft] = useState('')
  const rootRef = useRef<HTMLDivElement | null>(null)
  const inputRef = useRef<HTMLTextAreaElement | null>(null)
  const hoverRef = useRef(false)
  const dragRef = useRef<{ x: number; y: number } | null>(null)
  const movedRef = useRef(false)

  const pushLevel = useCallback((level: number, elapsed: number) => {
    window.bubble.reportLevel(level, elapsed)
  }, [])

  const recorder = useRecorder(pushLevel)
  const { start, stop, cancel, active, level } = recorder

  // Recording is driven by the main process so hotkey, tray and dashboard share one path.
  useEffect(() => {
    return window.bubble.onCommand((command) => {
      if (command.type === 'start') {
        void window.bubble.audioDevices().then((devices) => {
          void start(devices[0]?.deviceId ?? 'default')
        })
      }
      if (command.type === 'stop') {
        const result = stop()
        if (result) {
          window.bubble.reportAudio({
            wav: result.wav.buffer as ArrayBuffer,
            durationMs: result.durationMs,
            peak: result.peak,
            sampleRate: result.sampleRate
          })
        } else {
          window.bubble.reportRecordError('Trình ghi chưa kịp khởi động nên không có âm thanh.')
        }
      }
      if (command.type === 'collapse') {
        cancel()
        setDraft('')
      }
      if (command.type === 'focus-input') {
        inputRef.current?.focus()
      }
    })
  }, [cancel, start, stop])

  useEffect(() => {
    const handler = (event: Event): void => setSnapshot((event as CustomEvent<SessionSnapshot>).detail)
    window.addEventListener('bubble:state', handler)
    window.bubble.overlayReady()
    void window.bubble.snapshot().then(setSnapshot)
    return () => window.removeEventListener('bubble:state', handler)
  }, [])

  useEffect(() => {
    let cancelled = false
    void window.bubble.appInfo().then((runtime) => {
      if (cancelled) return
      const label = runtime.hotkey.keyLabel && runtime.hotkey.keyLabel !== '—' ? runtime.hotkey.keyLabel : 'phím'
      setKeycap({ label, shortcut: runtime.hotkey.shortcut || 'Alt+Shift+Space' })
    })
    return () => {
      cancelled = true
    }
  }, [snapshot.phase])

  // A click-through window becomes interactive only while the pointer is over the bubble.
  useEffect(() => {
    const onMove = (event: MouseEvent): void => {
      const target = rootRef.current?.querySelector<HTMLElement>('[data-bubble-shell]')
      if (!target) return
      const rect = target.getBoundingClientRect()
      const inside =
        event.clientX >= rect.left && event.clientX <= rect.right && event.clientY >= rect.top && event.clientY <= rect.bottom
      if (inside === hoverRef.current) return
      hoverRef.current = inside
      window.bubble.setHover(inside)
    }
    window.addEventListener('mousemove', onMove)
    return () => window.removeEventListener('mousemove', onMove)
  }, [])

  const copyAnswer = useCallback(async (): Promise<void> => {
    if (!snapshot.answer) return
    await window.bubble.copyText(snapshot.answer)
    setCopied(true)
    window.setTimeout(() => setCopied(false), 1600)
  }, [snapshot.answer])

  useEffect(() => {
    const onKey = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') {
        window.bubble.request('collapse')
        return
      }
      const hasSelection = Boolean(window.getSelection()?.toString())
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'c' && !hasSelection && snapshot.answer) {
        event.preventDefault()
        void copyAnswer()
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [copyAnswer, snapshot.answer])

  const beginDrag = (event: React.PointerEvent): void => {
    if (event.button !== 0) return
    dragRef.current = { x: event.screenX, y: event.screenY }
    movedRef.current = false
    const onMove = (moveEvent: PointerEvent): void => {
      const last = dragRef.current
      if (!last) return
      const dx = moveEvent.screenX - last.x
      const dy = moveEvent.screenY - last.y
      dragRef.current = { x: moveEvent.screenX, y: moveEvent.screenY }
      if (dx || dy) {
        movedRef.current = true
        window.bubble.drag({ dx, dy })
      }
    }
    const onUp = (): void => {
      dragRef.current = null
      window.bubble.drag({ dx: 0, dy: 0, done: true })
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
    }
    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
  }

  const expanded = snapshot.phase !== 'idle' || active || Boolean(draft)
  const ring = Math.min(1, level * 1.4)

  const statusLine = useMemo(() => {
    switch (snapshot.phase) {
      case 'arming':
        return 'Đang bật mic và chụp màn hình…'
      case 'listening':
        return snapshot.hasScreenshot ? 'Đang nghe · đã thấy màn hình · bấm lại để dừng' : 'Đang nghe · bấm lại để dừng'
      case 'thinking':
        return 'Đang phân tích màn hình và giọng nói…'
      case 'answer':
        return `Bấm ${keycap.label} để hỏi tiếp`
      case 'error':
        return 'Chưa xong — xem chi tiết phía trên'
      default:
        return `Bấm ${keycap.label} để AI nghe và nhìn màn hình`
    }
  }, [keycap.label, snapshot.hasScreenshot, snapshot.phase])

  return (
    <div className="bubble-root" ref={rootRef}>
      <div className={`bubble-shell ${expanded ? 'is-expanded' : 'is-collapsed'} phase-${snapshot.phase}`} data-bubble-shell>
        {expanded ? (
          <section className="bubble-card" aria-live="polite">
            <header className="bubble-head" onPointerDown={beginDrag}>
              <span className={`dot dot-${snapshot.phase}`} />
              <span className="bubble-phase">{PHASE_LABEL[snapshot.phase]}</span>
              <span className="bubble-trigger">{snapshot.triggerLabel}</span>
              <button type="button" className="icon-btn" title="Đóng (Esc)" onClick={() => window.bubble.request('collapse')}>
                ×
              </button>
            </header>

            <div className="bubble-body">
              {snapshot.error ? <p className="bubble-error">{snapshot.error}</p> : null}

              {snapshot.transcript && snapshot.phase === 'answer' ? (
                <p className="bubble-transcript">
                  <span className="bubble-transcript-label">Bạn nói</span> “{snapshot.transcript}”
                </p>
              ) : null}

              {snapshot.phase === 'listening' ? (
                <div className="bubble-wave" aria-hidden>
                  {Array.from({ length: 22 }, (_, index) => (
                    <span
                      key={index}
                      className="wave-bar"
                      style={{
                        transform: `scaleY(${0.2 + Math.abs(Math.sin(index * 0.7 + level * 9)) * (0.3 + level * 2.1)})`
                      }}
                    />
                  ))}
                </div>
              ) : null}

              {snapshot.phase === 'thinking' ? <div className="bubble-scan" aria-hidden /> : null}

              {snapshot.answer ? (
                <div className="bubble-answer">
                  <Markdown source={snapshot.answer} className="md" />
                </div>
              ) : null}

              {snapshot.phase === 'error' ? (
                <p className="bubble-hint">
                  Phím dự phòng: <kbd>{keycap.shortcut}</kbd> · mọi thứ vẫn hoạt động khi gõ câu hỏi bên dưới.
                </p>
              ) : null}
            </div>

            <footer className="bubble-foot">
              <div className="bubble-status">{statusLine}</div>
              <div className="bubble-actions">
                <button type="button" className="ghost-btn" disabled={!snapshot.answer} onClick={() => void copyAnswer()}>
                  {copied ? 'Đã copy' : 'Copy'}
                </button>
                <button type="button" className="ghost-btn" onClick={() => window.bubble.request('open-dashboard')}>
                  Lịch sử
                </button>
              </div>
            </footer>

            <form
              className="bubble-composer"
              onSubmit={(event) => {
                event.preventDefault()
                const text = draft.trim()
                if (!text) return
                setDraft('')
                window.bubble.askFromBubble(text)
              }}
            >
              <textarea
                ref={inputRef}
                rows={1}
                value={draft}
                placeholder="Hoặc gõ câu hỏi về màn hình này…"
                onChange={(event) => setDraft(event.target.value)}
                onFocus={() => window.bubble.request('focus-input')}
                onKeyDown={(event) => {
                  if (event.key === 'Enter' && !event.shiftKey) {
                    event.preventDefault()
                    event.currentTarget.form?.requestSubmit()
                  }
                }}
              />
              <button type="submit" className="send-btn" disabled={!draft.trim()}>
                Gửi
              </button>
            </form>
          </section>
        ) : (
          <button
            type="button"
            className="bubble-pill"
            onPointerDown={beginDrag}
            onClick={() => {
              // A drag ends with a click too: only a stationary press should toggle a session.
              if (!movedRef.current) window.bubble.request('toggle')
            }}
            title={`Bấm ${keycap.label} để AI nghe + nhìn màn hình`}
          >
            <span className="pill-glow" aria-hidden />
            <span className="pill-ring" aria-hidden style={{ transform: `scale(${1 + ring * 0.45})`, opacity: 0.2 + ring * 0.6 }} />
            <span className="pill-mark" aria-hidden>
              <svg viewBox="0 0 32 32" width="26" height="26">
                <circle cx="16" cy="16" r="9.5" fill="none" stroke="currentColor" strokeWidth="2.2" strokeDasharray="44 16" strokeLinecap="round" />
                <circle cx="16" cy="16" r="2.6" fill="currentColor" />
              </svg>
            </span>
            <span className="pill-keycap">{keycap.label}</span>
          </button>
        )}
      </div>
    </div>
  )
}
