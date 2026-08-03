import 'dart:collection';

final class SecureLogEntry {
  const SecureLogEntry({
    required this.time,
    required this.level,
    required this.message,
  });
  final DateTime time;
  final String level;
  final String message;
}

final class SecureLog {
  SecureLog({this.maxEntries = 500});

  final int maxEntries;
  final Queue<SecureLogEntry> _entries = Queue<SecureLogEntry>();

  static final List<RegExp> _secretPatterns = <RegExp>[
    RegExp(r'(oauth:)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    RegExp(r'(bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    RegExp(r'(basic\s+)[A-Za-z0-9+/=]+', caseSensitive: false),
    RegExp(
      r'''(client[_-]?secret["'\s:=]+)[^\s,&;"']+''',
      caseSensitive: false,
    ),
    RegExp(r'''(access[_-]?token["'\s:=]+)[^\s,&;"']+''', caseSensitive: false),
    RegExp(
      r'''(refresh[_-]?token["'\s:=]+)[^\s,&;"']+''',
      caseSensitive: false,
    ),
    RegExp(
      r'''((?:device|user)[_-]?code["'\s:=]+)[^\s,&;"']+''',
      caseSensitive: false,
    ),
    RegExp(
      r'''(code[_-]?verifier["'\s:=]+)[^\s,&;"']+''',
      caseSensitive: false,
    ),
    RegExp(r'(sig=)[^&\s]+', caseSensitive: false),
    RegExp(r'(token=)[^&\s]+', caseSensitive: false),
  ];

  List<SecureLogEntry> get entries =>
      List<SecureLogEntry>.unmodifiable(_entries);

  void info(String message) => _add('INFO', message);
  void warning(String message) => _add('WARN', message);
  void error(String message) => _add('ERROR', message);

  void _add(String level, String value) {
    var message = value.replaceAll(
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'),
      '',
    );
    for (final pattern in _secretPatterns) {
      message = message.replaceAllMapped(pattern, (Match match) {
        final prefix = match.groupCount >= 1 ? (match.group(1) ?? '') : '';
        return '$prefix[REDACTED]';
      });
    }
    if (message.length > 1800) {
      message = '${message.substring(0, 1800)}…';
    }
    _entries.add(
      SecureLogEntry(time: DateTime.now(), level: level, message: message),
    );
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
  }

  void clear() => _entries.clear();
}
