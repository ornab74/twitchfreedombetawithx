#!/usr/bin/env bash
set -euo pipefail

app="${1:?usage: package_macos_dmg.sh APP_BUNDLE OUTPUT.dmg}"
output="${2:?usage: package_macos_dmg.sh APP_BUNDLE OUTPUT.dmg}"

[[ -d "$app" ]] || {
  printf 'macOS application bundle missing: %s\n' "$app" >&2
  exit 1
}
command -v hdiutil >/dev/null || {
  printf 'hdiutil is required to build the disk image.\n' >&2
  exit 1
}

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Twitch Freedom.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -ov -format UDZO -volname 'Twitch Freedom' \
  -srcfolder "$stage" "$output"
