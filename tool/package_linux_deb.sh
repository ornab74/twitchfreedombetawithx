#!/usr/bin/env bash
set -euo pipefail

bundle="${1:?usage: package_linux_deb.sh BUNDLE_DIR OUTPUT.deb VERSION}"
output="${2:?usage: package_linux_deb.sh BUNDLE_DIR OUTPUT.deb VERSION}"
version="${3:?usage: package_linux_deb.sh BUNDLE_DIR OUTPUT.deb VERSION}"

[[ -x "$bundle/twitch_freedom_ultra" ]] || {
  printf 'Release executable missing from %s\n' "$bundle" >&2
  exit 1
}
command -v dpkg-deb >/dev/null || {
  printf 'dpkg-deb is required to build the installer.\n' >&2
  exit 1
}

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
install -d "$stage/DEBIAN" "$stage/opt/twitch-freedom" \
  "$stage/usr/bin" "$stage/usr/share/applications"
cp -a "$bundle/." "$stage/opt/twitch-freedom/"
ln -s /opt/twitch-freedom/twitch_freedom_ultra \
  "$stage/usr/bin/twitch-freedom"

cat >"$stage/DEBIAN/control" <<EOF
Package: twitch-freedom
Version: $version
Section: video
Priority: optional
Architecture: amd64
Maintainer: Twitch Freedom <noreply@github.com>
Depends: libgtk-3-0, libsecret-1-0, mpv, ffmpeg
Description: Local-first Twitch and X desktop client
 Secure media playback, encrypted local storage, and private local AI tools.
EOF

cat >"$stage/usr/share/applications/com.ornab74.twitchfreedom.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Twitch Freedom
Comment=Local-first Twitch and X desktop client
Exec=/usr/bin/twitch-freedom
Terminal=false
Categories=AudioVideo;Network;
StartupNotify=true
EOF

chmod 0755 "$stage/DEBIAN"
chmod 0644 "$stage/DEBIAN/control" \
  "$stage/usr/share/applications/com.ornab74.twitchfreedom.desktop"
dpkg-deb --root-owner-group --build "$stage" "$output"
