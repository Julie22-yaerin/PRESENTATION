import { spawn } from 'node:child_process'
import { mkdirSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

/**
 * Boots the built app under Xvfb with AIBUBBLE_SHOT set, so the main process renders the
 * dashboard and the bubble, runs one real AI turn and writes PNGs for visual review.
 *   node scripts/shots.mjs [outputDir]
 */
const here = dirname(fileURLToPath(import.meta.url))
const root = join(here, '..')
const outDir = resolve(process.argv[2] ?? join(root, 'shots'))
const electronBin = join(root, 'node_modules', 'electron', 'dist', 'electron')

mkdirSync(outDir, { recursive: true })

const useXvfb = !process.env.DISPLAY
const command = useXvfb ? 'xvfb-run' : electronBin
const args = useXvfb
  ? ['-a', '-s', '-screen 0 1440x900x24', electronBin, '.']
  : ['.']

const child = spawn(command, args, {
  cwd: root,
  env: { ...process.env, AIBUBBLE_SHOT: outDir, AIBUBBLE_NO_SANDBOX: '1', ELECTRON_DISABLE_SECURITY_WARNINGS: 'true' },
  stdio: 'inherit'
})

child.on('exit', (code) => {
  console.log(`\nshots: ${outDir} (exit ${code})`)
  process.exit(code ?? 0)
})
