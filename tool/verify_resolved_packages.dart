import 'dart:io';

const Map<String, String> expected = <String, String>{
  'archive': '4.0.9',
  'args': '2.7.0',
  'async': '2.13.1',
  'background_downloader': '9.5.7',
  'boolean_selector': '2.1.2',
  'characters': '1.4.1',
  'clock': '1.1.2',
  'code_assets': '1.2.1',
  'collection': '1.19.1',
  'crypto': '3.0.7',
  'cryptography': '2.9.0',
  'cryptography_flutter': '2.3.4',
  'csslib': '1.0.2',
  'dbus': '0.7.14',
  'fake_async': '1.3.3',
  'ffi': '2.2.0',
  'ffi_leak_tracker': '0.1.2',
  'file': '7.0.1',
  'fixnum': '1.1.1',
  'flutter_gemma': '1.4.1',
  'flutter_gemma_litertlm': '1.3.1',
  'flutter_gemma_speech': '0.2.0',
  'flutter_lints': '6.0.0',
  'flutter_secure_storage': '10.3.1',
  'flutter_secure_storage_darwin': '0.3.2',
  'flutter_secure_storage_linux': '3.0.1',
  'flutter_secure_storage_platform_interface': '2.0.2',
  'flutter_secure_storage_web': '2.1.1',
  'flutter_secure_storage_windows': '4.2.2',
  'glob': '2.1.3',
  'hooks': '2.0.2',
  'html': '0.15.6',
  'http': '1.6.0',
  'http_parser': '4.1.2',
  'image': '4.8.0',
  'intl': '0.20.3',
  // Flutter 3.44.0's native-asset resolution selects jni 1.0.3 in CI even
  // though the checked-in lockfile still records the solver-owned 1.0.2.
  'jni': '1.0.3',
  'jni_flutter': '1.0.2',
  'jni_util': '1.0.0',
  'large_file_handler': '0.5.0',
  'leak_tracker': '11.0.2',
  'leak_tracker_flutter_testing': '3.0.10',
  'leak_tracker_testing': '3.0.2',
  'lints': '6.1.0',
  'logging': '1.3.0',
  'matcher': '0.12.19',
  'material_color_utilities': '0.13.0',
  'media_kit': '1.2.6',
  'media_kit_libs_android_video': '1.3.8',
  'media_kit_libs_ios_video': '1.1.4',
  'media_kit_libs_linux': '1.2.1',
  'media_kit_libs_macos_video': '1.1.4',
  'media_kit_libs_video': '1.0.7',
  'media_kit_libs_windows_video': '1.0.11',
  'media_kit_video': '2.0.1',
  'meta': '1.18.0',
  'mime': '2.0.0',
  'mutex': '3.1.0',
  'native_toolchain_c': '0.19.2',
  'objective_c': '9.5.0',
  'package_config': '3.0.0',
  'package_info_plus': '10.2.1',
  'package_info_plus_platform_interface': '4.1.0',
  'path': '1.9.1',
  'path_provider': '2.1.6',
  'path_provider_android': '2.3.1',
  'path_provider_foundation': '2.6.0',
  'path_provider_linux': '2.2.2',
  'path_provider_platform_interface': '2.1.3',
  'path_provider_windows': '2.3.0',
  'petitparser': '7.0.2',
  'platform': '3.1.6',
  'plugin_platform_interface': '2.1.8',
  'posix': '6.5.2',
  'process': '5.0.5',
  'pub_semver': '2.2.0',
  'record_use': '0.6.0',
  'safe_local_storage': '2.0.6',
  'shared_preferences': '2.5.5',
  'shared_preferences_android': '2.4.27',
  'shared_preferences_foundation': '2.5.6',
  'shared_preferences_linux': '2.4.1',
  'shared_preferences_platform_interface': '2.4.2',
  'shared_preferences_web': '2.4.3',
  'shared_preferences_windows': '2.4.1',
  'source_span': '1.10.2',
  'sqlite3': '3.5.0',
  'stack_trace': '1.12.1',
  'stream_channel': '2.1.4',
  'string_scanner': '1.4.1',
  'sync_http': '0.3.1',
  'synchronized': '3.4.1+1',
  'term_glyph': '1.2.2',
  'test_api': '0.7.11',
  'typed_data': '1.4.0',
  'universal_platform': '1.1.0',
  'uri_parser': '3.0.2',
  'url_launcher': '6.3.2',
  'url_launcher_android': '6.3.32',
  'url_launcher_ios': '6.4.1',
  'url_launcher_linux': '3.2.2',
  'url_launcher_macos': '3.2.5',
  'url_launcher_platform_interface': '2.3.2',
  'url_launcher_web': '2.4.3',
  'url_launcher_windows': '3.1.5',
  'uuid': '4.6.0',
  'vector_math': '2.2.0',
  'video_player': '2.13.0',
  'video_player_android': '2.12.0',
  'video_player_avfoundation': '2.11.0',
  'video_player_platform_interface': '6.9.0',
  'video_player_web': '2.4.0',
  // The Flutter SDK pins vm_service 15.0.2 during CI resolution.
  'vm_service': '15.0.2',
  'wakelock_plus': '1.7.0',
  'wakelock_plus_platform_interface': '1.6.0',
  'web': '1.1.1',
  'webdriver': '3.1.0',
  'win32': '6.3.0',
  'xdg_directories': '1.1.0',
  'xml': '6.6.1',
  'yaml': '3.1.3',
};

const Map<String, String> newerButPotentiallyConstrained = <String, String>{
  'flutter_secure_storage_darwin': '0.4.0',
  'hooks': '2.1.0',
  'image': '4.9.1',
  'matcher': '0.12.20',
  'meta': '1.19.0',
  'native_toolchain_c': '0.19.3',
  'record_use': '1.0.0',
  'test_api': '0.7.13',
  'vector_math': '2.4.1',
  'xml': '7.0.1',
};

void main(List<String> arguments) {
  final strict = arguments.contains('--strict');
  final lock = File('pubspec.lock');
  if (!lock.existsSync()) {
    stderr.writeln('pubspec.lock is missing. Run flutter pub get first.');
    exitCode = strict ? 2 : 0;
    return;
  }

  final resolved = _parseLock(lock.readAsLinesSync());
  final mismatches = <String>[];
  for (final entry in expected.entries) {
    final actual = resolved[entry.key];
    if (actual == null) {
      mismatches.add(
        '${entry.key}: expected ${entry.value}, package not present',
      );
    } else if (actual != entry.value) {
      mismatches.add('${entry.key}: expected ${entry.value}, resolved $actual');
    }
  }

  stdout.writeln('Resolved packages inspected: ${resolved.length}');
  if (mismatches.isEmpty) {
    stdout.writeln(
      'The supplied July 2026 package baseline matches all present packages.',
    );
  } else {
    stdout.writeln('Resolution differences (${mismatches.length}):');
    for (final mismatch in mismatches) {
      stdout.writeln('  - $mismatch');
    }
  }

  stdout.writeln('\nNewer transitive versions reported by pub but not forced:');
  for (final entry in newerButPotentiallyConstrained.entries) {
    stdout.writeln('  - ${entry.key} ${entry.value}');
  }
  stdout.writeln(
    'These remain solver-owned because forcing Flutter SDK or native-asset '
    'transitives can break the package graph or ABI.',
  );

  if (strict && mismatches.isNotEmpty) exitCode = 1;
}

Map<String, String> _parseLock(List<String> lines) {
  final result = <String, String>{};
  String? current;
  for (final line in lines) {
    final package = RegExp(r'^  ([A-Za-z0-9_]+):$').firstMatch(line);
    if (package != null) {
      current = package.group(1);
      continue;
    }
    if (current == null) continue;
    final version = RegExp(r'^    version: "?([^"\s]+)"?$').firstMatch(line);
    if (version != null) {
      result[current] = version.group(1)!;
      current = null;
    }
  }
  return result;
}
