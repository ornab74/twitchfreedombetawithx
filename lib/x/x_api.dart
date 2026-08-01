import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/app_config.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import 'x_models.dart';

final class XApiService {
  XApiService({required SecureLog log}) : _log = log;

  final SecureLog _log;

  static final RegExp _handlePattern = RegExp(r'^[A-Za-z0-9_]{1,15}$');

  Future<AppResult<List<XPost>>> userPosts({
    required String handle,
    required String bearerToken,
  }) async {
    final normalized = handle.trim().replaceFirst(RegExp(r'^@'), '');
    if (!_handlePattern.hasMatch(normalized)) {
      return const AppError<List<XPost>>(
        AppFailure('x_invalid_handle', 'Enter a valid X handle.'),
      );
    }
    if (bearerToken.trim().length < 20) {
      return const AppError<List<XPost>>(
        AppFailure('x_token_missing', 'Add an X API bearer token first.'),
      );
    }
    final client = HttpClient()..connectionTimeout = AppConfig.networkTimeout;
    client.badCertificateCallback = (_, __, ___) => false;
    try {
      final user = await _getJson(
        client,
        Uri.https('api.x.com', '/2/users/by/username/$normalized'),
        bearerToken,
      );
      final data = user['data'];
      final id = data is Map ? data['id'] as String? : null;
      if (id == null || id.isEmpty) {
        return const AppError<List<XPost>>(
          AppFailure('x_user_missing', 'That X account was not found.'),
        );
      }
      final timeline = await _getJson(
        client,
        Uri.https(
          'api.x.com',
          '/2/users/$id/tweets',
          _timelineParameters(maxResults: 25)..['exclude'] = 'retweets,replies',
        ),
        bearerToken,
      );
      return AppSuccess<List<XPost>>(parseTimeline(timeline));
    } on TimeoutException catch (error) {
      return AppError<List<XPost>>(
        AppFailure('x_timeout', 'X did not respond in time.', cause: error),
      );
    } on XApiException catch (error) {
      return AppError<List<XPost>>(
        AppFailure(error.code, error.message, cause: error),
      );
    } catch (error) {
      _log.warning('X API request failed without credential details: $error');
      return AppError<List<XPost>>(
        AppFailure(
          'x_request_failed',
          'Could not load posts from X.',
          cause: error,
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AppResult<List<XPost>>> homeFeed({
    required String bearerToken,
    String? sinceId,
  }) async {
    final result = await _withClient((client) async {
      final me = await _getJson(
        client,
        Uri.https('api.x.com', '/2/users/me', <String, String>{
          'user.fields': 'id,name,username,profile_image_url',
        }),
        bearerToken,
      );
      final data = me['data'];
      final id = data is Map ? data['id'] as String? : null;
      if (id == null || id.isEmpty) {
        throw const XApiException(
          'x_user_context_required',
          'My Feed requires an OAuth user access token.',
        );
      }
      final parameters = _timelineParameters(maxResults: 100);
      if (sinceId != null && _isPostId(sinceId)) {
        parameters['since_id'] = sinceId;
      }
      final payload = await _getJson(
        client,
        Uri.https(
          'api.x.com',
          '/2/users/$id/timelines/reverse_chronological',
          parameters,
        ),
        bearerToken,
      );
      return parseHomeTimeline(payload, ownUserId: id);
    });
    if (result case AppError<List<XPost>>(
      error: AppFailure(code: 'x_unauthorized'),
    )) {
      return const AppError<List<XPost>>(
        AppFailure(
          'x_user_context_required',
          'My Feed requires an OAuth user access token with tweet.read and users.read.',
        ),
      );
    }
    return result;
  }

  Future<AppResult<List<XFollow>>> following({
    required String bearerToken,
    int maxPages = 10,
  }) => _relationships(
    bearerToken: bearerToken,
    relationship: 'following',
    maxPages: maxPages,
  );

  Future<AppResult<List<XFollow>>> followers({
    required String bearerToken,
    int maxPages = 10,
  }) => _relationships(
    bearerToken: bearerToken,
    relationship: 'followers',
    maxPages: maxPages,
  );

  Future<AppResult<List<XFollow>>> _relationships({
    required String bearerToken,
    required String relationship,
    required int maxPages,
  }) async {
    final client = HttpClient()..connectionTimeout = AppConfig.networkTimeout;
    client.badCertificateCallback = (_, __, ___) => false;
    try {
      final me = await _getJson(
        client,
        Uri.https('api.x.com', '/2/users/me'),
        bearerToken,
      );
      final meData = me['data'];
      final userId = meData is Map<Object?, Object?>
          ? meData['id'] as String?
          : null;
      if (userId == null || userId.isEmpty) {
        throw const XApiException(
          'x_user_context_required',
          'Following sync requires an OAuth user access token.',
        );
      }
      final follows = <XFollow>[];
      String? paginationToken;
      for (var page = 0; page < maxPages; page++) {
        final query = <String, String>{
          'max_results': '1000',
          'user.fields': 'id,name,username,description,profile_image_url',
          if (paginationToken != null) 'pagination_token': paginationToken,
        };
        final payload = await _getJson(
          client,
          Uri.https('api.x.com', '/2/users/$userId/$relationship', query),
          bearerToken,
        );
        final now = DateTime.now().toUtc();
        final rows = payload['data'];
        if (rows is List) {
          for (final raw in rows.whereType<Map<Object?, Object?>>()) {
            final row = Map<String, Object?>.from(raw);
            final id = row['id'] as String?;
            if (id == null || id.isEmpty) continue;
            final avatar = row['profile_image_url'] as String?;
            follows.add(
              XFollow(
                id: id,
                name: (row['name'] as String?) ?? '',
                username: (row['username'] as String?) ?? '',
                description: (row['description'] as String?) ?? '',
                avatarUrl: avatar == null ? null : Uri.tryParse(avatar),
                syncedAt: now,
                isFollowing: relationship == 'following',
                followsYou: relationship == 'followers',
              ),
            );
          }
        }
        final meta = payload['meta'];
        paginationToken = meta is Map ? meta['next_token'] as String? : null;
        if (paginationToken == null || paginationToken.isEmpty) break;
      }
      return AppSuccess<List<XFollow>>(follows);
    } on TimeoutException catch (error) {
      return AppError<List<XFollow>>(
        AppFailure('x_timeout', 'X did not respond in time.', cause: error),
      );
    } on XApiException catch (error) {
      return AppError<List<XFollow>>(
        AppFailure(error.code, error.message, cause: error),
      );
    } catch (error) {
      _log.warning(
        'X following sync failed without credential details: $error',
      );
      return AppError<List<XFollow>>(
        AppFailure(
          'x_follows_failed',
          'Could not sync X follows.',
          cause: error,
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<AppResult<List<XPost>>> searchRecent({
    required String query,
    required String bearerToken,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty ||
        normalized.length > 512 ||
        normalized.runes.any((r) => r < 32)) {
      return const AppError<List<XPost>>(
        AppFailure(
          'x_invalid_query',
          'Search must contain 1 to 512 visible characters.',
        ),
      );
    }
    return _withClient((client) async {
      final parameters = _timelineParameters(maxResults: 50)
        ..['query'] = normalized;
      final payload = await _getJson(
        client,
        Uri.https('api.x.com', '/2/tweets/search/recent', parameters),
        bearerToken,
      );
      return parseTimeline(payload);
    });
  }

  Future<AppResult<List<XPost>>> _withClient(
    Future<List<XPost>> Function(HttpClient client) action,
  ) async {
    final client = HttpClient()..connectionTimeout = AppConfig.networkTimeout;
    client.badCertificateCallback = (_, __, ___) => false;
    try {
      return AppSuccess<List<XPost>>(await action(client));
    } on TimeoutException catch (error) {
      return AppError<List<XPost>>(
        AppFailure('x_timeout', 'X did not respond in time.', cause: error),
      );
    } on XApiException catch (error) {
      return AppError<List<XPost>>(
        AppFailure(error.code, error.message, cause: error),
      );
    } catch (error) {
      _log.warning('X API request failed without credential details: $error');
      return AppError<List<XPost>>(
        AppFailure(
          'x_request_failed',
          'Could not load content from X.',
          cause: error,
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, String> _timelineParameters({
    required int maxResults,
  }) => <String, String>{
    'max_results': '$maxResults',
    'tweet.fields':
        'created_at,attachments,possibly_sensitive,author_id,public_metrics,lang',
    'expansions': 'author_id,attachments.media_keys',
    'user.fields': 'id,name,username,profile_image_url,verified',
    'media.fields':
        'media_key,type,url,preview_image_url,variants,width,height,alt_text,duration_ms',
  };

  static bool _isPostId(String value) =>
      value.isNotEmpty &&
      value.codeUnits.every((unit) => unit >= 48 && unit <= 57);

  Future<Map<String, Object?>> _getJson(
    HttpClient client,
    Uri uri,
    String token,
  ) async {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${token.trim()}',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'TwitchFreedom/${AppConfig.appVersion}',
    );
    request.followRedirects = false;
    final response = await request.close().timeout(AppConfig.networkTimeout);
    if (response.isRedirect) {
      throw const XApiException(
        'x_redirect_rejected',
        'X API redirected unexpectedly.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(AppConfig.networkTimeout)) {
      bytes.addAll(chunk);
      if (bytes.length > AppConfig.maxHttpBodyBytes) {
        throw const XApiException(
          'x_response_too_large',
          'X returned too much data.',
        );
      }
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const XApiException(
        'x_unauthorized',
        'X rejected the API token or access level.',
      );
    }
    if (response.statusCode == 429) {
      throw const XApiException(
        'x_rate_limited',
        'X rate limit reached. Try again later.',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw XApiException(
        'x_http_error',
        'X returned HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) throw const FormatException('Expected an object.');
    return Map<String, Object?>.from(decoded);
  }

  static List<XPost> parseTimeline(Map<String, Object?> payload) {
    final includes = payload['includes'];
    final mediaRows = includes is Map ? includes['media'] : null;
    final mediaByKey = <String, XMedia>{};
    final usersById = <String, Map<String, Object?>>{};
    final userRows = includes is Map ? includes['users'] : null;
    if (userRows is List) {
      for (final raw in userRows.whereType<Map<Object?, Object?>>()) {
        final user = Map<String, Object?>.from(raw);
        final id = user['id'] as String?;
        if (id != null) usersById[id] = user;
      }
    }
    if (mediaRows is List) {
      for (final raw in mediaRows.whereType<Map<Object?, Object?>>()) {
        final row = Map<String, Object?>.from(raw);
        final key = row['media_key'] as String?;
        if (key == null) continue;
        final variants = row['variants'];
        Map<Object?, Object?>? smooth;
        Map<Object?, Object?>? highest;
        if (variants is List) {
          final mp4 =
              variants
                  .whereType<Map<Object?, Object?>>()
                  .where(
                    (item) =>
                        item['content_type'] == 'video/mp4' &&
                        item['url'] is String,
                  )
                  .toList()
                ..sort(
                  (a, b) => ((a['bit_rate'] as num?) ?? 0).compareTo(
                    (b['bit_rate'] as num?) ?? 0,
                  ),
                );
          // X commonly offers 256k, 832k and 2176k variants. Prefer the
          // highest rendition at or below 1.2 Mbps for smooth inline playback;
          // the explicit encrypted download remains available separately.
          highest = mp4.lastOrNull;
          smooth =
              mp4.where((item) {
                final rate = (item['bit_rate'] as num?)?.toInt() ?? 0;
                return rate > 0 && rate <= 1200000;
              }).lastOrNull ??
              mp4.firstOrNull;
        }
        final type = (row['type'] as String?) ?? 'unknown';
        final direct = type == 'photo'
            ? row['url'] as String?
            : highest?['url'] as String?;
        final playback = type == 'photo'
            ? row['url'] as String?
            : smooth?['url'] as String?;
        final preview =
            row['preview_image_url'] as String? ?? row['url'] as String?;
        mediaByKey[key] = XMedia(
          key: key,
          type: type,
          previewUrl: preview == null ? null : Uri.tryParse(preview),
          downloadUrl: direct == null ? null : Uri.tryParse(direct),
          playbackUrl: playback == null ? null : Uri.tryParse(playback),
          contentType: type == 'photo' ? 'image/jpeg' : 'video/mp4',
          width: (row['width'] as num?)?.toInt(),
          height: (row['height'] as num?)?.toInt(),
        );
      }
    }
    final rows = payload['data'];
    if (rows is! List) return const <XPost>[];
    return rows
        .whereType<Map<Object?, Object?>>()
        .map((raw) {
          final row = Map<String, Object?>.from(raw);
          final attachments = row['attachments'];
          final keys = attachments is Map ? attachments['media_keys'] : null;
          final attached = keys is List
              ? keys
                    .whereType<String>()
                    .map((key) => mediaByKey[key])
                    .whereType<XMedia>()
                    .toList()
              : <XMedia>[];
          final authorId = (row['author_id'] as String?) ?? '';
          final author = usersById[authorId];
          final avatar = author?['profile_image_url'] as String?;
          return XPost(
            id: (row['id'] as String?) ?? '',
            text: (row['text'] as String?) ?? '',
            createdAt: DateTime.tryParse((row['created_at'] as String?) ?? ''),
            sensitive: (row['possibly_sensitive'] as bool?) ?? false,
            media: attached,
            authorId: authorId,
            authorName: (author?['name'] as String?) ?? '',
            authorUsername: (author?['username'] as String?) ?? '',
            authorAvatarUrl: avatar == null ? null : Uri.tryParse(avatar),
          );
        })
        .where((post) => post.id.isNotEmpty)
        .toList();
  }

  static List<XPost> parseHomeTimeline(
    Map<String, Object?> payload, {
    required String ownUserId,
  }) => parseTimeline(
    payload,
  ).where((post) => post.authorId != ownUserId).toList(growable: false);
}

final class XApiException implements Exception {
  const XApiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  T? get lastOrNull {
    if (isEmpty) return null;
    return last;
  }
}
