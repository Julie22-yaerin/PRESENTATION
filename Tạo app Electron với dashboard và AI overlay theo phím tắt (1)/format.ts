import type { BubblePhase, CaptureRecord, SessionSnapshot } from '../../../shared/types'

export const PHASE_LABEL: Record<BubblePhase, string> = {
  idle: 'Sẵn sàng',
  arming: 'Đang bật…',
  listening: 'Đang nghe',
  thinking: 'Đang phân tích',
  answer: 'Đã có kết quả',
  error: 'Cần xử lý'
}

export const SOURCE_LABEL: Record<CaptureRecord['source'], string> = {
  hotkey: 'Phím nóng',
  dashboard: 'Dashboard',
  bubble: 'Bong bóng'
}

export function formatDuration(ms: number): string {
  if (!Number.isFinite(ms) || ms <= 0) return '0s'
  if (ms < 1000) return `${Math.round(ms)}ms`
  if (ms < 60000) return `${(ms / 1000).toFixed(ms < 10000 ? 1 : 0)}s`
  const minutes = Math.floor(ms / 60000)
  const seconds = Math.round((ms % 60000) / 1000)
  return `${minutes}m ${seconds.toString().padStart(2, '0')}s`
}

export function formatBytes(bytes: number): string {
  if (!bytes) return '0 KB'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export function formatTime(timestamp: number): string {
  return new Date(timestamp).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })
}

export function formatDateTime(timestamp: number): string {
  return new Date(timestamp).toLocaleString('vi-VN', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  })
}

export function timeAgo(timestamp: number): string {
  const diff = Date.now() - timestamp
  if (diff < 45_000) return 'vừa xong'
  if (diff < 3_600_000) return `${Math.round(diff / 60_000)} phút trước`
  if (diff < 86_400_000) return `${Math.round(diff / 3_600_000)} giờ trước`
  return new Date(timestamp).toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit' })
}

export function isToday(timestamp: number): boolean {
  const date = new Date(timestamp)
  const now = new Date()
  return date.getDate() === now.getDate() && date.getMonth() === now.getMonth() && date.getFullYear() === now.getFullYear()
}

const KEYCODE_NAMES: Record<number, string> = {
  1: 'Esc',
  15: 'Tab',
  57: 'Space',
  58: 'CapsLock',
  3639: 'PrtSc',
  69: 'NumLock',
  70: 'ScrollLock'
}

/** Human label for a raw uiohook keycode captured in learn-key mode. */
export function guessKeyName(keycode: number): string {
  const preset = HOTKEY_KEYS.find((option) => option.keycode === keycode)
  if (preset) return preset.glyph
  return KEYCODE_NAMES[keycode] ?? `Phím #${keycode}`
}

export function firstLine(text: string): string {
  return (
    text
      .split('\n')
      .map((line) => line.trim())
      .find(Boolean) ?? ''
  )
}

export function summarize(snapshot: SessionSnapshot): string {
  if (snapshot.phase === 'listening') return `Đang nghe ${formatDuration(snapshot.recordingMs)}`
  if (snapshot.phase === 'thinking') return 'Đang phân tích màn hình + giọng nói'
  if (snapshot.phase === 'answer') return firstLine(snapshot.answer)
  if (snapshot.phase === 'error') return snapshot.error ?? 'Có lỗi xảy ra'
  return ''
}

export function platformGlyph(platform: string, mode: 'single_tap' | 'double_tap', keyLabel: string): string {
  const times = mode === 'double_tap' && keyLabel !== 'fn' ? `${keyLabel}${keyLabel}` : keyLabel === 'fn' ? 'fn ×2' : keyLabel
  return platform === 'darwin' ? `⌘ · ${times}` : times
}

export function keycapLabel(platform: string): { primary: string; note: string } {
  if (platform === 'darwin') return { primary: 'Command (⌘) hoặc Fn', note: 'Fn thường bị macOS giữ lại — có thể dùng Command.' }
  if (platform === 'win32') return { primary: 'Shift hoặc Win', note: 'Win hay bị system phím nóng chiếm dụng.' }
  return { primary: 'Shift', note: 'Trên Wayland, hook toàn cục có thể bị chặn.' }
}
import { HOTKEY_KEYS } from '../../../shared/types'
