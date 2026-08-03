import 'dart:io';

void main(List<String> arguments) {
  if (arguments.length != 1 ||
      !RegExp(r'^\d+(?:\.\d+)*$').hasMatch(arguments.single)) {
    stderr.writeln('usage: dart run tool/verify_release_version.dart X.Y.Z');
    exitCode = 64;
    return;
  }
  final pubspec = File('pubspec.yaml').readAsLinesSync();
  final line = pubspec.firstWhere(
    (value) => value.startsWith('version:'),
    orElse: () => '',
  );
  final declared = line.replaceFirst('version:', '').trim().split('+').first;
  if (declared != arguments.single) {
    stderr.writeln(
      'Release version mismatch: workflow=${arguments.single}, '
      'pubspec=$declared.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('Release version verified: $declared');
}
