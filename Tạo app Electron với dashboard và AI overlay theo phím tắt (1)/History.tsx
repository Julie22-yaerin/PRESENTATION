import { useEffect, useMemo, useState } from 'react'
import { useApp } from '../context'
import { Badge, Button, Card, Empty, Segmented } from '../components'
import { SOURCE_LABEL, formatBytes, formatDateTime, formatDuration, timeAgo } from '../../lib/format'
import { assetUrl } from '../../lib/asset'
import type { CaptureRecord } from '../../../../shared/types'

type Filter = 'all' | 'done' | 'error'

export function History() {
  const { records, bundle, actions, selectedId, select } = useApp()
  const [filter, setFilter] = useState<Filter>('all')
  const [query, setQuery] = useState('')
  const base = bundle?.runtime.assetBase

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return records.filter((record) => {
      if (filter === 'done' && record.status !== 'done') return false
      if (filter === 'error' && record.status !== 'error') return false
      if (!needle) return true
      return [record.answer, record.question, record.transcript, record.error, record.triggerLabel]
        .filter(Boolean)
        .some((text) => String(text).toLowerCase().includes(needle))
    })
  }, [filter, query, records])

  const selected: CaptureRecord | null = useMemo(
    () => filtered.find((record) => record.id === selectedId) ?? filtered[0] ?? null,
    [filtered, selectedId]
  )

  useEffect(() => {
    if (selected && selected.id !== selectedId) select(selected.id)
  }, [select, selected, selectedId])

  const screenshot = assetUrl(base, selected?.screenshot?.file)
  const audio = assetUrl(base, selected?.audio?.file)

  return (
    <div className="history">
      <Card
        title={`Lịch sử · ${records.length} phiên`}
        actions={
          <div className="row-gap">
            <input className="input input-search" placeholder="Tìm trong câu hỏi và kết quả…" value={query} onChange={(event) => setQuery(event.target.value)} />
            <Segmented
              value={filter}
              onChange={setFilter}
              options={[
                { value: 'all', label: 'Tất cả' },
                { value: 'done', label: 'Thành công' },
                { value: 'error', label: 'Lỗi' }
              ]}
            />
            <Button onClick={() => void actions.exportRecords()}>Xuất JSON</Button>
            <Button variant="danger" onClick={() => void actions.clearRecords()} disabled={!records.length}>
              Xóa hết
            </Button>
          </div>
        }
      >
        <div className="history-grid">
          <div className="history-list">
            {filtered.length === 0 ? (
              <Empty title="Không có phiên nào khớp" hint="Bấm phím nóng ngoài màn hình để tạo phiên mới." />
            ) : (
              <ul>
                {filtered.map((record) => (
                  <li key={record.id}>
                    <button
                      type="button"
                      className={`history-item ${selected?.id === record.id ? 'is-active' : ''}`}
                      onClick={() => select(record.id)}
                    >
                      <span className="history-thumb">
                        {record.screenshot ? (
                          <img src={assetUrl(base, record.screenshot.file) ?? ''} alt="" loading="lazy" />
                        ) : (
                          <span className="history-thumb-empty">không ảnh</span>
                        )}
                      </span>
                      <span className="history-text">
                        <span className="history-line">
                          {record.answer ? record.answer.split('\n')[0] : (record.error ?? record.question ?? 'Chưa có nội dung')}
                        </span>
                        <span className="history-meta">
                          <span className={`inline-dot tone-${record.status === 'done' ? 'ok' : 'error'}`} />
                          {timeAgo(record.createdAt)} · {SOURCE_LABEL[record.source]}
                          {record.audio ? ` · ${formatDuration(record.audio.durationMs)}` : ''}
                          {record.pinned ? ' · 📌' : ''}
                        </span>
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <div className="history-detail">
            {!selected ? (
              <Empty title="Chọn một phiên" hint="Bên trái là toàn bộ những lần bạn đã hỏi AI Bubble." />
            ) : (
              <>
                <div className="detail-head">
                  <div>
                    <p className="detail-time">{formatDateTime(selected.createdAt)}</p>
                    <p className="detail-sub">
                      {SOURCE_LABEL[selected.source]} · {selected.triggerLabel} ·{' '}
                      {selected.strategyUsed === 'multimodal' ? 'audio + ảnh một lượt gọi' : 'ghi âm → chữ → ảnh'}
                    </p>
                  </div>
                  <div className="row-gap">
                    <Button onClick={() => void actions.pinRecord(selected.id, !selected.pinned)}>{selected.pinned ? 'Bỏ ghim' : 'Ghim'}</Button>
                    <Button onClick={() => void window.bubble.copyText(selected.answer)}>Copy kết quả</Button>
                    <Button variant="danger" onClick={() => void actions.removeRecord(selected.id)}>
                      Xóa
                    </Button>
                  </div>
                </div>

                {screenshot ? (
                  <figure className="detail-shot">
                    <img src={screenshot} alt={`Màn hình đã chụp lúc ${formatDateTime(selected.createdAt)}`} />
                    <figcaption>
                      {selected.screenshot?.width}×{selected.screenshot?.height} · display {selected.screenshot?.displayId} ·{' '}
                      {formatBytes(selected.screenshot?.bytes ?? 0)}
                    </figcaption>
                  </figure>
                ) : (
                  <p className="muted">Phiên này không có ảnh màn hình.</p>
                )}

                {selected.question ? (
                  <div className="detail-block">
                    <p className="detail-label">Câu hỏi đã gõ</p>
                    <p className="detail-text">{selected.question}</p>
                  </div>
                ) : null}

                {selected.transcript ? (
                  <div className="detail-block">
                    <p className="detail-label">Giọng nói (bản ghi)</p>
                    <p className="detail-text">“{selected.transcript}”</p>
                  </div>
                ) : null}

                {audio ? (
                  <div className="detail-block">
                    <p className="detail-label">Bản ghi gốc · {formatBytes(selected.audio?.bytes ?? 0)}</p>
                    <audio controls src={audio} />
                  </div>
                ) : null}

                {selected.answer ? (
                  <div className="detail-block detail-answer">
                    <p className="detail-label">AI trả lời</p>
                    <pre className="detail-pre">{selected.answer}</pre>
                  </div>
                ) : null}

                {selected.error ? (
                  <div className="detail-block detail-error">
                    <p className="detail-label">Cảnh báo / lỗi</p>
                    <p className="detail-text">{selected.error}</p>
                  </div>
                ) : null}

                <div className="detail-timing">
                  <Badge>capture {formatDuration(selected.timings.captureMs)}</Badge>
                  <Badge>STT {formatDuration(selected.timings.sttMs)}</Badge>
                  <Badge tone="ok">AI {formatDuration(selected.timings.aiMs)}</Badge>
                  <Badge>tổng {formatDuration(selected.timings.totalMs)}</Badge>
                  {selected.usage ? (
                    <Badge>
                      {selected.usage.promptTokens}↑ / {selected.usage.completionTokens}↓ tokens
                    </Badge>
                  ) : null}
                </div>
              </>
            )}
          </div>
        </div>
      </Card>
    </div>
  )
}
