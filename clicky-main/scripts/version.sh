#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$ROOT/Config/Release.xcconfig"
PROJECT_FILE="$ROOT/leanring-buddy.xcodeproj/project.pbxproj"

read_value() {
  local key="$1"
  local file="$2"
  grep -E "^${key} = " "$file" | head -n 1 | sed -E "s/^${key} = //" | tr -d '\r'
}

version="$(read_value "MARKETING_VERSION" "$CONFIG_FILE")"
build="$(read_value "CURRENT_PROJECT_VERSION" "$CONFIG_FILE")"
min_macos="$(read_value "MACOSX_DEPLOYMENT_TARGET" "$CONFIG_FILE")"
app_name="$(grep -E "PRODUCT_NAME = " "$PROJECT_FILE" | head -n 1 | sed -E 's/^\s*PRODUCT_NAME = //; s/;$//' )"

printf 'MARKETING_VERSION=%s\n' "$version"
printf 'CURRENT_PROJECT_VERSION=%s\n' "$build"
printf 'MACOSX_DEPLOYMENT_TARGET=%s\n' "$min_macos"
printf 'APP_NAME=%s\n' "$app_name"
printf 'DMG_NAME=%s.dmg\n' "$app_name"
printf 'DMG_NAME_ARM64=%s-arm64.dmg\n' "$app_name"
printf 'DMG_NAME_INTEL=%s-intel.dmg\n' "$app_name"
