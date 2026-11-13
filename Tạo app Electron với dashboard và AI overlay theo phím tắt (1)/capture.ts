import { desktopCapturer, screen } from 'electron'

export interface ScreenShot {
  jpeg: Buffer
  width: number
  height: number
  displayId: string
  label: string
  bytes: number
}

export interface CaptureOptions {
  maxWidth: number
  quality: number
  display: 'cursor' | 'primary'
}

export interface DisplayInfo {
  id: string
  label: string
  bounds: { x: number; y: number; width: number; height: number }
  scaleFactor: number
  isPrimary: boolean
  isCursor: boolean
}

export function listDisplays(): DisplayInfo[] {
  const cursor = screen.getCursorScreenPoint()
  const primary = screen.getPrimaryDisplay()
  return screen.getAllDisplays().map((display) => ({
    id: String(display.id),
    label: `${display.bounds.width}×${display.bounds.height} @${display.scaleFactor}x${display.id === primary.id ? ' · chính' : ''}`,
    bounds: { ...display.bounds },
    scaleFactor: display.scaleFactor,
    isPrimary: display.id === primary.id,
    isCursor:
      cursor.x >= display.bounds.x &&
      cursor.x < display.bounds.x + display.bounds.width &&
      cursor.y >= display.bounds.y &&
      cursor.y < display.bounds.y + display.bounds.height
  }))
}

function targetDisplay(preference: CaptureOptions['display']): DisplayInfo {
  const displays = listDisplays()
  if (!displays.length) throw new Error('Không phát hiện màn hình nào')
  if (preference === 'primary') return displays.find((item) => item.isPrimary) ?? displays[0]
  return displays.find((item) => item.isCursor) ?? displays.find((item) => item.isPrimary) ?? displays[0]
}

/**
 * Captures one frame of the requested display. Called synchronously at the moment
 * the hotkey fires so the image matches what the user was looking at.
 */
export async function captureScreen(options: CaptureOptions): Promise<ScreenShot> {
  const display = targetDisplay(options.display)
  const pixelWidth = Math.max(1, Math.round(display.bounds.width * display.scaleFactor))
  const pixelHeight = Math.max(1, Math.round(display.bounds.height * display.scaleFactor))
  const ratio = Math.min(1, options.maxWidth / pixelWidth)
  const thumbWidth = Math.max(1, Math.round(pixelWidth * ratio))
  const thumbHeight = Math.max(1, Math.round(pixelHeight * ratio))

  const sources = await desktopCapturer.getSources({
    types: ['screen'],
    thumbnailSize: { width: thumbWidth, height: thumbHeight }
  })

  if (!sources.length) {
    throw new Error(
      'Không lấy được nguồn màn hình. Trên Linux cần X11 hoặc desktop capture hợp lệ; trên macOS hãy cấp quyền Screen Recording.'
    )
  }

  const matched = sources.find((source) => String(source.display_id) === display.id) ?? sources[0]
  const image = matched.thumbnail
  if (!image || image.isEmpty()) {
    throw new Error('Ảnh màn hình rỗng — thường do thiếu quyền Screen Recording (macOS) hoặc Wayland (Linux).')
  }

  const size = image.getSize()
  const jpeg = image.toJPEG(options.quality)

  return {
    jpeg,
    width: size.width,
    height: size.height,
    displayId: display.id,
    label: `${size.width}×${size.height} · ${matched.name || `màn hình ${display.id}`}`,
    bytes: jpeg.byteLength
  }
}

/** Fallback path used when the app needs a specific display id from the renderer. */
export function displayLabel(id: string): string {
  const found = listDisplays().find((item) => item.id === id)
  return found ? found.label : `màn hình ${id}`
}
