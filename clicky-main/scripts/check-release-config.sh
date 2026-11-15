#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$ROOT/Config/Release.xcconfig"
LANDING_CONFIG="$ROOT/../landing/download-config.json"
INFO_PLIST="$ROOT/leanring-buddy/Info.plist"
RELEASE_SCRIPT="$ROOT/scripts/release.sh"
APPCAST_FILE="$ROOT/appcast.xml"

error() {
  echo "release-config: $*" >&2
  exit 1
}

version=$(grep -E '^MARKETING_VERSION = ' "$CONFIG_FILE" | head -n 1 | sed -E 's/^MARKETING_VERSION = //')
build=$(grep -E '^CURRENT_PROJECT_VERSION = ' "$CONFIG_FILE" | head -n 1 | sed -E 's/^CURRENT_PROJECT_VERSION = //')
min_macos=$(grep -E '^MACOSX_DEPLOYMENT_TARGET = ' "$CONFIG_FILE" | head -n 1 | sed -E 's/^MACOSX_DEPLOYMENT_TARGET = //')
landing_version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$LANDING_CONFIG")
landing_macos=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["requirements"]["macos"])' "$LANDING_CONFIG")
feed_url=$(grep -E '<key>SUFeedURL</key>' -A1 "$INFO_PLIST" | tail -n 1 | sed -E 's#.*<string>(.*)</string>.*#\1#')
app_name=$(grep -E '^APP_NAME=' "$RELEASE_SCRIPT" | head -n 1 | sed -E 's/^APP_NAME="?//; s/"?$//')

[[ -n "$version" ]] || error "MARKETING_VERSION missing from $CONFIG_FILE"
[[ -n "$build" ]] || error "CURRENT_PROJECT_VERSION missing from $CONFIG_FILE"
[[ -n "$min_macos" ]] || error "MACOSX_DEPLOYMENT_TARGET missing from $CONFIG_FILE"
[[ "$version" == "$landing_version" ]] || error "project version $version does not match landing/download-config.json version $landing_version"
[[ "$min_macos" == "$landing_macos" ]] || error "project min macOS $min_macos does not match landing/download-config.json requirement $landing_macos"
[[ "$feed_url" == *"Julie22-yaerin/PRESENTATION"* ]] || error "SUFeedURL must point to Julie22-yaerin/PRESENTATION, found: $feed_url"
[[ "$app_name" != "makesomething" ]] || error "APP_NAME is still makesomething in $RELEASE_SCRIPT"
grep -q "julianjear" "$APPCAST_FILE" && error "appcast.xml still references julianjear"

echo "release-config OK: v${version} build ${build}, min macOS ${min_macos}, appcast repo is Julie22-yaerin/PRESENTATION"
