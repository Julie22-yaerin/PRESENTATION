import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * Boots the built app inside Xvfb with AIBUBBLE_SMOKE=1. The main process performs a
 * real desktopCapturer grab, synthesises a WAV, calls the configured AI endpoint and
 * prints a single SMOKE_JSON line. Requires OPENAI_API_KEY / OPENAI_API_BASE
 * (or AIBUBBLE_API_KEY / AIBUBBLE_BASE_URL) in the environment.
 */
const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..')
const electronBin = join(root, 'node_modules', 'electron', 'dist', 'electron')

if (!existsSync(electronBin)) {
  console.error('Electron binary missing — run: node node_modules/electron/install.js')
  process.exit(2)
}

if (!process.env.OPENAI_API_KEY && !process.env.AIBUBBLE_API_KEY) {
  console.error('No API key in the environment (OPENAI_API_KEY or AIBUBBLE_API_KEY).')
  process.exit(2)
}

const timeoutMs = Number(process.env.SMOKE_TIMEOUT_MS ?? 150000)
const child = spawn('xvfb-run', ['-a', '-s', '-screen 0 1920x1080x24', electronBin, '.'], {
  cwd: root,
  env: {
    ...process.env,
    AIBUBBLE_SMOKE: '1',
    ELECTRON_DISABLE_SECURITY_WARNINGS: 'true',
    LIBGL_ALWAYS_SOFTWARE: '1'
  },
  stdio: ['ignore', 'pipe', 'pipe']
})

let buffer = ''
let payload = null
const start = Date.now()

const finish = (code, reason) => {
  clearTimeout(timer)
  if (!child.killed) child.kill('SIGTERM')
  if (payload) {
    console.log('\n--- smoke report ---')
    console.log(JSON.stringify(payload, null, 2))
  }
  console.log(`\nsmoke exit=${code} ${reason} (${Date.now() - start}ms)`)
  process.exit(code)
}

const timer = setTimeout(() => finish(1, 'timeout'), timeoutMs)

child.stdout.on('data', (chunk) => {
  const text = chunk.toString()
  process.stdout.write(text)
  buffer += text
  const index = buffer.indexOf('SMOKE_JSON ')
  if (index >= 0 && !payload) {
    try {
      payload = JSON.parse(buffer.slice(index + 'SMOKE_JSON '.length))
      finish(payload.ok ? 0 : 1, payload.ok ? 'ok' : 'failed assertion')
    } catch {
      /* partial JSON, keep reading */
    }
  }
})

child.stderr.on('data', (chunk) => process.stderr.write(chunk))
child.on('exit', (code) => finish(code === 0 && payload?.ok ? 0 : 1, `electron exited ${code}`))
