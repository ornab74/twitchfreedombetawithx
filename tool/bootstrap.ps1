$ErrorActionPreference = 'Stop'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
flutter create --platforms=android,ios,linux,macos,windows --org com.ornab74 .
dart run tool/configure_generated_platforms.dart
flutter pub get --enforce-lockfile
dart run tool/verify_resolved_packages.dart --strict
flutter analyze
flutter test
Write-Host 'Twitch Freedom workspace validated.'
Write-Host 'Linux uses responsive X11 and falls back to CPU OpenGL when needed.'
