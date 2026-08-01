import 'dart:io';

void main() {
  _patchAndroid();
  _patchApple();
  _patchLinux();
  _repairToolPermissions();
  stdout.writeln(
    'Generated platform security/capability configuration applied.',
  );
}

void _patchAndroid() {
  final gradle = File('android/app/build.gradle.kts');
  if (gradle.existsSync()) {
    var text = gradle.readAsStringSync();
    text = text.replaceFirst('minSdk = flutter.minSdkVersion', 'minSdk = 30');
    if (!text.contains('abiFilters += listOf("arm64-v8a")')) {
      text = text.replaceFirst(
        'minSdk = 30',
        'minSdk = 30\n        ndk { abiFilters += listOf("arm64-v8a") }',
      );
    }
    gradle.writeAsStringSync(text);
  }

  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    var text = manifest.readAsStringSync();
    if (!text.contains('android.permission.INTERNET')) {
      text = text.replaceFirst(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <uses-permission android:name="android.permission.INTERNET" />',
      );
    }
    manifest.writeAsStringSync(text);
  }
}

void _patchApple() {
  const deploymentTargets = <String, (String, String)>{
    'ios/Runner.xcodeproj/project.pbxproj': (
      'IPHONEOS_DEPLOYMENT_TARGET',
      '16.0',
    ),
    'macos/Runner.xcodeproj/project.pbxproj': (
      'MACOSX_DEPLOYMENT_TARGET',
      '12.0',
    ),
  };
  for (final entry in deploymentTargets.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) continue;
    final (setting, version) = entry.value;
    final text = file.readAsStringSync().replaceAll(
      RegExp('$setting = [^;]+;'),
      '$setting = $version;',
    );
    file.writeAsStringSync(text);
  }

  for (final path in <String>['ios/Podfile', 'macos/Podfile']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    final target = path.startsWith('ios')
        ? "platform :ios, '16.0'"
        : "platform :osx, '12.0'";
    final pattern = path.startsWith('ios')
        ? RegExp(r"#?\s*platform :ios, '[^']+'")
        : RegExp(r"#?\s*platform :osx, '[^']+'");
    if (pattern.hasMatch(text)) {
      text = text.replaceFirst(pattern, target);
    } else {
      text = '$target\n$text';
    }
    file.writeAsStringSync(text);
  }

  for (final path in <String>[
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    if (!text.contains('com.apple.security.network.client')) {
      text = text.replaceFirst(
        '</dict>',
        '\t<key>com.apple.security.network.client</key>\n\t<true/>\n</dict>',
      );
    }
    file.writeAsStringSync(text);
  }
}

void _patchLinux() {
  final template = File('tool/linux_main_software.cc');
  final destination = File('linux/runner/main.cc');
  if (!template.existsSync() || !destination.parent.existsSync()) return;
  destination.writeAsStringSync(template.readAsStringSync());

  stdout.writeln(
    'Linux runner configured for responsive Crostini X11 with a capability-'
    'based CPU-OpenGL fallback and isolated media/AI workloads.',
  );
}

void _repairToolPermissions() {
  if (Platform.isWindows) return;
  for (final path in <String>[
    'tool/bootstrap.sh',
    'tool/package_linux_deb.sh',
    'tool/package_macos_dmg.sh',
    'tool/verify_linux_ready.sh',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final result = Process.runSync('chmod', <String>['u+x', path]);
    if (result.exitCode != 0) {
      stderr.writeln(
        'Warning: could not mark $path executable. Run: chmod +x $path',
      );
    }
  }
}
