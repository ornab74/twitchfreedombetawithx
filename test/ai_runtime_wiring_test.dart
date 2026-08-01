import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/ai/agent_orchestrator.dart';
import 'package:twitch_freedom_ultra/ai/speech_context.dart';

void main() {
  group('Moonshine PCM chunk preparation', () {
    test('pads a short aligned chunk to the fixed five-second window', () {
      final input = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final output = prepareMoonshinePcmWindow(input);

      expect(output.length, moonshineWindowBytes);
      expect(output.sublist(0, 4), input);
      expect(output[4], 0);
    });

    test('drops an incomplete sample and trims oversized chunks', () {
      final odd = prepareMoonshinePcmWindow(Uint8List.fromList(<int>[1, 2, 3]));
      expect(odd.sublist(0, 4), <int>[1, 2, 0, 0]);

      final oversized = Uint8List(moonshineWindowBytes + 20);
      oversized.fillRange(0, oversized.length, 7);
      final trimmed = prepareMoonshinePcmWindow(oversized);
      expect(trimmed.length, moonshineWindowBytes);
      expect(trimmed.last, 7);
    });
  });

  group('rolling transcript chunks', () {
    test('deduplicates adjacent overlapping words', () {
      expect(
        mergeTranscriptChunks(
          'the quick brown fox jumps over',
          'fox jumps over the stream',
        ),
        'the quick brown fox jumps over the stream',
      );
    });

    test('retains distinct chunks and enforces the context bound', () {
      expect(
        mergeTranscriptChunks('hello world', 'new topic'),
        'hello world new topic',
      );
      expect(mergeTranscriptChunks('12345', '67890', limit: 7), '5 67890');
    });
  });
}
