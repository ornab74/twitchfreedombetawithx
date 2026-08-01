# Changelog

## Unreleased

- Split Linux UI, media, and AI acceleration policies so unsupported video/compute backends are never coupled to Flutter rendering.
- Kept Crostini on the responsive X11 path after native Wayland stalled in device testing, and added a render-node-aware CPU fallback.
- Reserved half of the eight-vCPU VM for input, media, and Dart while allowing an explicit llvmpipe thread override.
- Coalesced Media Kit software-frame callbacks and reused OpenGL texture storage to prevent decoded frames and per-frame reallocations from starving input and paint work.
- Fixed the playback restart race that could rebuild the video surface after its controller had been released.
- Added safe double-click full-window playback without a native GTK surface resize and capped software playback to CPU-safe 30 FPS variants.
- Fixed Twitch IRC join readiness, live message parsing, Helix send receipts, outgoing local echo, message-ID deduplication, and Unicode/control-character validation.
- Reused encrypted Gemma SHA-256 attestations for unchanged files and added first-pass verification progress.
- Added responsive height/width breakpoints and exact 1500×930 ↔ 1920×1090 resize regression coverage.

## 0.2.0+2 — Linux and PulseMesh upgrade

- Added a complete Linux desktop project so `flutter run -d linux` is recognized.
- Defaulted Linux UI rendering to software mode without a command-line flag.
- Added native and Dart boot logs for the effective rendering policy.
- Added an explicit `TWITCH_FREEDOM_ALLOW_GPU=1` opt-in.
- Updated direct package constraints to the supplied July 2026 versions.
- Added package-resolution baseline verification.
- Added the PulseMesh adaptive scheduler and ordered BootPipeline.
- Moved AI batching and speech capture onto scheduler-managed recurrence.
- Added scheduler diagnostics to Control Center.
- Made raw chat render before encrypted persistence work.
- Added scheduler and Linux policy tests/scripts.
