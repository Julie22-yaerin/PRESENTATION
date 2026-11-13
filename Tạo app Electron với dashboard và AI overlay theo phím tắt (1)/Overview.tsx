import { useEffect, useState } from 'react'
import { useApp } from '../context'
import { Badge, Button, Card, Empty, Key, Stat, StatusDot } from '../components'
import { PHASE_LABEL, SOURCE_LABEL, formatDuration, formatTime, isToday, timeAgo } from '../../lib/format'

function useTicker(active: boolean): number {
  const [now, setNow] = useState(Date.now())
  useEffect(() => {
    if (!active) return
    const timer = window.setInterval(() => setNow(Date.now()), 200)
    return () => window.clearInterval(timer)
  }, [active])
  return now
}

export function Overview() {
  const { snapshot, health, records, bundle, actions, busy, setTab, select } = useApp()
  const runtime = bundle?.runtime
  const listening = snapshot.phase === 'listening'
  const now = useTicker(listening)
  const liveMs = listening && snapshot.startedAt ? now - snapshot.startedAt : snapshot.recordingMs

  const today = records.filter((record) => isToday(record.createdAt))
  const done = records.filter((record) => record.status === 'done')
  const avgAi = done.length ? done.reduce((sum, record) => sum + record.timings.aiMs, 0) / done.length : 0
  const audioSeconds = records.reduce((sum, record) => sum + (record.audio?.durationMs ?? 0), 0) / 1000
  const errors = records.filter((record) => record.status === 'error').length

  const healthRows = health
    ? [
        { label: 'API key', tone: health.key.ok ? 'ok' : 'error', detail: health.key.detail },
        { label: 'AI endpoint', tone: health.ai.ok ? 'ok' : 'warn', detail: health.ai.detail },
        { label: 'Microphone', tone: health.mic.ok ? 'ok' : 'warn', detail: health.mic.detail },
        { label: 'Chụp màn hình', tone: health.screen.ok ? 'ok' : 'error', detail: health.screen.detail },
        {
          label: 'Phím nóng',
          tone: health.hotkey.ok ? 'ok' : 'warn',
          detail: `${health.hotkey.detail} · nhân: ${health.hotkey.engine}`
        }
      ]
    : []

  return (
    <div className="overview">
      <div className="overview-main">
        <Card className="hero">
          <div className="hero-left">
            <span className={`hero-dot tone-${snapshot.phase}`} />
            <div>
              <p className="hero-kicker">{PHASE_LABEL[snapshot.phase]}</p>
              <h2 className="hero-title">
                {snapshot.phase === 'listening'
                  ? `Đang nghe ${formatDuration(liveMs)}`
                  : snapshot.phase === 'thinking'
                    ? 'Đang phân tích màn hình + giọng nói'
                    : snapshot.phase === 'answer'
                      ? (snapshot.answer.split('\n').find(Boolean) ?? 'Đã có kết quả')
                      : snapshot.phase === 'error'
                        ? (snapshot.error ?? 'Có lỗi xảy ra')
                        : 'Bong bóng đang chờ ngoài màn hình'}
              </h2>
              <p className="hero-sub">
                {snapshot.triggerLabel ? `Kích hoạt bởi ${snapshot.triggerLabel} · ` : ''}
                {snapshot.hasScreenshot ? 'đã thấy màn hình' : 'chưa có ảnh'} ·{' '}
                {snapshot.hasAudio || listening ? 'đang có âm thanh' : 'chưa có âm thanh'}
              </p>
            </div>
          </div>
          <div className="hero-actions">
            {listening || snapshot.phase === 'arming' || snapshot.phase === 'thinking' ? (
              <Button onClick={() => void actions.cancelSession()} variant="ghost" disabled={busy === 'session'}>
                Hủy phiên
              </Button>
            ) : null}
            <Button
              variant="primary"
              onClick={() => void actions.toggleSession()}
              disabled={snapshot.phase === 'thinking' || busy === 'session'}
            >
              {listening ? 'Dừng & gửi AI' : 'Nghe + nhìn màn hình ngay'}
            </Button>
          </div>
        </Card>

        <Card
          title="Cách gọi AI"
          subtitle={
            runtime?.hotkey.detail ??
            'Đang đọc cấu hình phím nóng…'
          }
          actions={<Button onClick={() => setTab('settings')}>Đổi phím</Button>}
        >
          <div className="howto">
            <div className="howto-step">
              <span className="howto-index">1</span>
              <div>
                <p className="howto-title">
                  Bấm <Key>{runtime?.hotkey.keyLabel || '⇧⇧'}</Key> để bật
                </p>
                <p className="howto-text">App chụp màn hình đúng khoảnh khắc đó và bắt đầu ghi âm.</p>
              </div>
            </div>
            <div className="howto-step">
              <span className="howto-index">2</span>
              <div>
                <p className="howto-title">Nói câu hỏi của bạn</p>
                <p className="howto-text">
                 VD: “Sao biểu đồ này tụt?” · hoặc gõ vào bong bóng nếu đang ở nơi không tiện nói.
                </p>
              </div>
            </div>
            <div className="howto-step">
              <span className="howto-index">3</span>
              <div>
                <p className="howto-title">
                  Bấm <Key>{runtime?.hotkey.keyLabel || '⇧⇧'}</Key> lần nữa để gửi
                </p>
                <p className="howto-text">
                  Câu trả lời hiện ngay trong bong bóng. Phím dự phòng: <Key>{runtime?.hotkey.shortcut || 'Alt+Shift+Space'}</Key>
                </p>
              </div>
            </div>
          </div>
        </Card>

        <Card
          title="Phiên gần đây"
          actions={<Button onClick={() => setTab('history')}>Xem tất cả</Button>}
        >
          {records.length === 0 ? (
            <Empty title="Chưa có phiên nào" hint="Bấm phím nóng ngoài màn hình để tạo phiên đầu tiên." />
          ) : (
            <ul className="recent-list">
              {records.slice(0, 6).map((record) => (
                <li key={record.id}>
                  <button
                    type="button"
                    className="recent-item"
                    onClick={() => {
                      select(record.id)
                      setTab('history')
                    }}
                  >
                    <span className={`recent-status tone-${record.status === 'done' ? 'ok' : 'error'}`} />
                    <span className="recent-time">{formatTime(record.createdAt)}</span>
                    <span className="recent-text">{(record.answer || record.question || record.error || '—').split('\n')[0]}</span>
                    <span className="recent-meta">
                      {SOURCE_LABEL[record.source]} · {timeAgo(record.createdAt)}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <aside className="overview-side">
        <Card
          title="Sức khỏe hệ thống"
          actions={
            <Button onClick={() => void actions.refreshHealth()} disabled={busy === 'health'}>
              {busy === 'health' ? 'Đang kiểm tra…' : 'Kiểm tra lại'}
            </Button>
          }
        >
          {healthRows.length === 0 ? (
            <p className="muted">Đang đo…</p>
          ) : (
            <ul className="health-list">
              {healthRows.map((row) => (
                <li key={row.label} className="health-row">
                  <StatusDot tone={row.tone as 'ok' | 'warn' | 'error'} />
                  <div>
                    <p className="health-label">{row.label}</p>
                    <p className="health-detail">{row.detail}</p>
                  </div>
                </li>
              ))}
            </ul>
          )}
          {health && health.sessionType === 'wayland' ? (
            <p className="note">Wayland chặn hook bàn phím toàn cục — dùng phím dự phòng hoặc chuyển sang X11.</p>
          ) : null}
        </Card>

        <Card title="Hôm nay">
          <div className="stat-grid">
            <Stat value={today.length} label="lượt hỏi" />
            <Stat value={formatDuration(avgAi)} label="AI phản hồi TB" />
            <Stat value={`${Math.round(audioSeconds / 60 * 10) / 10}m`} label="audio đã ghi" />
            <Stat value={errors} label="lỗi" />
          </div>
        </Card>

        <Card title="Máy">
          <ul className="kv-list">
            <li>
              <span>Hệ điều hành</span>
              <Badge>{runtime ? `${runtime.platform}/${runtime.arch}` : '—'}</Badge>
            </li>
            <li>
              <span>Electron</span>
              <Badge>{runtime?.electron ?? '—'}</Badge>
            </li>
            <li>
              <span>Model</span>
              <Badge tone="ok">{runtime?.effectiveModel ?? '—'}</Badge>
            </li>
            <li>
              <span>Endpoint</span>
              <Badge>{runtime?.effectiveBaseUrl ?? '—'}</Badge>
            </li>
            <li>
              <span>Màn hình</span>
              <Badge>{runtime?.displays.map((display) => display.label).join(' · ') ?? '—'}</Badge>
            </li>
          </ul>
        </Card>
      </aside>
    </div>
  )
}
