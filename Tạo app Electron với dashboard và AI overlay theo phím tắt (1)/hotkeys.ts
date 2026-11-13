import { EventEmitter } from 'node:events'
import { globalShortcut } from 'electron'
import { HOTKEY_KEYS, type AppSettings, type HotkeyKeyOption } from '../shared/types'

type UiohookModule = typeof import('uiohook-napi')
type KeyboardEventLike = { keycode: number }

export interface HotkeyStatus {
  engine: 'uiohook' | 'globalShortcut' | 'none'
  ok: boolean
  detail: string
  keyLabel: string
  shortcut: string
  listening: boolean
}

export interface ResolvedKey {
  keycode: number
  label: string
  option: HotkeyKeyOption
}

const TAP_MAX_MS = 450
const DOUBLE_TAP_WINDOW_MS = 600

/** Resolve the configured logical key into a raw uiohook keycode. */
export function resolveKey(config: AppSettings['hotkey'], platform: NodeJS.Platform): ResolvedKey | null {
  if (config.keyId === 'custom') {
    if (!config.customKeycode) return null
    return {
      keycode: config.customKeycode,
      label: config.customKeyLabel || `Phím #${config.customKeycode}`,
      option: HOTKEY_KEYS.find((item) => item.id === 'custom') ?? HOTKEY_KEYS[0]
    }
  }

  const autoId: string = platform === 'darwin' ? 'command' : 'shift'
  const option = HOTKEY_KEYS.find((item) => item.id === (config.keyId === 'auto' ? autoId : config.keyId))
  if (!option || option.keycode === null) return null
  return { keycode: option.keycode, label: option.glyph, option }
}

/**
 * Global hotkeys for a *bare modifier* cannot be expressed with Electron's
 * globalShortcut, so taps are detected from raw key events and a
 * real accelerator is kept as a guaranteed fallback.
 */
export class HotkeyService extends EventEmitter {
  private module: UiohookModule | null = null
  private config: AppSettings['hotkey'] | null = null
  private pressedAt: number | null = null
  private comboUsed = false
  private lastTapAt = 0
  private learning = false
  private hookRunning = false
  private fallbackRegistered = false
  private loadError = ''

  status(): HotkeyStatus {
    const config = this.config
    const resolved = config ? resolveKey(config, process.platform) : null
    const shortcut = config?.fallbackEnabled ? config.fallbackShortcut : ''
    return {
      engine: this.hookRunning ? 'uiohook' : shortcut ? 'globalShortcut' : 'none',
      ok: this.hookRunning || this.fallbackRegistered,
      detail: this.detail(resolved, shortcut),
      keyLabel: resolved?.label ?? (config?.keyId === 'custom' ? 'chưa học phím' : '—'),
      shortcut,
      listening: this.hookRunning
    }
  }

  private detail(resolved: ResolvedKey | null, shortcut: string): string {
    if (!this.config?.enabled) return 'Phím nóng đang tắt trong Cài đặt'
    if (this.hookRunning && resolved) {
      return `Đang theo dõi ${resolved.label} (${this.config.mode === 'double_tap' ? 'bấm đúp' : 'bấm một lần'})`
    }
    if (this.hookRunning && !resolved) {
      return 'Hook đang chạy nhưng chưa có phím hợp lệ — hãy chọn phím hoặc bấm "Học phím"'
    }
    if (shortcut && this.fallbackRegistered) return `Hook hệ thống bị chặn, dùng tổ hợp dự phòng ${shortcut}`
    return this.loadError || 'Chưa bật được hook phím nóng'
  }

  async start(config: AppSettings['hotkey']): Promise<void> {
    this.config = config
    await this.ensureModule()
    this.restart()
  }

  update(config: AppSettings['hotkey']): void {
    this.config = config
    this.restart()
  }

  private async ensureModule(): Promise<void> {
    if (this.module || this.loadError) return
    try {
      this.module = await import('uiohook-napi')
    } catch (error) {
      this.loadError = `Không tải được nhân phím (${error instanceof Error ? error.message : String(error)}). Wayland thường bị chặn.`
      this.module = null
    }
  }

  private restart(): void {
    this.stopHook()
    this.unregisterFallback()
    const config = this.config
    if (!config?.enabled) return
    this.startHook()
    if (config.fallbackEnabled && config.fallbackShortcut.trim()) {
      try {
        this.fallbackRegistered = globalShortcut.register(config.fallbackShortcut.trim(), () => {
          this.emit('toggle', `phím ${config.fallbackShortcut}`)
        })
      } catch (error) {
        this.fallbackRegistered = false
        this.loadError = `Không đăng ký được ${config.fallbackShortcut}: ${error instanceof Error ? error.message : String(error)}`
      }
    }
  }

  private startHook(): void {
    const mod = this.module
    if (!mod || !this.config?.enabled) return
    try {
      mod.uIOhook.on('keydown', this.onKeyDown)
      mod.uIOhook.on('keyup', this.onKeyUp)
      mod.uIOhook.start()
      this.hookRunning = true
    } catch (error) {
      this.hookRunning = false
      this.loadError = error instanceof Error ? error.message : String(error)
    }
  }

  private stopHook(): void {
    const mod = this.module
    if (mod && this.hookRunning) {
      try {
        mod.uIOhook.off('keydown', this.onKeyDown)
        mod.uIOhook.off('keyup', this.onKeyUp)
        mod.uIOhook.stop()
      } catch {
        /* the hook may already be stopped */
      }
    }
    this.hookRunning = false
    this.pressedAt = null
    this.comboUsed = false
  }

  private unregisterFallback(): void {
    try {
      globalShortcut.unregisterAll()
    } catch {
      /* ignore */
    }
    this.fallbackRegistered = false
  }

  private onKeyDown = (event: KeyboardEventLike): void => {
    const config = this.config
    if (!config) return

    if (this.learning) {
      this.emit('keycode', event.keycode)
      return
    }

    const resolved = resolveKey(config, process.platform)
    if (!resolved) return

    if (event.keycode === resolved.keycode) {
      if (this.pressedAt === null) this.pressedAt = Date.now()
    } else if (this.pressedAt !== null) {
      // Another key was typed while the modifier was held: a shortcut, not a tap.
      this.comboUsed = true
    }
  }

  private onKeyUp = (event: KeyboardEventLike): void => {
    const config = this.config
    if (!config || this.learning) return

    const resolved = resolveKey(config, process.platform)
    if (!resolved || event.keycode !== resolved.keycode) return

    const started = this.pressedAt
    this.pressedAt = null
    const wasCombo = this.comboUsed
    this.comboUsed = false
    if (started === null || wasCombo) return

    const duration = Date.now() - started
    if (duration > TAP_MAX_MS) return

    if (config.mode === 'single_tap') {
      this.emit('toggle', `${resolved.label}`)
      return
    }

    const since = Date.now() - this.lastTapAt
    if (since <= DOUBLE_TAP_WINDOW_MS) {
      this.lastTapAt = 0
      const glyph = resolved.label
      this.emit('toggle', glyph === 'fn' ? 'fn ×2' : `${glyph}${glyph}`)
    } else {
      this.lastTapAt = Date.now()
    }
  }

  beginLearning(): void {
    this.learning = true
  }

  endLearning(): void {
    this.learning = false
  }

  stop(): void {
    this.stopHook()
    this.unregisterFallback()
    this.removeAllListeners()
  }
}
