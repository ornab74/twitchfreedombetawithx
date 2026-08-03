import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Start-menu shortcut uses a per-user WiX key path', () {
    final script = File('tool/package_windows_msi.ps1').readAsStringSync();
    final shortcutComponent = RegExp(
      r'<Component Id="ApplicationShortcut"[\s\S]*?</Component>',
    ).firstMatch(script);

    expect(shortcutComponent, isNotNull);
    final source = shortcutComponent!.group(0)!;
    expect(source, contains('<RegistryValue Root="HKCU"'));
    expect(source, contains('KeyPath="yes"'));
    expect(source, isNot(contains('<RegistryValue Root="HKLM"')));
  });

  test('Windows remembered unlock is explicitly user-scoped DPAPI', () {
    final vault = File('lib/security/vault.dart').readAsStringSync();
    expect(vault, contains('WindowsOptions(useBackwardCompatibility: false)'));
    expect(
      vault,
      isNot(contains('WindowsOptions(useBackwardCompatibility: true)')),
    );

    final packageConfigFile = File('.dart_tool/package_config.json');
    final packageConfig =
        jsonDecode(packageConfigFile.readAsStringSync())
            as Map<String, Object?>;
    final packages = packageConfig['packages']! as List<Object?>;
    final windowsStorage = packages.cast<Map<String, Object?>>().singleWhere(
      (entry) => entry['name'] == 'flutter_secure_storage_windows',
    );
    final configuredRoot = windowsStorage['rootUri']! as String;
    final packageRoot = packageConfigFile.absolute.uri.resolve(
      configuredRoot.endsWith('/') ? configuredRoot : '$configuredRoot/',
    );
    final implementation = File.fromUri(
      packageRoot.resolve('lib/src/flutter_secure_storage_windows_ffi.dart'),
    ).readAsStringSync();
    expect(implementation, contains('CryptProtectData('));
    expect(implementation, contains('CryptUnprotectData('));
    expect(implementation, isNot(contains('CRYPTPROTECT_LOCAL_MACHINE')));

    final lock = File('pubspec.lock').readAsStringSync();
    expect(lock, contains('flutter_secure_storage_windows:'));
    expect(lock, contains('version: "4.2.2"'));
    expect(
      lock,
      contains(
        '471951813a97006d899db4948acc654a4f28c440083ea08178935ce20b173ec1',
      ),
    );
  });

  test('Windows release tags require signing and strict dependencies', () {
    final workflow = File('.github/workflows/build.yml').readAsStringSync();
    final packager = File('tool/package_windows_msi.ps1').readAsStringSync();

    expect(workflow, contains('flutter pub get --enforce-lockfile'));
    expect(workflow, contains('verify_resolved_packages.dart --strict'));
    expect(workflow, contains("startsWith(github.ref, 'refs/tags/v')"));
    expect(workflow, contains('WINDOWS_SIGNING_PFX_BASE64'));
    expect(workflow, contains('WINDOWS_SIGNING_PFX_PASSWORD'));
    expect(packager, contains('Invoke-AuthenticodeSign'));
    expect(packager, contains('signtool.exe'));
    expect(packager, contains('verify /nologo /pa /all'));
  });
}
