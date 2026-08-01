import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/models.dart';
import '../core/result.dart';
import '../core/secure_log.dart';

sealed class ChatEvent {
  const ChatEvent();
}

final class ChatConnecting extends ChatEvent {
  const ChatConnecting(this.channel);
  final String channel;
}

final class ChatConnected extends ChatEvent {
  const ChatConnected(this.channel);
  final String channel;
}

final class ChatReconnecting extends ChatEvent {
  const ChatReconnecting(this.channel, this.delay, this.reason);
  final String channel;
  final Duration delay;
  final String reason;
}

final class ChatDisconnected extends ChatEvent {
  const ChatDisconnected(this.channel, this.userRequested);
  final String channel;
  final bool userRequested;
}

final class ChatMessageReceived extends ChatEvent {
  const ChatMessageReceived(this.message);
  final ChatMessage message;
}

final class ChatNotice extends ChatEvent {
  const ChatNotice(this.message);
  final String message;
}

final class ChatDraftValidation {
  const ChatDraftValidation({
    required this.text,
    required this.characterCount,
    this.error = '',
  });

  final String text;
  final int characterCount;
  final String error;

  bool get valid => error.isEmpty;
}

ChatDraftValidation validateChatDraft(String input) {
  // C0/C1 and Unicode bidi-override controls can alter IRC framing or spoof
  // how a sent message appears. Replace them before counting/sending.
  final clean = input
      .replaceAll(
        RegExp(r'[\x00-\x1F\x7F-\x9F\u202A-\u202E\u2066-\u2069]'),
        ' ',
      )
      .trim();
  final count = clean.runes.length;
  if (clean.isEmpty) {
    return ChatDraftValidation(
      text: clean,
      characterCount: count,
      error: 'Enter a chat message.',
    );
  }
  if (count > 500) {
    return ChatDraftValidation(
      text: clean,
      characterCount: count,
      error: 'Twitch messages are limited to 500 characters.',
    );
  }
  return ChatDraftValidation(text: clean, characterCount: count);
}

final class TwitchIrcClient {
  TwitchIrcClient({required SecureLog log}) : _log = log;

  static const String host = 'irc.chat.twitch.tv';
  static const int port = 6697;
  static const Duration socketTimeout = Duration(seconds: 90);
  static const Duration stableReset = Duration(minutes: 1);

  final SecureLog _log;
  final StreamController<ChatEvent> _events =
      StreamController<ChatEvent>.broadcast();
  final Random _random = Random.secure();

  SecureSocket? _socket;
  StreamSubscription<String>? _subscription;
  bool _stop = true;
  bool _manualStop = false;
  int _generation = 0;
  String _channel = '';
  String _nick = '';
  String _token = '';
  bool _joined = false;

  Stream<ChatEvent> get events => _events.stream;
  bool get connected => _socket != null && !_stop && _joined;
  String get channel => _channel;

  Future<AppResult<void>> connect({
    required String channel,
    required String nick,
    required String accessToken,
  }) async {
    final normalized = channel.toLowerCase().trim();
    if (!RegExp(r'^[a-z0-9_]{3,25}$').hasMatch(normalized)) {
      return const AppError<void>(
        AppFailure('invalid_channel', 'Enter a valid Twitch channel.'),
      );
    }
    if (!RegExp(r'^[A-Za-z0-9_]{1,32}$').hasMatch(nick)) {
      return const AppError<void>(
        AppFailure(
          'invalid_nick',
          'Twitch did not provide a valid login name.',
        ),
      );
    }
    await disconnect(userRequested: false);
    _stop = false;
    _manualStop = false;
    _channel = normalized;
    _nick = nick;
    _token = accessToken.startsWith('oauth:')
        ? accessToken
        : 'oauth:$accessToken';
    final generation = ++_generation;
    _events.add(ChatConnecting(_channel));
    unawaited(_runReconnectLoop(generation));
    return const AppSuccess<void>(null);
  }

  Future<void> _runReconnectLoop(int generation) async {
    var attempt = 0;
    while (!_stop && generation == _generation) {
      final startedAt = DateTime.now();
      try {
        await _openAndRead(generation);
        if (_stop || generation != _generation) return;
        final stable = DateTime.now().difference(startedAt) >= stableReset;
        attempt = stable ? 0 : attempt + 1;
        final delay = _backoff(attempt);
        _events.add(
          ChatReconnecting(
            _channel,
            delay,
            'Twitch closed the IRC connection.',
          ),
        );
        await Future<void>.delayed(delay);
      } on _ReconnectRequested {
        if (_stop || generation != _generation) return;
        attempt = 0;
        const delay = Duration(milliseconds: 350);
        _events.add(
          ChatReconnecting(
            _channel,
            delay,
            'Twitch requested a new IRC session.',
          ),
        );
        await Future<void>.delayed(delay);
      } catch (error) {
        if (_stop || generation != _generation) return;
        attempt++;
        final delay = _backoff(attempt);
        _log.warning('IRC connection ended: $error');
        _events.add(
          ChatReconnecting(_channel, delay, 'Temporary chat connection error.'),
        );
        await Future<void>.delayed(delay);
      } finally {
        await _closeSocket();
      }
    }
    if (generation == _generation) {
      _events.add(ChatDisconnected(_channel, _manualStop));
    }
  }

  Future<void> _openAndRead(int generation) async {
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 12),
      onBadCertificate: (_) => false,
    );
    if (_stop || generation != _generation) {
      socket.destroy();
      return;
    }
    _socket = socket;
    _joined = false;
    _write('PASS $_token');
    _write('NICK $_nick');
    _write('CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership');
    _write('JOIN #$_channel');

    final lines = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final completer = Completer<void>();
    Timer? heartbeat;
    final joinTimeout = Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted && !_joined) {
        completer.completeError(
          TimeoutException('Twitch did not confirm the chat-room join.'),
        );
      }
    });
    var lastData = DateTime.now();
    heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      if (DateTime.now().difference(lastData) > const Duration(seconds: 75)) {
        try {
          _write(
            'PING :twitchfreedom-${DateTime.now().millisecondsSinceEpoch}',
          );
        } catch (_) {
          socket.destroy();
        }
      }
    });

    _subscription = lines.listen(
      (String line) {
        lastData = DateTime.now();
        try {
          _handleLine(line);
        } on _ReconnectRequested catch (request) {
          if (!completer.isCompleted) completer.completeError(request);
        } catch (error) {
          _log.warning('Ignored malformed IRC line: $error');
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    try {
      await completer.future;
    } finally {
      joinTimeout.cancel();
      heartbeat.cancel();
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  void _handleLine(String rawLine) {
    final line = rawLine.trimRight();
    if (line.isEmpty) return;
    if (line.startsWith('PING')) {
      _write(line.replaceFirst('PING', 'PONG'));
      return;
    }
    if (line == ':tmi.twitch.tv RECONNECT' || line.contains(' RECONNECT')) {
      throw const _ReconnectRequested();
    }
    if (line.contains('Login authentication failed') ||
        line.contains('Improperly formatted auth')) {
      _events.add(
        const ChatNotice(
          'Twitch rejected the chat token. Re-authorize in Settings.',
        ),
      );
      _stop = true;
      _token = '';
      _socket?.destroy();
      return;
    }
    if (RegExp(r'^:tmi\.twitch\.tv 001 [^ ]+ ').hasMatch(line)) {
      return;
    }
    if (line.contains(' CAP * NAK ')) {
      _events.add(
        const ChatNotice(
          'Twitch rejected required chat capabilities; reconnecting.',
        ),
      );
      throw const _ReconnectRequested();
    }
    final ownJoin = RegExp(
      '^:${RegExp.escape(_nick)}![^ ]+ JOIN #${RegExp.escape(_channel)}\$',
      caseSensitive: false,
    ).hasMatch(line);
    final roomReady =
        line.contains(' ROOMSTATE #$_channel') ||
        line.contains(' USERSTATE #$_channel');
    if (ownJoin || roomReady) {
      _markJoined();
    }
    final parsed = parsePrivmsg(line, _channel, _nick);
    if (parsed != null) {
      _markJoined();
      _events.add(ChatMessageReceived(parsed));
      return;
    }
    if (line.contains(' NOTICE ') && line.contains(' :')) {
      _events.add(ChatNotice(_sanitize(line.split(' :').last, 400)));
    }
  }

  void _markJoined() {
    if (_joined) return;
    _joined = true;
    _events.add(ChatConnected(_channel));
  }

  Future<void> disconnect({required bool userRequested}) async {
    final disconnectedChannel = _channel;
    _manualStop = userRequested;
    _stop = true;
    _generation++;
    await _closeSocket();
    _channel = '';
    _nick = '';
    _token = '';
    if (disconnectedChannel.isNotEmpty) {
      _events.add(ChatDisconnected(disconnectedChannel, userRequested));
    }
  }

  Future<void> _closeSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    _joined = false;
    if (socket != null) {
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  void _write(String command) {
    final socket = _socket;
    if (socket == null)
      throw const SocketException('IRC socket is not connected.');
    socket.add(utf8.encode('$command\r\n'));
  }

  Duration _backoff(int attempt) {
    final seconds = min(30, max(1, 1 << min(attempt, 5)));
    final jitter = _random.nextInt(600);
    return Duration(seconds: seconds, milliseconds: jitter);
  }

  Future<void> dispose() async {
    await disconnect(userRequested: true);
    await _events.close();
  }
}

ChatMessage? parsePrivmsg(String line, String channel, String ownNick) {
  var remaining = line;
  final tags = <String, String>{};
  if (remaining.startsWith('@')) {
    final split = remaining.indexOf(' ');
    if (split < 0) return null;
    final rawTags = remaining.substring(1, split);
    remaining = remaining.substring(split + 1);
    for (final tag in rawTags.split(';')) {
      final equals = tag.indexOf('=');
      final key = equals < 0 ? tag : tag.substring(0, equals);
      final value = equals < 0 ? '' : _ircUnescape(tag.substring(equals + 1));
      tags[key] = value;
    }
  }
  final match = RegExp(
    r'^:([^!]+)![^ ]+ PRIVMSG #([a-zA-Z0-9_]+) :(.+)$',
  ).firstMatch(remaining);
  if (match == null) return null;
  if (match.group(2)!.toLowerCase() != channel.toLowerCase()) return null;
  final login = match.group(1)!;
  final user = _sanitize(
    tags['display-name']?.isNotEmpty == true ? tags['display-name']! : login,
    32,
  );
  final text = _sanitize(match.group(3)!, 500);
  if (text.isEmpty) return null;
  final id = tags['id']?.isNotEmpty == true
      ? tags['id']!
      : '${DateTime.now().microsecondsSinceEpoch}-${user.hashCode}';
  return ChatMessage(
    id: id,
    channel: channel,
    user: user,
    text: text,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      int.tryParse(tags['tmi-sent-ts'] ?? '') ??
          DateTime.now().millisecondsSinceEpoch,
      isUtc: true,
    ).toLocal(),
    tags: Map<String, String>.unmodifiable(tags),
    isOwn: login.toLowerCase() == ownNick.toLowerCase(),
    isModerator:
        tags['mod'] == '1' ||
        tags['badges']?.contains('moderator/') == true ||
        tags['badges']?.contains('broadcaster/') == true,
  );
}

String _ircUnescape(String value) => value
    .replaceAll(r'\s', ' ')
    .replaceAll(r'\:', ';')
    .replaceAll(r'\r', '\r')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\\', '\\');

String _sanitize(String value, int maximum) {
  final clean = value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
      .trim();
  return clean.length > maximum ? clean.substring(0, maximum) : clean;
}

final class _ReconnectRequested implements Exception {
  const _ReconnectRequested();
}
