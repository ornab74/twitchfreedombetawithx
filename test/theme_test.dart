import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_freedom_ultra/core/models.dart';
import 'package:twitch_freedom_ultra/ui/theme.dart';

void main() {
  test('all theme profiles produce distinct token sets', () {
    expect(ThemeProfile.values, hasLength(19));
    final primaryColors = <Color>{};
    for (final profile in ThemeProfile.values) {
      final theme = FreedomTheme.fromProfile(profile);
      expect(theme.extension<FreedomTokens>(), isNotNull);
      expect(theme.useMaterial3, isTrue);
      primaryColors.add(theme.colorScheme.primary);
    }
    expect(primaryColors, hasLength(ThemeProfile.values.length));
  });
}
