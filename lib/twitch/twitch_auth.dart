import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import '../security/vault.dart';

final class TwitchAppCredentials {
  const TwitchAppCredentials({
    required this.clientId,
    required this.clientSecret,
  });
  final String clientId;
  final String clientSecret;

  Map<String, Object?> toJson() => <String, Object?>{
    'clientId': clientId,
    'clientSecret': clientSecret,
  };
  static TwitchAppCredentials fromJson(Map<String, Object?> json) =>
      TwitchAppCredentials(
        clientId: json['clientId']! as String,
        clientSecret: json['clientSecret']! as String,
      );
}

final class TwitchTokenState {
  const TwitchTokenState({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.scopes,
    required this.login,
    required this.userId,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final List<String> scopes;
  final String login;
  final String userId;

  bool get needsRefresh =>
      expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 2)));

  Map<String, Object?> toJson() => <String, Object?>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'scopes': scopes,
    'login': login,
    'userId': userId,
  };

  static TwitchTokenState fromJson(Map<String, Object?> json) =>
      TwitchTokenState(
        accessToken: json['accessToken']! as String,
        refreshToken: (json['refreshToken'] as String?) ?? '',
        expiresAt: DateTime.parse(json['expiresAt']! as String),
        scopes: List<String>.from(
          (json['scopes'] as List<Object?>?) ?? const <Object?>[],
        ),
        login: (json['login'] as String?) ?? '',
        userId: (json['userId'] as String?) ?? '',
      );
}

final class DeviceAuthorization {
  const DeviceAuthorization({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final int expiresIn;
  final int interval;
}

final class TwitchAuthService {
  TwitchAuthService({
    required VaultRepository vault,
    required SecureLog log,
    http.Client? client,
  }) : _vault = vault,
       _log = log,
       _client = client ?? http.Client();

  static const String _credentialsType = 'secret';
  static const String _credentialsId = 'twitch_app_credentials';
  static const String _tokenId = 'twitch_token_state';
  static const List<String> requiredScopes = <String>[
    'chat:read',
    'user:write:chat',
    'user:read:follows',
  ];

  final VaultRepository _vault;
  final SecureLog _log;
  final http.Client _client;

  Future<void> saveCredentials(TwitchAppCredentials value) async {
    if (!_validClientId(value.clientId) || value.clientSecret.length < 12) {
      throw const AppFailure(
        'invalid_twitch_credentials',
        'Enter a valid Twitch Client ID and Client Secret.',
      );
    }
    await _vault.putJson(_credentialsType, _credentialsId, value.toJson());
  }

  Future<TwitchAppCredentials?> credentials() async {
    final json = await _vault.getJson(_credentialsType, _credentialsId);
    return json == null ? null : TwitchAppCredentials.fromJson(json);
  }

  Future<TwitchTokenState?> tokenState() async {
    final json = await _vault.getJson(_credentialsType, _tokenId);
    return json == null ? null : TwitchTokenState.fromJson(json);
  }

  Future<AppResult<DeviceAuthorization>> beginDeviceAuthorization() async {
    try {
      final app = await credentials();
      if (app == null) {
        return const AppError<DeviceAuthorization>(
          AppFailure(
            'credentials_missing',
            'Save a Twitch application Client ID and Client Secret first.',
          ),
        );
      }
      final response = await _client
          .post(
            AppConfig.twitchDevice,
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: <String, String>{
              'client_id': app.clientId,
              'scopes': requiredScopes.join(' '),
            },
          )
          .timeout(AppConfig.networkTimeout);
      final body = _decodeObject(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppFailure(
          'device_flow_failed',
          _safeApiMessage(body, response.statusCode),
        );
      }
      return AppSuccess<DeviceAuthorization>(
        DeviceAuthorization(
          deviceCode: body['device_code']! as String,
          userCode: body['user_code']! as String,
          verificationUri: Uri.parse(body['verification_uri']! as String),
          expiresIn: (body['expires_in'] as num?)?.toInt() ?? 600,
          interval: (body['interval'] as num?)?.toInt() ?? 5,
        ),
      );
    } catch (error) {
      return AppError<DeviceAuthorization>(
        AppFailure(
          'device_flow_failed',
          'Could not start Twitch device authorization.',
          cause: error,
          retryable: true,
        ),
      );
    }
  }

  Future<AppResult<TwitchTokenState>> pollDeviceAuthorization(
    DeviceAuthorization authorization, {
    required bool Function() cancelled,
    void Function(String status)? onStatus,
  }) async {
    final app = await credentials();
    if (app == null)
      return const AppError<TwitchTokenState>(
        AppFailure('credentials_missing', 'Twitch credentials are missing.'),
      );
    var interval = authorization.interval;
    final deadline = DateTime.now().add(
      Duration(seconds: authorization.expiresIn),
    );
    while (DateTime.now().isBefore(deadline) && !cancelled()) {
      await Future<void>.delayed(Duration(seconds: interval));
      final response = await _client.post(
        AppConfig.twitchToken,
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: <String, String>{
          'client_id': app.clientId,
          'client_secret': app.clientSecret,
          'device_code': authorization.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
      final body = _decodeObject(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final saved = await _saveTokenResponse(body);
          return AppSuccess<TwitchTokenState>(saved);
        } catch (error) {
          return AppError<TwitchTokenState>(
            AppFailure(
              'token_validation_failed',
              'Twitch issued a token that could not be validated.',
              cause: error,
            ),
          );
        }
      }
      final code =
          (body['message'] as String?) ?? (body['error'] as String?) ?? '';
      if (code.contains('authorization_pending')) {
        onStatus?.call('Waiting for Twitch approval…');
        continue;
      }
      if (code.contains('slow_down')) {
        interval += 2;
        onStatus?.call('Twitch requested slower authorization polling.');
        continue;
      }
      if (code.contains('expired_token')) break;
      return AppError<TwitchTokenState>(
        AppFailure(
          'authorization_failed',
          _safeApiMessage(body, response.statusCode),
        ),
      );
    }
    return const AppError<TwitchTokenState>(
      AppFailure(
        'authorization_expired',
        'The Twitch authorization code expired or was cancelled.',
      ),
    );
  }

  Future<AppResult<String>> validAccessToken() async {
    try {
      var token = await tokenState();
      if (token == null)
        return const AppError<String>(
          AppFailure('not_authorized', 'Authorize Twitch in Settings first.'),
        );
      if (!token.needsRefresh) return AppSuccess<String>(token.accessToken);
      token = await _refresh(token);
      return AppSuccess<String>(token.accessToken);
    } catch (error) {
      return AppError<String>(
        AppFailure(
          'token_refresh_failed',
          'Could not refresh the Twitch token.',
          cause: error,
          retryable: true,
        ),
      );
    }
  }

  Future<TwitchTokenState> _refresh(TwitchTokenState current) async {
    final app = await credentials();
    if (app == null || current.refreshToken.isEmpty)
      throw StateError('Refresh credentials are incomplete.');
    final response = await _client.post(
      AppConfig.twitchToken,
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'client_id': app.clientId,
        'client_secret': app.clientSecret,
        'grant_type': 'refresh_token',
        'refresh_token': current.refreshToken,
      },
    );
    final body = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppFailure(
        'token_refresh_failed',
        _safeApiMessage(body, response.statusCode),
      );
    }
    return _saveTokenResponse(body, prior: current);
  }

  Future<TwitchTokenState> _saveTokenResponse(
    Map<String, Object?> body, {
    TwitchTokenState? prior,
  }) async {
    final accessToken = body['access_token']! as String;
    final validation = await validate(accessToken);
    final expires = (body['expires_in'] as num?)?.toInt() ?? 3600;
    final token = TwitchTokenState(
      accessToken: accessToken,
      refreshToken:
          (body['refresh_token'] as String?) ?? prior?.refreshToken ?? '',
      expiresAt: DateTime.now().add(Duration(seconds: expires)),
      scopes: List<String>.from(
        (validation['scopes'] as List<Object?>?) ??
            (body['scope'] as List<Object?>?) ??
            const <Object?>[],
      ),
      login: (validation['login'] as String?) ?? '',
      userId: (validation['user_id'] as String?) ?? '',
    );
    await _vault.putJson(_credentialsType, _tokenId, token.toJson());
    _log.info('Saved authenticated Twitch token state for ${token.login}.');
    return token;
  }

  Future<Map<String, Object?>> validate(String accessToken) async {
    final response = await _client.get(
      AppConfig.twitchValidate,
      headers: <String, String>{'Authorization': 'OAuth $accessToken'},
    );
    final body = _decodeObject(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppFailure(
        'token_invalid',
        _safeApiMessage(body, response.statusCode),
      );
    }
    return body;
  }

  Future<void> clearAuthorization() async {
    await _vault.delete(_credentialsType, _tokenId);
  }

  void dispose() => _client.close();

  bool _validClientId(String value) =>
      RegExp(r'^[A-Za-z0-9]{10,80}$').hasMatch(value);

  Map<String, Object?> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<Object?, Object?>)
      throw const FormatException('Expected JSON object.');
    return Map<String, Object?>.from(decoded);
  }

  String _safeApiMessage(Map<String, Object?> body, int status) {
    final message =
        ((body['message'] as String?) ??
                (body['error_description'] as String?) ??
                (body['error'] as String?) ??
                'Twitch request failed')
            .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
            .trim();
    return 'HTTP $status: ${message.length > 300 ? message.substring(0, 300) : message}';
  }
}
