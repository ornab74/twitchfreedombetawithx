import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_gemma/core/domain/platform_types.dart';
import 'package:flutter_gemma_speech/src/litert/litert_speech_recognizer.dart';
import 'package:flutter_gemma_speech/src/model/stt_model_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'installed Moonshine performs native inference on a synthetic phrase',
    () async {
      if (!Platform.isLinux) return;
      final home = Platform.environment['HOME'];
      if (home == null) return;
      final directory = Directory(
        '$home/.local/share/com.ornab74.twitchfreedom/flutter_gemma',
      );
      final model = File('${directory.path}/moonshine_tiny_5s_f32.tflite');
      final tokenizer = File('${directory.path}/tokenizer.json');
      if (!model.existsSync() || !tokenizer.existsSync()) return;

      final pcm = File(
        '${Directory.systemTemp.path}/twitch_freedom_stt_smoke.s16le',
      );
      final generated = await Process.run('ffmpeg', <String>[
        '-nostdin',
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        "flite=text='speech chunk test':voice=slt",
        '-t',
        '5',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-f',
        's16le',
        '-y',
        pcm.path,
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr.toString());

      // flutter_tester does not inherit the application bundle's $ORIGIN/lib
      // RUNPATH. Preload the same generated native asset by absolute path; the
      // packaged application resolves this automatically from bundle/lib.
      DynamicLibrary.open(
        '${Directory.current.path}/.dart_tool/lib/libLiteRt.so',
      );

      final recognizer = await LiteRtSpeechRecognizer.create(
        profile: const SttModelProfile.moonshine(),
        modelPath: model.path,
        tokenizerPath: tokenizer.path,
        preferredBackend: PreferredBackend.cpu,
      );
      try {
        final transcript = await recognizer.transcribe(
          Uint8List.fromList(await pcm.readAsBytes()),
        );
        expect(transcript.trim(), isNotEmpty);
        // Visible under `flutter test --reporter expanded` for manual audits.
        // ignore: avoid_print
        print('Moonshine native smoke transcript: ${transcript.trim()}');
      } finally {
        await recognizer.close();
        if (pcm.existsSync()) pcm.deleteSync();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
