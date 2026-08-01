import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import 'twitch_auth.dart';

final class DiscoveryStream {
  const DiscoveryStream({
    required this.id,
    required this.channel,
    required this.displayName,
    required this.title,
    required this.category,
    required this.language,
    required this.viewerCount,
    required this.startedAt,
    this.reason = '',
  });

  final String id;
  final String channel;
  final String displayName;
  final String title;
  final String category;
  final String language;
  final int viewerCount;
  final DateTime startedAt;
  final String reason;

  DiscoveryStream copyWith({String? reason}) => DiscoveryStream(
    id: id,
    channel: channel,
    displayName: displayName,
    title: title,
    category: category,
    language: language,
    viewerCount: viewerCount,
    startedAt: startedAt,
    reason: reason ?? this.reason,
  );
}

final class ChatSendReceipt {
  const ChatSendReceipt({required this.messageId});

  final String messageId;
}

ChatSendReceipt decodeChatSendReceipt(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<Object?, Object?>) {
    throw const FormatException('Expected a Twitch JSON object.');
  }
  final body = Map<String, Object?>.from(decoded);
  final data = body['data'] as List<Object?>? ?? const <Object?>[];
  if (data.isEmpty || data.first is! Map<Object?, Object?>) {
    throw const FormatException('Twitch returned no send receipt.');
  }
  final receipt = Map<String, Object?>.from(
    data.first! as Map<Object?, Object?>,
  );
  final sent = receipt['is_sent'] == true;
  final messageId = (receipt['message_id'] as String?) ?? '';
  if (!sent || messageId.isEmpty) {
    final rawDrop = receipt['drop_reason'];
    final drop = rawDrop is Map<Object?, Object?>
        ? Map<String, Object?>.from(rawDrop)
        : const <String, Object?>{};
    final explanation = (drop['message']?.toString() ?? '')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .trim();
    throw AppFailure(
      'chat_message_dropped',
      explanation.isEmpty
          ? 'Twitch did not accept the chat message.'
          : explanation.length > 500
          ? explanation.substring(0, 500)
          : explanation,
    );
  }
  return ChatSendReceipt(messageId: messageId);
}

final class TwitchHelixService {
  TwitchHelixService({
    required TwitchAuthService auth,
    required SecureLog log,
    http.Client? client,
  }) : _auth = auth,
       _log = log,
       _client = client ?? http.Client();

  final TwitchAuthService _auth;
  final SecureLog _log;
  final http.Client _client;

  Future<AppResult<List<DiscoveryStream>>> followedStreams() async {
    try {
      final state = await _auth.tokenState();
      if (state == null || state.userId.isEmpty) {
        return const AppError<List<DiscoveryStream>>(
          AppFailure(
            'not_authorized',
            'Authorize Twitch to load followed channels.',
          ),
        );
      }
      return _getStreams(<String, String>{
        'user_id': state.userId,
        'first': '100',
      }, path: '/streams/followed');
    } catch (error) {
      return AppError<List<DiscoveryStream>>(
        AppFailure(
          'followed_streams_failed',
          'Could not load followed Twitch channels.',
          cause: error,
          retryable: true,
        ),
      );
    }
  }

  Future<AppResult<List<DiscoveryStream>>> searchByCategory(
    String categoryName, {
    int first = 40,
  }) async {
    try {
      final categories = await _get('/search/categories', <String, String>{
        'query': categoryName,
        'first': '10',
      });
      final list = categories['data'] as List<Object?>? ?? const <Object?>[];
      if (list.isEmpty)
        return const AppSuccess<List<DiscoveryStream>>(<DiscoveryStream>[]);
      final best = Map<String, Object?>.from(
        list.first as Map<Object?, Object?>,
      );
      return _getStreams(<String, String>{
        'game_id': best['id']! as String,
        'first': '$first',
      });
    } catch (error) {
      return AppError<List<DiscoveryStream>>(
        AppFailure(
          'category_search_failed',
          'Could not search Twitch categories.',
          cause: error,
          retryable: true,
        ),
      );
    }
  }

  Future<AppResult<List<DiscoveryStream>>> searchChannels(
    String query, {
    int first = 40,
  }) async {
    try {
      final response = await _get('/search/channels', <String, String>{
        'query': query,
        'first': '$first',
        'live_only': 'true',
      });
      final data = response['data'] as List<Object?>? ?? const <Object?>[];
      return AppSuccess<List<DiscoveryStream>>(
        data
            .map((Object? raw) {
              final item = Map<String, Object?>.from(
                raw! as Map<Object?, Object?>,
              );
              return DiscoveryStream(
                id:
                    (item['id'] as String?) ??
                    (item['broadcaster_login'] as String?) ??
                    '',
                channel: ((item['broadcaster_login'] as String?) ?? '')
                    .toLowerCase(),
                displayName:
                    (item['display_name'] as String?) ??
                    (item['broadcaster_login'] as String?) ??
                    '',
                title: _clean(item['title']),
                category: _clean(item['game_name']),
                language: (item['broadcaster_language'] as String?) ?? '',
                viewerCount: 0,
                startedAt: DateTime.now(),
              );
            })
            .where((DiscoveryStream item) => item.channel.isNotEmpty)
            .toList(growable: false),
      );
    } catch (error) {
      return AppError<List<DiscoveryStream>>(
        AppFailure(
          'channel_search_failed',
          'Could not search Twitch channels.',
          cause: error,
          retryable: true,
        ),
      );
    }
  }

  Future<AppResult<Set<String>>> onlineChannels(
    Iterable<String> channels,
  ) async {
    try {
      final unique = channels
          .map((String value) => value.toLowerCase())
          .where(_validLogin)
          .toSet()
          .toList();
      final online = <String>{};
      for (var offset = 0; offset < unique.length; offset += 100) {
        final query = <String, List<String>>{
          'user_login': unique.skip(offset).take(100).toList(),
          'first': <String>['100'],
        };
        final response = await _getMulti('/streams', query);
        for (final raw
            in response['data'] as List<Object?>? ?? const <Object?>[]) {
          final item = Map<String, Object?>.from(raw! as Map<Object?, Object?>);
          final login = (item['user_login'] as String?)?.toLowerCase();
          if (login != null) online.add(login);
        }
      }
      return AppSuccess<Set<String>>(online);
    } catch (error) {
      return AppError<Set<String>>(
        AppFailure(
          'online_check_failed',
          'Could not refresh live status.',
          cause: error,
          retryable: true,
        ),
      );
    }
  }

  Future<AppResult<String>> resolveUserId(String login) async {
    final normalized = login.trim().toLowerCase();
    if (!_validLogin(normalized)) {
      return const AppError<String>(
        AppFailure('invalid_channel', 'The Twitch channel name is invalid.'),
      );
    }
    try {
      final response = await _get('/users', <String, String>{
        'login': normalized,
      });
      final data = response['data'] as List<Object?>? ?? const <Object?>[];
      if (data.isEmpty) {
        return const AppError<String>(
          AppFailure(
            'broadcaster_missing',
            'Twitch could not find that channel.',
          ),
        );
      }
      final item = Map<String, Object?>.from(
        data.first! as Map<Object?, Object?>,
      );
      final id = (item['id'] as String?) ?? '';
      if (id.isEmpty) throw const FormatException('Missing Twitch user ID.');
      return AppSuccess<String>(id);
    } catch (error) {
      return AppError<String>(
        AppFailure(
          'broadcaster_lookup_failed',
          'Could not resolve the Twitch channel identity.',
          cause: error,
          retryable: true,
        ),
      );
    }
  }

  Future<AppResult<ChatSendReceipt>> sendChat(
    String broadcasterId,
    String message,
  ) async {
    try {
      final state = await _auth.tokenState();
      if (state == null || state.userId.isEmpty)
        throw StateError('No Twitch user identity.');
      final access = await _auth.validAccessToken();
      final token = access.fold(
        success: (String value) => value,
        failure: (AppFailure failure) => throw failure,
      );
      final credentials = await _auth.credentials();
      if (credentials == null) throw StateError('No Twitch app credentials.');
      final response = await _client
          .post(
            AppConfig.twitchHelix.resolve('/helix/chat/messages'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Client-Id': credentials.clientId,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'broadcaster_id': broadcasterId,
              'sender_id': state.userId,
              'message': message,
            }),
          )
          .timeout(AppConfig.networkTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppFailure(
          'chat_send_failed',
          'Twitch rejected the chat message with HTTP ${response.statusCode}.',
        );
      }
      return AppSuccess<ChatSendReceipt>(decodeChatSendReceipt(response.body));
    } catch (error) {
      final failure = error is AppFailure
          ? error
          : AppFailure(
              'chat_send_failed',
              'Could not send the Twitch chat message.',
              cause: error,
              retryable: true,
            );
      return AppError<ChatSendReceipt>(failure);
    }
  }

  Future<AppResult<List<DiscoveryStream>>> _getStreams(
    Map<String, String> query, {
    String path = '/streams',
  }) async {
    try {
      final response = await _get(path, query);
      final data = response['data'] as List<Object?>? ?? const <Object?>[];
      final streams = data
          .map((Object? raw) {
            final item = Map<String, Object?>.from(
              raw! as Map<Object?, Object?>,
            );
            return DiscoveryStream(
              id: (item['id'] as String?) ?? '',
              channel: ((item['user_login'] as String?) ?? '').toLowerCase(),
              displayName:
                  (item['user_name'] as String?) ??
                  (item['user_login'] as String?) ??
                  '',
              title: _clean(item['title']),
              category: _clean(item['game_name']),
              language: (item['language'] as String?) ?? '',
              viewerCount: (item['viewer_count'] as num?)?.toInt() ?? 0,
              startedAt:
                  DateTime.tryParse((item['started_at'] as String?) ?? '') ??
                  DateTime.now(),
            );
          })
          .where((DiscoveryStream item) => item.channel.isNotEmpty)
          .toList(growable: false);
      return AppSuccess<List<DiscoveryStream>>(streams);
    } catch (error) {
      return AppError<List<DiscoveryStream>>(
        AppFailure(
          'streams_failed',
          'Could not load Twitch streams.',
          cause: error,
          retryable: true,
        ),
      );
    }
  }

  Future<Map<String, Object?>> _get(String path, Map<String, String> query) {
    return _authorizedGet(
      AppConfig.twitchHelix
          .resolve('/helix$path')
          .replace(queryParameters: query),
    );
  }

  Future<Map<String, Object?>> _getMulti(
    String path,
    Map<String, List<String>> query,
  ) {
    final pairs = <MapEntry<String, String>>[];
    query.forEach((String key, List<String> values) {
      for (final value in values) {
        pairs.add(MapEntry<String, String>(key, value));
      }
    });
    final queryText = pairs
        .map(
          (MapEntry<String, String> item) =>
              '${Uri.encodeQueryComponent(item.key)}=${Uri.encodeQueryComponent(item.value)}',
        )
        .join('&');
    return _authorizedGet(
      Uri.parse('${AppConfig.twitchHelix.resolve('/helix$path')}?$queryText'),
    );
  }

  Future<Map<String, Object?>> _authorizedGet(Uri uri) async {
    final access = await _auth.validAccessToken();
    final token = access.fold(
      success: (String value) => value,
      failure: (AppFailure failure) => throw failure,
    );
    final credentials = await _auth.credentials();
    if (credentials == null)
      throw StateError('Twitch credentials are not configured.');
    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Client-Id': credentials.clientId,
          },
        )
        .timeout(AppConfig.networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log.warning('Helix request failed: ${response.statusCode} ${uri.path}');
      throw AppFailure(
        'helix_http_error',
        'Twitch API returned HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<Object?, Object?>)
      throw const FormatException('Expected a Twitch JSON object.');
    return Map<String, Object?>.from(decoded);
  }

  String _clean(Object? value) {
    final text = (value?.toString() ?? '')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .trim();
    return text.length > 500 ? text.substring(0, 500) : text;
  }

  bool _validLogin(String value) =>
      RegExp(r'^[a-z0-9_]{3,25}$').hasMatch(value);
  void dispose() => _client.close();
}
