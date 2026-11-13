import { BrowserWindow, screen } from 'electron'
import path from 'node:path'

/** The window is always the expanded size; the pill sits in its bottom-right corner. */
export const OVERLAY_WIDTH = 470
export const OVERLAY_HEIGHT = 540
const EDGE_PADDING = 20

export interface OverlayPosition {
  x: number
  y: number
}

interface OverlayOptions {
  preload: string
  isDev: boolean
  devServerUrl?: string
  onPositionChange?: (position: OverlayPosition) => void
}

export class OverlayController {
  private win: BrowserWindow | null = null
  private interactive = false
  private expanded = false

  constructor(private readonly options: OverlayOptions) {}

  get window(): BrowserWindow | null {
    return this.win
  }

  get ready(): boolean {
    return this.win !== null && !this.win.isDestroyed()
  }

  create(initial?: OverlayPosition | null): BrowserWindow {
    const position = this.clamp(initial ?? this.defaultPosition())

    const win = new BrowserWindow({
      ...position,
      width: OVERLAY_WIDTH,
      height: OVERLAY_HEIGHT,
      show: false,
      frame: false,
      transparent: true,
      resizable: false,
      movable: true,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      skipTaskbar: true,
      hasShadow: false,
      alwaysOnTop: true,
      focusable: false,
      title: 'AI Bubble',
      backgroundColor: '#00000000',
      webPreferences: {
        preload: this.options.preload,
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false,
        spellcheck: false,
        backgroundThrottling: false
      }
    })

    win.setMenuBarVisibility(false)
    win.setMinimumSize(OVERLAY_WIDTH, OVERLAY_HEIGHT)
    win.setMaximumSize(OVERLAY_WIDTH, OVERLAY_HEIGHT)
    // 'screen-saver' keeps the bubble above fullscreen apps on macOS and Windows.
    win.setAlwaysOnTop(true, 'screen-saver', 1)
    try {
      win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
    } catch {
      /* Linux ignores this option */
    }
    win.setIgnoreMouseEvents(true, { forward: true })
    this.interactive = false

    win.on('closed', () => {
      this.win = null
    })

    this.load(win)
    this.win = win
    return win
  }

  private load(win: BrowserWindow): void {
    if (this.options.isDev && this.options.devServerUrl) {
      void win.loadURL(`${this.options.devServerUrl.replace(/\/$/, '')}/overlay.html`)
    } else {
      void win.loadFile(path.join(__dirname, '../renderer/overlay.html'))
    }
  }

  private defaultPosition(): OverlayPosition {
    const display = screen.getPrimaryDisplay()
    const { x, y, width, height } = display.workArea
    return {
      x: Math.round(x + width - OVERLAY_WIDTH - EDGE_PADDING),
      y: Math.round(y + height - OVERLAY_HEIGHT - EDGE_PADDING)
    }
  }

  clamp(position: OverlayPosition): OverlayPosition {
    const display = screen.getDisplayMatching({
      x: Math.round(position.x + OVERLAY_WIDTH / 2),
      y: Math.round(position.y + OVERLAY_HEIGHT / 2),
      width: 1,
      height: 1
    })
    const { x, y, width, height } = display.workArea
    return {
      x: Math.round(Math.min(Math.max(position.x, x), x + Math.max(0, width - OVERLAY_WIDTH))),
      y: Math.round(Math.min(Math.max(position.y, y), y + Math.max(0, height - OVERLAY_HEIGHT)))
    }
  }

  moveTo(position: OverlayPosition, persist = true): OverlayPosition {
    const clamped = this.clamp(position)
    if (this.ready) this.win!.setPosition(clamped.x, clamped.y)
    if (persist) this.options.onPositionChange?.(clamped)
    return clamped
  }

  currentBounds(): OverlayPosition & { width: number; height: number } {
    if (!this.ready) {
      const fallback = this.defaultPosition()
      return { ...fallback, width: OVERLAY_WIDTH, height: OVERLAY_HEIGHT }
    }
    const bounds = this.win!.getBounds()
    return { x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height }
  }

  dragBy(delta: { dx: number; dy: number }): void {
    if (!this.ready) return
    const bounds = this.win!.getBounds()
    this.moveTo({ x: bounds.x + Math.round(delta.dx), y: bounds.y + Math.round(delta.dy) }, false)
  }

  endDrag(): void {
    if (this.ready) this.options.onPositionChange?.({ x: this.win!.getBounds().x, y: this.win!.getBounds().y })
  }

  setExpanded(expanded: boolean): void {
    this.expanded = expanded
    this.applyInteractivity()
  }

  get isExpanded(): boolean {
    return this.expanded
  }

  /**
   * macOS/Windows forward mousemove to a click-through window, so the renderer can
   * hover-detect the pill. On Linux forwarding is unavailable: the bubble is only
   * interactive while expanded, otherwise clicks pass straight through.
   */
  setHover(hovering: boolean): void {
    if (process.platform === 'linux' && !this.expanded) return
    this.interactive = hovering || this.expanded
    this.applyInteractivity()
  }

  private applyInteractivity(): void {
    if (!this.ready) return
    const ignore = !(this.interactive || this.expanded)
    if (ignore) {
      this.win!.setIgnoreMouseEvents(true, { forward: process.platform !== 'linux' })
    } else {
      this.win!.setIgnoreMouseEvents(false)
    }
  }

  allowKeyboardInput(enabled: boolean): void {
    if (!this.ready) return
    try {
      this.win!.setFocusable(enabled)
      if (enabled) this.win!.focus()
    } catch {
      /* older Electron builds do not expose setFocusable */
    }
  }

  send(channel: string, payload: unknown): void {
    if (this.ready) this.win!.webContents.send(channel, payload)
  }

  /** Scales the bubble itself without changing the on-screen anchor. */
  setScale(factor: number): void {
    if (!this.ready) return
    const clamped = Math.min(1.6, Math.max(0.8, Number(factor) || 1))
    try {
      this.win!.webContents.setZoomFactor(clamped)
    } catch {
      /* zoom is unavailable before the page is attached */
    }
  }

  show(): void {
    if (!this.ready) this.create()
    this.win!.showInactive()
  }

  hide(): void {
    if (this.ready) this.win!.hide()
  }

  isVisible(): boolean {
    return this.ready && this.win!.isVisible()
  }

  reload(): void {
    if (this.ready) this.win!.webContents.reload()
  }
}
