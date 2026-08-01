# Dependency upgrade report

The application now pins its direct runtime dependencies to the versions from
the July 29, 2026 resolution supplied for this project.

## Direct pins updated

- `http 1.6.0`
- `crypto 3.0.7`
- `cryptography 2.9.0`
- `cryptography_flutter 2.3.4`
- `flutter_secure_storage 10.3.1`
- `sqlite3 3.5.0`
- `path 1.9.1`
- `path_provider 2.1.6`
- `uuid 4.6.0`
- `intl 0.20.3`
- `meta 1.18.0`
- `video_player 2.13.0`
- `media_kit 1.2.6`
- `media_kit_video 2.0.1`
- `media_kit_libs_video 1.0.7`
- `flutter_gemma 1.4.1`
- `flutter_gemma_litertlm 1.3.1`
- `flutter_gemma_speech 0.2.0`
- `url_launcher 6.3.2`
- `wakelock_plus 1.7.0`
- `package_info_plus 10.2.1`

## Why transitive packages are not overridden

Packages such as `matcher`, `test_api`, `meta`, `vector_math`, `hooks`,
`native_toolchain_c`, and platform implementations of Flutter plugins are
selected by the Flutter SDK and their owning packages. Forcing newer transitive
versions with `dependency_overrides` can create an invalid SDK graph or native
ABI mismatch. The project deliberately lets `flutter pub get` select those
versions from the pinned direct graph.

Run:

```bash
flutter pub get
flutter pub outdated
flutter analyze
flutter test
```

The generated `pubspec.lock` is the authoritative complete resolution for the
installed Flutter SDK.


## Linux plugin correction

The old direct `ffmpeg_kit_flutter_new` dependency was removed. The newer
`ffmpeg_kit_extended_flutter` package was audited at upstream commit
`d06b6902b68ab0aef4d8f9ead7f2544a45686440`: its CodeAssets bindings are valid,
but its Linux video output is OpenGL-based and conflicts with this app's
Crostini resize-crash mitigation. Linux therefore uses `media_kit` for playback
and the hardened `SystemFfmpegAdapter` only for ephemeral PCM extraction.
