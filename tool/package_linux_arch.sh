#!/usr/bin/env bash
set -euo pipefail

bundle="${1:?usage: package_linux_arch.sh BUNDLE OUTPUT.pkg.tar.zst VERSION OUTPUT-AUR.tar.gz RELEASE.tar.gz}"
output="${2:?usage: package_linux_arch.sh BUNDLE OUTPUT.pkg.tar.zst VERSION OUTPUT-AUR.tar.gz RELEASE.tar.gz}"
version="${3:?usage: package_linux_arch.sh BUNDLE OUTPUT.pkg.tar.zst VERSION OUTPUT-AUR.tar.gz RELEASE.tar.gz}"
aur_output="${4:?usage: package_linux_arch.sh BUNDLE OUTPUT.pkg.tar.zst VERSION OUTPUT-AUR.tar.gz RELEASE.tar.gz}"
release_tar="${5:?usage: package_linux_arch.sh BUNDLE OUTPUT.pkg.tar.zst VERSION OUTPUT-AUR.tar.gz RELEASE.tar.gz}"

[[ -x "$bundle/twitch_freedom_ultra" ]] || {
  printf 'Release executable missing from %s\n' "$bundle" >&2
  exit 1
}
command -v zstd >/dev/null || {
  printf 'zstd is required to build the Arch package.\n' >&2
  exit 1
}
[[ "$version" =~ ^[0-9]+([.][0-9]+)*$ ]] || {
  printf 'Invalid Arch package version: %s\n' "$version" >&2
  exit 1
}

stage="$(mktemp -d)"
aur_stage="$(mktemp -d)"
trap 'rm -rf "$stage" "$aur_stage"' EXIT

install -d "$stage/opt/twitch-freedom" "$stage/usr/bin" \
  "$stage/usr/share/applications"
cp -a "$bundle/." "$stage/opt/twitch-freedom/"
ln -s /opt/twitch-freedom/twitch_freedom_ultra \
  "$stage/usr/bin/twitch-freedom"
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

installed_size="$(du -sk "$stage" | cut -f1)"
cat >"$stage/.PKGINFO" <<EOF
pkgname = twitch-freedom-bin
pkgbase = twitch-freedom-bin
pkgver = $version-1
pkgdesc = Local-first Twitch and X desktop client
url = https://github.com/ornab74/twitchfreedombetawithx
builddate = ${SOURCE_DATE_EPOCH:-$(date +%s)}
packager = Twitch Freedom CI
size = $((installed_size * 1024))
arch = x86_64
license = MIT
depend = gtk3
depend = libsecret
depend = mpv
depend = ffmpeg
EOF
tar --zstd -C "$stage" --owner=0 --group=0 -cf "$output" .PKGINFO opt usr

# Generate the metadata users can submit to the AUR. It references the generic
# Linux release tarball and pins its checksum instead of downloading unverified
# moving content.
release_sha="$(sha256sum "$release_tar" | cut -d' ' -f1)"
cat >"$aur_stage/PKGBUILD" <<EOF
pkgname=twitch-freedom-bin
pkgver=$version
pkgrel=1
pkgdesc='Local-first Twitch and X desktop client'
arch=('x86_64')
url='https://github.com/ornab74/twitchfreedombetawithx'
license=('MIT')
depends=('gtk3' 'libsecret' 'mpv' 'ffmpeg')
provides=('twitch-freedom')
conflicts=('twitch-freedom')
source=("TwitchFreedom-Linux-x64.tar.gz::https://github.com/ornab74/twitchfreedombetawithx/releases/download/v\${pkgver}/TwitchFreedom-Linux-x64.tar.gz")
sha256sums=('$release_sha')

package() {
  install -d "\${pkgdir}/opt/twitch-freedom" "\${pkgdir}/usr/bin" "\${pkgdir}/usr/share/applications"
  cp -a "\${srcdir}"/. "\${pkgdir}/opt/twitch-freedom/"
  rm -f "\${pkgdir}/opt/twitch-freedom/PKGBUILD"
  ln -s /opt/twitch-freedom/twitch_freedom_ultra "\${pkgdir}/usr/bin/twitch-freedom"
  cat >"\${pkgdir}/usr/share/applications/com.ornab74.twitchfreedom.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Twitch Freedom
Comment=Local-first Twitch and X desktop client
Exec=/usr/bin/twitch-freedom
Terminal=false
Categories=AudioVideo;Network;
StartupNotify=true
DESKTOP
}
EOF
cat >"$aur_stage/.SRCINFO" <<EOF
pkgbase = twitch-freedom-bin
  pkgdesc = Local-first Twitch and X desktop client
  pkgver = $version
  pkgrel = 1
  url = https://github.com/ornab74/twitchfreedombetawithx
  arch = x86_64
  license = MIT
  depends = gtk3
  depends = libsecret
  depends = mpv
  depends = ffmpeg
  provides = twitch-freedom
  conflicts = twitch-freedom
  source = TwitchFreedom-Linux-x64.tar.gz::https://github.com/ornab74/twitchfreedombetawithx/releases/download/v$version/TwitchFreedom-Linux-x64.tar.gz
  sha256sums = $release_sha

pkgname = twitch-freedom-bin
EOF
tar -C "$aur_stage" -czf "$aur_output" PKGBUILD .SRCINFO
