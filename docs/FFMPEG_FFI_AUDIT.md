# FFmpeg Kit Extended FFI audit

Audit target: `akashskypatel/ffmpeg-kit-extended` commit
`d06b6902b68ab0aef4d8f9ead7f2544a45686440` (July 25, 2026), published as
`ffmpeg_kit_extended_flutter 0.5.12`.

## Dart binding result

- `flutter/ffigen.yaml` declares the CodeAssets native asset ID
  `package:ffmpeg_kit_extended_flutter/ffmpegkit`.
- Generated calls use `@ffi.DefaultAsset` and `@ffi.Native`, which is the
  correct Dart native-asset binding pattern for the package's supported SDK.
- Native callbacks use long-lived `NativeCallable.listener` instances rather
  than stack-scoped callbacks, which is appropriate for calls arriving from
  FFmpeg/native worker threads.
- The loader's explicit `libffmpegkit.so` open is limited to obtaining the
  function pointer needed by a `NativeFinalizer`; ordinary symbols use the
  CodeAssets binding.

## Why it is not the Linux video renderer here

The Linux plugin registers an `FlTextureGL`, uploads frames with OpenGL, copies
decoded frame data more than once, and schedules GTK idle work for frame
delivery. The application crash trace shows Flutter waiting for an OpenGL frame
whose backing-store size still matches the window's previous dimensions. Adding
another GL texture producer would increase rather than remove that failure mode.

Twitch Freedom therefore keeps one playback pipeline:

- Media Kit decodes HLS.
- Crostini presents video through its CPU pixel-buffer path.
- Signed HLS data is cached only in bounded RAM.
- The system FFmpeg adapter is audio-only, starts an absolute allowlisted binary
  directly with `runInShell: false`, and captures at most five seconds into an
  ephemeral file.

Re-evaluate the package for audio-only embedding after its Linux texture queue,
resize behavior, release/unregistration path, and licensing inventory have been
validated independently. It must not be enabled as a second video renderer on
the stable Crostini build.
