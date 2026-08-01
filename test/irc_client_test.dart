import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/chat/irc_client.dart';

void main() {
  group('validateChatDraft', () {
    test('sanitizes framing and bidi controls before sending', () {
      final result = validateChatDraft('  hello\r\nworld\u202E  ');

      expect(result.valid, isTrue);
      expect(result.text, isNot(contains('\r')));
      expect(result.text, isNot(contains('\n')));
      expect(result.text, isNot(contains('\u202E')));
      expect(result.characterCount, result.text.runes.length);
    });

    test('counts Unicode scalar values instead of UTF-16 code units', () {
      final valid = validateChatDraft(List<String>.filled(500, '🙂').join());
      final tooLong = validateChatDraft(List<String>.filled(501, '🙂').join());

      expect(valid.valid, isTrue);
      expect(valid.characterCount, 500);
      expect(tooLong.valid, isFalse);
      expect(tooLong.characterCount, 501);
    });

    test('rejects an empty draft', () {
      expect(validateChatDraft(' \n ').valid, isFalse);
    });
  });

  group('parsePrivmsg', () {
    test('parses Twitch tags, timestamp, moderator, and own login', () {
      final message = parsePrivmsg(
        '@badges=moderator/1;display-name=MyLogin;id=message-1;'
            'tmi-sent-ts=1720000000000 '
            ':mylogin!mylogin@mylogin.tmi.twitch.tv '
            'PRIVMSG #testchannel :hello chat',
        'testchannel',
        'mylogin',
      );

      expect(message, isNotNull);
      expect(message!.id, 'message-1');
      expect(message.channel, 'testchannel');
      expect(message.user, 'MyLogin');
      expect(message.text, 'hello chat');
      expect(message.isOwn, isTrue);
      expect(message.isModerator, isTrue);
      expect(
        message.timestamp.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1720000000000, isUtc: true),
      );
    });

    test('ignores a message for another room', () {
      expect(
        parsePrivmsg(
          ':viewer!viewer@viewer.tmi.twitch.tv '
              'PRIVMSG #otherchannel :hello',
          'testchannel',
          'mylogin',
        ),
        isNull,
      );
    });
  });
}
