#!/usr/bin/env bash
set -euo pipefail

bundle="${1:?usage: package_linux_rpm.sh BUNDLE_DIR OUTPUT.rpm VERSION}"
output="${2:?usage: package_linux_rpm.sh BUNDLE_DIR OUTPUT.rpm VERSION}"
version="${3:?usage: package_linux_rpm.sh BUNDLE_DIR OUTPUT.rpm VERSION}"

[[ -x "$bundle/twitch_freedom_ultra" ]] || {
  printf 'Release executable missing from %s\n' "$bundle" >&2
  exit 1
}
command -v rpmbuild >/dev/null || {
  printf 'rpmbuild is required to build the Fedora package.\n' >&2
  exit 1
}
[[ "$version" =~ ^[0-9]+([.][0-9]+)*$ ]] || {
  printf 'Invalid RPM version: %s\n' "$version" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
tar -C "$bundle" -czf "$work/SOURCES/twitch-freedom-bundle.tar.gz" .

cat >"$work/SPECS/twitch-freedom.spec" <<EOF
Name:           twitch-freedom
Version:        $version
Release:        1%{?dist}
Summary:        Local-first Twitch and X desktop client
License:        MIT
URL:            https://github.com/ornab74/twitchfreedombetawithx
Source0:        twitch-freedom-bundle.tar.gz
BuildArch:      x86_64
Requires:       gtk3, libsecret, /usr/bin/mpv, /usr/bin/ffmpeg

%description
Secure media playback, encrypted local storage, and private local AI tools.

%prep
%setup -q -c -T

%install
install -d %{buildroot}/opt/twitch-freedom
tar -xzf %{SOURCE0} -C %{buildroot}/opt/twitch-freedom
install -d %{buildroot}/usr/bin %{buildroot}/usr/share/applications
ln -s /opt/twitch-freedom/twitch_freedom_ultra %{buildroot}/usr/bin/twitch-freedom
cat >%{buildroot}/usr/share/applications/com.ornab74.twitchfreedom.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Twitch Freedom
Comment=Local-first Twitch and X desktop client
Exec=/usr/bin/twitch-freedom
Terminal=false
Categories=AudioVideo;Network;
StartupNotify=true
DESKTOP

%files
/opt/twitch-freedom
/usr/bin/twitch-freedom
/usr/share/applications/com.ornab74.twitchfreedom.desktop

%changelog
* Thu Jan 01 2026 Twitch Freedom <noreply@github.com> - $version-1
- Automated release package.
EOF

rpmbuild --define "_topdir $work" -bb "$work/SPECS/twitch-freedom.spec"
rpm_file="$(find "$work/RPMS" -type f -name '*.rpm' -print -quit)"
[[ -n "$rpm_file" && -s "$rpm_file" ]] || {
  printf 'rpmbuild did not produce an RPM.\n' >&2
  exit 1
}
cp "$rpm_file" "$output"
