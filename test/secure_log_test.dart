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
}
