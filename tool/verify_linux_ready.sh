#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$1" >&2; exit 1; }
pass() { printf 'OK: %s\n' "$1"; }

[[ -f linux/CMakeLists.txt ]] || fail 'linux/CMakeLists.txt is missing'
[[ -f linux/runner/main.cc ]] || fail 'linux/runner/main.cc is missing'
grep -q 'crostini-x11-cpu-opengl' linux/runner/main.cc || fail 'Crostini CPU fallback policy missing'
grep -q 'GDK_BACKEND", "wayland"' linux/runner/main.cc || fail 'accelerated Crostini Wayland policy missing'
grep -q 'GDK_BACKEND", "x11"' linux/runner/main.cc || fail 'Crostini X11 fallback policy missing'
grep -q 'TWITCH_FREEDOM_ACCELERATED_UI' linux/runner/main.cc || fail 'accelerated UI override missing'
grep -q 'TWITCH_FREEDOM_MEDIA_RENDERER' linux/runner/main.cc || fail 'isolated media-rendering policy missing'
grep -q 'TWITCH_FREEDOM_AI_RENDERER' linux/runner/main.cc || fail 'isolated AI-rendering policy missing'
grep -q 'is_crostini && !allow_ai_acceleration' linux/runner/main.cc || fail 'Crostini native AI crash isolation missing'
grep -q 'TWITCH_FREEDOM_GPU_AVAILABLE' linux/runner/main.cc || fail 'Linux GPU capability probe missing'
grep -q 'TWITCH_FREEDOM_OPENGL_AVAILABLE' linux/runner/main.cc || fail 'Linux OpenGL capability probe missing'
grep -q 'TWITCH_FREEDOM_HWDEC_AVAILABLE' linux/runner/main.cc || fail 'Linux hardware decode probe missing'
grep -q 'FLUTTER_LINUX_RENDERER' linux/runner/main.cc || fail 'Flutter OpenGL texture compositor policy missing'
grep -q 'LIBGL_ALWAYS_SOFTWARE' linux/runner/main.cc || fail 'Mesa software policy missing'
grep -q 'GALLIUM_DRIVER' linux/runner/main.cc || fail 'llvmpipe policy missing'
grep -q 'LP_NUM_THREADS' linux/runner/main.cc || fail 'llvmpipe worker override support missing'
grep -q 'Linux policy:' lib/main.dart || fail 'Dart boot workload log missing'
! grep -q 'ffmpeg_kit_flutter_new:' pubspec.yaml || fail 'unsupported FFmpeg Kit Linux plugin is still enabled'
! grep -q 'ffmpeg_kit_extended_flutter:' pubspec.yaml || fail 'OpenGL FFmpeg Kit video plugin is enabled on the stable Crostini path'
grep -q 'SystemFfmpegAdapter' lib/playback/linux_ffmpeg_adapter.dart || fail 'secure system FFmpeg adapter missing'
grep -q 'runInShell: false' lib/playback/linux_ffmpeg_adapter.dart || fail 'system FFmpeg adapter must never invoke a shell'
grep -q 'path: third_party/media_kit$' pubspec.yaml || fail 'local media_kit safety override missing'
grep -q 'mpv_set_wakeup_callback(reference.cast(), nullptr, nullptr)' third_party/media_kit/lib/src/player/native/player/real.dart || fail 'mpv hot-restart callback detachment missing'
grep -q 'flutter_gemma_litertlm: 1.3.1' pubspec.yaml || fail 'LiteRT-LM version was not updated'
grep -q 'video_player: 2.13.0' pubspec.yaml || fail 'video_player version was not updated'

pass 'Linux desktop project is configured'
pass 'responsive X11, CPU-OpenGL fallback, and isolated media/AI policies are configured'
pass 'boot-time workload logs are present'
pass 'OpenGL FFmpeg Kit video plugins are excluded from the stable Linux path'
pass 'secure system FFmpeg audio adapter is configured'
pass 'mpv hot-restart callback teardown is configured'
pass 'requested compatible direct dependency versions are pinned'

if [[ "${1:-}" == '--full' ]]; then
  command -v flutter >/dev/null || fail 'flutter is not on PATH'
  flutter config --enable-linux-desktop
  dart run tool/configure_generated_platforms.dart
  flutter pub get --enforce-lockfile
  flutter analyze
  flutter test
  pass 'Flutter dependency, analyzer, and test validation completed'
fi
