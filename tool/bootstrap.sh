#!/usr/bin/env bash
set -euo pipefail
export FLUTTER_SUPPRESS_ANALYTICS=true

flutter config --enable-linux-desktop
flutter create --platforms=android,ios,linux,macos,windows --org com.ornab74 .
dart run tool/configure_generated_platforms.dart
flutter pub get --enforce-lockfile
dart run tool/verify_resolved_packages.dart --strict
flutter analyze
flutter test

printf '
Twitch Freedom workspace validated.
'
printf 'Linux uses responsive X11 and falls back to CPU OpenGL when needed.
'
printf 'Run: flutter run --release -d linux
'
