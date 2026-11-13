import { Menu, Tray, app, nativeImage } from 'electron'
import { existsSync } from 'node:fs'
import type { SessionSnapshot } from '../shared/types'

const PHASE_LABEL: Record<SessionSnapshot['phase'], string> = {
  idle: 'Sẵn sàng',
  arming: 'Đang bật…',
  listening: 'Đang nghe…',
  thinking: 'Đang phân tích…',
  answer: 'Đã có kết quả',
  error: 'Có lỗi'
}

export interface TrayOptions {
  iconPath: string
  getState: () => SessionSnapshot
  onToggle: () => void
  onDashboard: () => void
  onToggleBubble: () => void
}

export interface TrayHandle {
  available: boolean
  refresh: () => void
  destroy: () => void
}

/** Tray is optional: some Linux desktops have no status notifier host. */
export function createTray(options: TrayOptions): TrayHandle {
  if (!existsSync(options.iconPath)) {
    return { available: false, refresh: () => undefined, destroy: () => undefined }
  }

  const image = nativeImage.createFromPath(options.iconPath)
  if (image.isEmpty()) {
    return { available: false, refresh: () => undefined, destroy: () => undefined }
  }
  if (process.platform === 'darwin') image.setTemplateImage(true)

  let tray: Tray
  try {
    // Creating a Tray fails on desktops without a status notifier host.
    tray = new Tray(image.resize({ width: 18, height: 18 }))
  } catch {
    return { available: false, refresh: () => undefined, destroy: () => undefined }
  }
  tray.setToolTip('AI Bubble')

  const rebuild = (): void => {
    const state = options.getState()
    const menu = Menu.buildFromTemplate([
      { label: `Trạng thái: ${PHASE_LABEL[state.phase]}`, enabled: false },
      { type: 'separator' },
      {
        label: state.phase === 'listening' ? 'Dừng & gửi AI' : 'Bắt đầu nghe + nhìn màn hình',
        accelerator: process.platform === 'darwin' ? 'Cmd+Shift+Space' : 'Ctrl+Shift+Space',
        click: options.onToggle
      },
      { label: 'Mở Dashboard', click: options.onDashboard },
      { label: state.lastRecordId ? 'Mở lại bong bóng' : 'Chưa có kết quả nào', enabled: Boolean(state.lastRecordId), click: options.onToggleBubble },
      { type: 'separator' },
      { label: 'Thoát AI Bubble', click: () => app.quit() }
    ])
    tray.setContextMenu(menu)
  }

  rebuild()
  tray.on('click', rebuild)

  return {
    available: true,
    refresh: rebuild,
    destroy: () => tray.destroy()
  }
}
