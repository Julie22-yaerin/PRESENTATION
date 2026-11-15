#!/usr/bin/env bash
# Reads landing/download-config.json and tells the owner, per channel, what is
# true right now: is the button live, is the promised asset already uploaded,
# or is the name still missing from the release.
#
# Informational: it always exits 0, so an unpublished Windows build can never
# fail a workflow.
#
#   bash landing/scripts/check-downloads.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$HERE/download-config.json"

if [[ ! -f "$CONFIG" ]]; then
  echo "missing $CONFIG" >&2
  exit 1
fi

probe() { # url -> http code
  curl -s -o /dev/null -L --max-time 25 -w '%{http_code}' "$1" 2>/dev/null || echo 000
}

printf 'download channels — %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)"
printf 'version: %s   updated: %s\n' \
  "$(python3 -c "import json;print(json.load(open('$CONFIG')).get('version','?'))")" \
  "$(python3 -c "import json;print(json.load(open('$CONFIG')).get('updated','?'))")"
printf -- '---------------------------------------------------------------\n'

python3 - "$CONFIG" <<'PY' > /tmp/lyceum-channels.tsv
import json, sys
config = json.load(open(sys.argv[1]))
for ch in config.get('channels', []):
    # a literal token stands in for empty values: bash read would merge the
    # neighbouring tabs otherwise and lose the column.
    print('\t'.join([
        ch.get('id', '?'),
        ch.get('platform', '?'),
        (ch.get('url') or '').strip() or 'NOTSET',
        (ch.get('plannedUrl') or '').strip() or 'NOTSET',
    ]))
PY

while IFS=$'\t' read -r id platform url planned; do
  [[ "$url" == "NOTSET" ]] && url=""
  [[ "$planned" == "NOTSET" ]] && planned=""
  if [[ -n "$url" ]]; then
    code=$(probe "$url")
    [[ "$code" == "200" ]] \
      && printf '%-10s %-8s LIVE      %s\n' "$id" "$platform" "$url" \
      || printf '%-10s %-8s BROKEN(%s) %s  <- button ships a dead link\n' "$id" "$platform" "$code" "$url"
  elif [[ -n "$planned" ]]; then
    code=$(probe "$planned")
    if [[ "$code" == "200" ]]; then
      printf '%-10s %-8s READY     %s\n' "$id" "$platform" "asset exists — copy plannedUrl into \"url\" and the button starts downloading"
    else
      printf '%-10s %-8s WAITING   %s\n' "$id" "$platform" "no asset named $(basename "$planned") in the latest release (button says: coming soon)"
    fi
  else
    printf '%-10s %-8s SIGNUP    %s\n' "$id" "$platform" "no url and no plannedUrl — button falls back to signupUrl"
  fi
done < /tmp/lyceum-channels.tsv

printf -- '---------------------------------------------------------------\n'
printf 'recipe: publish a release whose assets are named exactly as plannedUrl,\n'
printf 'then move each plannedUrl into url. releases/latest/download/... always\n'
printf 'resolves to your newest release, so the page needs no further edits.\n'
exit 0
