import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/x/x_oauth.dart';

void main() {
  test('X OAuth uses a fixed IPv4 loopback callback', () {
    expect(XOAuthService.callbackUri.scheme, 'http');
    expect(XOAuthService.callbackUri.host, '127.0.0.1');
    expect(XOAuthService.callbackUri.port, XOAuthService.callbackPort);
    expect(XOAuthService.callbackUri.path, '/x/oauth/callback');
    expect(XOAuthService.callbackUri.hasQuery, isFalse);
  });
}
