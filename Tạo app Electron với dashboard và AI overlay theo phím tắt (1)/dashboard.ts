import { BrowserWindow, shell } from 'electron'
import path from 'node:path'

interface DashboardOptions {
  preload: string
  isDev: boolean
  devServerUrl?: string
  /** Closing the window should only hide it while the bubble keeps running. */
  shouldHideOnClose?: () => boolean
}

export class DashboardWindow {
  private win: BrowserWindow | null = null

  constructor(private readonly options: DashboardOptions) {}

  get window(): BrowserWindow | null {
    return this.win
  }

  show(): BrowserWindow {
    if (this.win && !this.win.isDestroyed()) {
      if (this.win.isMinimized()) this.win.restore()
      this.win.show()
      this.win.focus()
      return this.win
    }
    return this.create()
  }

  private create(): BrowserWindow {
    const win = new BrowserWindow({
      width: 1320,
      height: 860,
      minWidth: 1040,
      minHeight: 700,
      show: false,
      title: 'AI Bubble — Dashboard',
      backgroundColor: '#0b0d14',
      autoHideMenuBar: true,
      titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
      webPreferences: {
        preload: this.options.preload,
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: false,
        spellcheck: false
      }
    })

    win.once('ready-to-show', () => win.show())

    // Closing the dashboard keeps the app alive: the bubble is the product.
    win.on('close', (event) => {
      if (!this.options.shouldHideOnClose?.()) return
      event.preventDefault()
      win.hide()
    })

    win.webContents.setWindowOpenHandler(({ url }) => {
      if (url.startsWith('http://') || url.startsWith('https://')) void shell.openExternal(url)
      return { action: 'deny' }
    })

    if (this.options.isDev && this.options.devServerUrl) {
      void win.loadURL(this.options.devServerUrl)
    } else {
      void win.loadFile(path.join(__dirname, '../renderer/index.html'))
    }

    win.on('closed', () => {
      this.win = null
    })

    this.win = win
    return win
  }

  send(channel: string, payload: unknown): void {
    if (this.win && !this.win.isDestroyed()) this.win.webContents.send(channel, payload)
  }

  isVisible(): boolean {
    return this.win !== null && !this.win.isDestroyed() && this.win.isVisible()
  }

  focusRecord(id: string): void {
    const win = this.show()
    const send = (): void => win.webContents.send('dash:focus-record', id)
    if (win.webContents.isLoading()) win.webContents.once('did-finish-load', send)
    else send()
  }

  reload(): void {
    if (this.win && !this.win.isDestroyed()) this.win.webContents.reload()
  }
}
