import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/core/models.dart';
import 'package:twitch_freedom_ultra/state/app_controller.dart';
import 'package:twitch_freedom_ultra/ui/theme.dart';
import 'package:twitch_freedom_ultra/ui/x_mode_screen.dart';

void main() {
  testWidgets('X mode fits desktop and compact surfaces', (tester) async {
    final controller = AppController();
    addTearDown(controller.scheduler.close);

    for (final size in <Size>[const Size(1200, 800), const Size(420, 760)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: FreedomTheme.fromProfile(ThemeProfile.obsidianGlass),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: XModeScreen(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final label in <String>[
        'Search',
        'Account',
        'Follows',
        'Content Lab',
        'Carousel',
        'Vault',
        'X Settings',
        'My feed',
      ]) {
        await tester.ensureVisible(find.text(label).last);
        await tester.tap(find.text(label).last);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$label at $size');
        if (label == 'X Settings') {
          expect(
            find.byKey(const ValueKey<String>('x-handle')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('x-oauth-client-id')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey<String>('x-oauth-client-secret')),
            findsOneWidget,
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.scheduler.close();
  });
}
