import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/ui/app.dart';

void main() {
  test('application root remains available to generated platforms', () {
    // Keeping a project-owned widget_test.dart prevents `flutter create` in CI
    // from generating Flutter's counter-app template, which references MyApp.
    expect(TwitchFreedomApp, isNotNull);
  });
}
