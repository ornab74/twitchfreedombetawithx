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
}
