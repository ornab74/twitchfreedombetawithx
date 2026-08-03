import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/core/secure_log.dart';

void main() {
  test('redacts bearer, oauth, signature, and token values', () {
    final log = SecureLog();
    log.info(
      'Authorization: Bearer topsecret oauth:abc123 sig=signature&token=playlist',
    );
    final text = log.entries.single.message;
    expect(text, isNot(contains('topsecret')));
    expect(text, isNot(contains('abc123')));
    expect(text, isNot(contains('signature')));
    expect(text, isNot(contains('playlist')));
    expect(text, contains('[REDACTED]'));
  });

  test('redacts Windows-vault and OAuth JSON naming variants', () {
    final log = SecureLog();
    log.warning(
      'Basic Y2xpZW50OnNlY3JldA== '
      '{"clientSecret":"client-value","accessToken":"access-value",'
      '"refresh_token":"refresh-value","device_code":"device-value",'
      '"codeVerifier":"verifier-value"}',
    );
    final text = log.entries.single.message;
    for (final secret in <String>[
      'Y2xpZW50OnNlY3JldA==',
      'client-value',
      'access-value',
      'refresh-value',
      'device-value',
      'verifier-value',
    ]) {
      expect(text, isNot(contains(secret)));
    }
    expect('[REDACTED]'.allMatches(text), hasLength(6));
  });
}
