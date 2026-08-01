import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';

import 'state/app_controller.dart';
import 'ui/app.dart';

Future<void> main() async {
  // The Dart/Flutter MCP server can drive this app only when it is launched in
  // debug mode with --dart-define=ENABLE_FLUTTER_DRIVER=true. Keeping both
  // gates compile-time constant prevents the driver service from being exposed
  // by profile or release builds.
  if (kDebugMode && const bool.fromEnvironment('ENABLE_FLUTTER_DRIVER')) {
    enableFlutterDriverExtension();
  }

  if (Platform.isLinux) {
    final renderer =
        Platform.environment['TWITCH_FREEDOM_RENDERER'] ?? 'platform-default';
    final media =
        Platform.environment['TWITCH_FREEDOM_MEDIA_RENDERER'] ?? 'auto';
    final ai = Platform.environment['TWITCH_FREEDOM_AI_RENDERER'] ?? 'auto';
    final gpu =
        Platform.environment['TWITCH_FREEDOM_GPU_AVAILABLE'] ?? 'unknown';
    final gl =
        Platform.environment['TWITCH_FREEDOM_OPENGL_AVAILABLE'] ?? 'unknown';
    final hwdec =
        Platform.environment['TWITCH_FREEDOM_HWDEC_AVAILABLE'] ?? 'unknown';
    final display =
        Platform.environment['TWITCH_FREEDOM_DISPLAY_BACKEND'] ??
        Platform.environment['GDK_BACKEND'] ??
        'platform-default';
    stdout.writeln(
      '[TwitchFreedom][Boot] Linux policy: ui=$renderer, media=$media, ai=$ai; '
      'gpu=$gpu, opengl=$gl, hwdec=$hwdec, display=$display. '
      'Override only when needed with TWITCH_FREEDOM_SOFTWARE=1 or '
      'TWITCH_FREEDOM_ACCELERATED_UI=1.',
    );
  }
  WidgetsFlutterBinding.ensureInitialized();

  runApp(TwitchFreedomApp(controller: AppController()));
}
