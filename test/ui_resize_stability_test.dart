import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/state/app_controller.dart';
import 'package:twitch_freedom_ultra/core/models.dart';
import 'package:twitch_freedom_ultra/ui/home_screen.dart';
import 'package:twitch_freedom_ultra/ui/theme.dart';
import 'package:twitch_freedom_ultra/ui/widgets/ai_companion_panel.dart';

void main() {
  testWidgets('desktop and compact layouts survive repeated resize', (
    WidgetTester tester,
  ) async {
    final controller = AppController();
    addTearDown(controller.scheduler.close);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 930);
    await tester.pumpWidget(
      MaterialApp(
        theme: FreedomTheme.fromProfile(controller.preferences.theme),
        home: HomeScreen(controller: controller),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1920, 1090);
    await tester.pump();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1500, 800);
    await tester.pump();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1000, 650);
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Linux window managers can briefly report these dimensions while the
    // native surface is being minimized, maximized, or moved across displays.
    tester.view.physicalSize = const Size(438, 69);
    await tester.pump();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(438, 300);
    await tester.pump();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(300, 650);
    await tester.pump();
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1500, 930);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await controller.scheduler.close();
  });

  testWidgets('enabled AI panel fits the short desktop allocation', (
    WidgetTester tester,
  ) async {
    final controller = AppController();
    addTearDown(controller.scheduler.close);
    try {
      await controller.updatePreferences(
        controller.preferences.copyWith(
          ai: const AiFeatureSettings(
            enabled: true,
            speechContext: true,
            technicalCompanion: true,
          ),
        ),
      );
    } catch (_) {
      // This layout-only test intentionally has no unlocked persistence vault.
    }
    expect(controller.preferences.ai.enabled, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: FreedomTheme.fromProfile(controller.preferences.theme),
        home: Center(
          child: SizedBox(
            width: 968.8,
            height: 218.4,
            child: AiCompanionPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Local AI Companion'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.scheduler.close();
  });

  testWidgets('desktop Explore button opens the discovery sheet', (
    WidgetTester tester,
  ) async {
    final controller = AppController();
    addTearDown(controller.scheduler.close);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 930);

    await tester.pumpWidget(
      MaterialApp(
        theme: FreedomTheme.fromProfile(controller.preferences.theme),
        home: HomeScreen(controller: controller),
      ),
    );
    await tester.tap(find.byTooltip('Explore streams'));
    await tester.pumpAndSettle();

    expect(find.text('Explore live text metadata'), findsOneWidget);
    expect(find.text('Search live channels or topics'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.scheduler.close();
  });
}
