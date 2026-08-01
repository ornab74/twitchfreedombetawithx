import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/core/result.dart';
import 'package:twitch_freedom_ultra/twitch/helix.dart';

void main() {
  test('accepts an affirmative Twitch chat-send receipt', () {
    final receipt = decodeChatSendReceipt(
      '{"data":[{"message_id":"sent-123","is_sent":true}]}',
    );

    expect(receipt.messageId, 'sent-123');
  });

  test('rejects HTTP-success payloads Twitch marked as dropped', () {
    expect(
      () => decodeChatSendReceipt(
        '{"data":[{"message_id":"","is_sent":false,'
        '"drop_reason":{"code":"msg_duplicate",'
        '"message":"That message is not unique."}}]}',
      ),
      throwsA(
        isA<AppFailure>().having(
          (AppFailure value) => value.message,
          'message',
          'That message is not unique.',
        ),
      ),
    );
  });

  test('rejects a malformed or missing receipt', () {
    expect(() => decodeChatSendReceipt('{"data":[]}'), throwsFormatException);
  });
}
