import 'dart:io';

final forbidden = <RegExp>[
  RegExp(r'http://'),
  RegExp(r'Process\.run\([^\n]*runInShell\s*:\s*true'),
  RegExp(r'WebView'),
  RegExp(r'''clientSecret\s*=\s*["'][^"']+["']'''),
  RegExp(r'''accessToken\s*=\s*["'][^"']+["']'''),
];

void main() {
  final root = Directory('lib');
  if (!root.existsSync()) {
    stderr.writeln('lib directory not found');
    exitCode = 2;
    return;
  }
  final violations = <String>[];
  for (final entity in root.listSync(recursive: true).whereType<File>().where((File file) => file.path.endsWith('.dart'))) {
    final source = entity.readAsStringSync();
    for (final rule in forbidden) {
      if (rule.hasMatch(source)) violations.add('${entity.path}: matched ${rule.pattern}');
    }
  }
  if (violations.isNotEmpty) {
    stderr.writeln('Security source check failed:');
    for (final value in violations) stderr.writeln(' - $value');
    exitCode = 1;
    return;
  }
  stdout.writeln('Security source checks passed.');
}
