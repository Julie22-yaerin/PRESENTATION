#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/../landing/download-config.json"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to inspect download-config.json" >&2
  exit 1
fi

win_url=$(python3 - "$CONFIG" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    cfg = json.load(f)
for ch in cfg.get('channels', []):
    if ch.get('id') == 'win-x64':
        print((ch.get('url') or '').strip())
        break
PY
)

if [[ -z "$win_url" || "$win_url" == "null" ]]; then
  echo "waiting for a real Windows build"
  exit 0
fi

asset="${win_url##*/}"
expected="TheLyceum-win-x64.exe"
if [[ "$asset" != "$expected" ]]; then
  echo "Windows asset name mismatch: expected $expected, got $asset" >&2
  exit 1
fi

if [[ "$win_url" != *"Julie22-yaerin/PRESENTATION"* ]]; then
  echo "Windows download URL must point to Julie22-yaerin/PRESENTATION" >&2
  exit 1
fi

if [[ ! -f "${ROOT}/../.github/workflows/release-config.yml" ]]; then
  echo "missing release-config workflow" >&2
  exit 1
fi

sha_file="${ROOT}/../releases/${asset}.sha256"
if [[ ! -f "$sha_file" ]]; then
  echo "missing ${asset}.sha256 for Windows asset" >&2
  exit 1
fi

echo "Windows release channel configured for $asset"
