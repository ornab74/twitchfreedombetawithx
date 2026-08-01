import 'package:flutter/material.dart';

import '../core/models.dart';

@immutable
final class FreedomTokens extends ThemeExtension<FreedomTokens> {
  const FreedomTokens({
    required this.canvas,
    required this.panel,
    required this.panelElevated,
    required this.border,
    required this.glow,
    required this.good,
    required this.warning,
    required this.danger,
    required this.chatBackground,
  });

  final Color canvas;
  final Color panel;
  final Color panelElevated;
  final Color border;
  final Color glow;
  final Color good;
  final Color warning;
  final Color danger;
  final Color chatBackground;

  @override
  FreedomTokens copyWith({
    Color? canvas,
    Color? panel,
    Color? panelElevated,
    Color? border,
    Color? glow,
    Color? good,
    Color? warning,
    Color? danger,
    Color? chatBackground,
  }) => FreedomTokens(
    canvas: canvas ?? this.canvas,
    panel: panel ?? this.panel,
    panelElevated: panelElevated ?? this.panelElevated,
    border: border ?? this.border,
    glow: glow ?? this.glow,
    good: good ?? this.good,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    chatBackground: chatBackground ?? this.chatBackground,
  );

  @override
  FreedomTokens lerp(covariant FreedomTokens? other, double t) {
    if (other == null) return this;
    return FreedomTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panelElevated: Color.lerp(panelElevated, other.panelElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      good: Color.lerp(good, other.good, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      chatBackground: Color.lerp(chatBackground, other.chatBackground, t)!,
    );
  }
}

abstract final class FreedomTheme {
  static ThemeData fromProfile(ThemeProfile profile) {
    final definition = switch (profile) {
      ThemeProfile.auroraViolet => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF7C4DFF),
        secondary: const Color(0xFF00D9FF),
        canvas: const Color(0xFF050713),
        panel: const Color(0xD90C1021),
        elevated: const Color(0xEE12182C),
        border: const Color(0xFF27365C),
        glow: const Color(0xFF8C5BFF),
      ),
      ThemeProfile.obsidianGlass => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF3FA9FF),
        secondary: const Color(0xFF54F4CA),
        canvas: const Color(0xFF04070B),
        panel: const Color(0xDF0A111A),
        elevated: const Color(0xF0121C28),
        border: const Color(0xFF263849),
        glow: const Color(0xFF3FA9FF),
      ),
      ThemeProfile.solarGraphite => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFFFA94D),
        secondary: const Color(0xFFFFD166),
        canvas: const Color(0xFF090806),
        panel: const Color(0xE0151411),
        elevated: const Color(0xF0201D17),
        border: const Color(0xFF4B402E),
        glow: const Color(0xFFFFB55E),
      ),
      ThemeProfile.arcticSignal => _ThemeDefinition(
        brightness: Brightness.light,
        seed: const Color(0xFF376DFF),
        secondary: const Color(0xFF006C8F),
        canvas: const Color(0xFFF2F5FA),
        panel: const Color(0xEFFFFFFF),
        elevated: const Color(0xFFF8FAFF),
        border: const Color(0xFFC7D2E8),
        glow: const Color(0xFF376DFF),
      ),
      ThemeProfile.oledVoid => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF9A6CFF),
        secondary: const Color(0xFF00E2B8),
        canvas: Colors.black,
        panel: const Color(0xEE030306),
        elevated: const Color(0xFF090910),
        border: const Color(0xFF242438),
        glow: const Color(0xFF9A6CFF),
      ),
      ThemeProfile.highContrast => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFFFFF00),
        secondary: const Color(0xFF00FFFF),
        canvas: Colors.black,
        panel: const Color(0xFF050505),
        elevated: const Color(0xFF101010),
        border: Colors.white,
        glow: const Color(0xFFFFFF00),
      ),
      ThemeProfile.matrix => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF00FF41),
        secondary: const Color(0xFF8AFF80),
        canvas: const Color(0xFF000500),
        panel: const Color(0xEE031007),
        elevated: const Color(0xFF071A0C),
        border: const Color(0xFF166B2B),
        glow: const Color(0xFF00FF41),
      ),
      ThemeProfile.barbie => _ThemeDefinition(
        brightness: Brightness.light,
        seed: const Color(0xFFE5007D),
        secondary: const Color(0xFF8A2BE2),
        canvas: const Color(0xFFFFF0F8),
        panel: const Color(0xF9FFF8FC),
        elevated: const Color(0xFFFFE1F1),
        border: const Color(0xFFF2A4CE),
        glow: const Color(0xFFFF2FA0),
      ),
      ThemeProfile.halo2 => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF9DAF56),
        secondary: const Color(0xFFFFA31A),
        canvas: const Color(0xFF090C08),
        panel: const Color(0xEE151B12),
        elevated: const Color(0xFF222A1B),
        border: const Color(0xFF59643A),
        glow: const Color(0xFFFF9D24),
      ),
      ThemeProfile.synthwaveSunset => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFFF3CAC),
        secondary: const Color(0xFF2B86C5),
        canvas: const Color(0xFF10051C),
        panel: const Color(0xEE1C0B30),
        elevated: const Color(0xFF2B1245),
        border: const Color(0xFF673A87),
        glow: const Color(0xFFFF4FCB),
      ),
      ThemeProfile.oceanAbyss => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF00A8CC),
        secondary: const Color(0xFF63F5D2),
        canvas: const Color(0xFF020A12),
        panel: const Color(0xEE061522),
        elevated: const Color(0xFF0B2233),
        border: const Color(0xFF1D5067),
        glow: const Color(0xFF00D4FF),
      ),
      ThemeProfile.forestTerminal => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFF66BB6A),
        secondary: const Color(0xFFD4E157),
        canvas: const Color(0xFF071009),
        panel: const Color(0xEE101B12),
        elevated: const Color(0xFF19281B),
        border: const Color(0xFF3D6141),
        glow: const Color(0xFF7DDF82),
      ),
      ThemeProfile.crimsonProtocol => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFFF334F),
        secondary: const Color(0xFFFF9F43),
        canvas: const Color(0xFF0D0305),
        panel: const Color(0xEE1C090D),
        elevated: const Color(0xFF2B1016),
        border: const Color(0xFF6D2632),
        glow: const Color(0xFFFF405C),
      ),
      ThemeProfile.desertDusk => _ThemeDefinition(
        brightness: Brightness.light,
        seed: const Color(0xFFA4512C),
        secondary: const Color(0xFF6C5B9B),
        canvas: const Color(0xFFFFF4E6),
        panel: const Color(0xFAFFF9F0),
        elevated: const Color(0xFFF5DFC5),
        border: const Color(0xFFD4AF8C),
        glow: const Color(0xFFD66A3A),
      ),
      ThemeProfile.lunarIce => _ThemeDefinition(
        brightness: Brightness.light,
        seed: const Color(0xFF3977B8),
        secondary: const Color(0xFF6A5ACD),
        canvas: const Color(0xFFF4F9FF),
        panel: const Color(0xFAFFFFFF),
        elevated: const Color(0xFFE4F0FC),
        border: const Color(0xFFB2CBE4),
        glow: const Color(0xFF55A7E8),
      ),
      ThemeProfile.retroArcade => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFFFD600),
        secondary: const Color(0xFF00E5FF),
        canvas: const Color(0xFF090514),
        panel: const Color(0xEE160B28),
        elevated: const Color(0xFF24133B),
        border: const Color(0xFF67428B),
        glow: const Color(0xFFFFD600),
      ),
      ThemeProfile.royalAmethyst => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFB57BFF),
        secondary: const Color(0xFFFFD166),
        canvas: const Color(0xFF0B0712),
        panel: const Color(0xEE171020),
        elevated: const Color(0xFF241832),
        border: const Color(0xFF5B3E73),
        glow: const Color(0xFFC18CFF),
      ),
      ThemeProfile.copperSteampunk => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFCA7B42),
        secondary: const Color(0xFF6FB98F),
        canvas: const Color(0xFF100B08),
        panel: const Color(0xEE211711),
        elevated: const Color(0xFF302218),
        border: const Color(0xFF755039),
        glow: const Color(0xFFE69255),
      ),
      ThemeProfile.sakuraNight => _ThemeDefinition(
        brightness: Brightness.dark,
        seed: const Color(0xFFFF8FB8),
        secondary: const Color(0xFF8CA6FF),
        canvas: const Color(0xFF0D0911),
        panel: const Color(0xEE1B121F),
        elevated: const Color(0xFF291A2E),
        border: const Color(0xFF664268),
        glow: const Color(0xFFFF9EC5),
      ),
    };
    final colorScheme = ColorScheme.fromSeed(
      seedColor: definition.seed,
      brightness: definition.brightness,
      primary: definition.seed,
      secondary: definition.secondary,
      surface: definition.panel,
    );
    final textTheme = ThemeData(brightness: definition.brightness).textTheme
        .apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
          fontFamily: 'Inter',
        );
    return ThemeData(
      useMaterial3: true,
      brightness: definition.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: definition.canvas,
      canvasColor: definition.canvas,
      textTheme: textTheme,
      fontFamily: 'Inter',
      visualDensity: VisualDensity.standard,
      // InkSparkle is costly on software-rendered desktop surfaces and can
      // delay presentation of pointer/text invalidations. Ripple is cheaper
      // and reliable across GTK, Windows, and software rendering.
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[
        FreedomTokens(
          canvas: definition.canvas,
          panel: definition.panel,
          panelElevated: definition.elevated,
          border: definition.border,
          glow: definition.glow,
          good: const Color(0xFF53E3B5),
          warning: const Color(0xFFFFC857),
          danger: const Color(0xFFFF5E7C),
          chatBackground: Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.025),
            definition.panel,
          ),
        ),
      ],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: definition.elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: definition.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: definition.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: definition.glow, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          side: BorderSide(color: definition.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: definition.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(color: definition.border),
        ),
      ),
      dividerColor: definition.border,
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          definition.glow.withValues(alpha: 0.45),
        ),
        radius: const Radius.circular(12),
        thickness: const WidgetStatePropertyAll(6),
      ),
    );
  }
}

final class _ThemeDefinition {
  const _ThemeDefinition({
    required this.brightness,
    required this.seed,
    required this.secondary,
    required this.canvas,
    required this.panel,
    required this.elevated,
    required this.border,
    required this.glow,
  });
  final Brightness brightness;
  final Color seed;
  final Color secondary;
  final Color canvas;
  final Color panel;
  final Color elevated;
  final Color border;
  final Color glow;
}

FreedomTokens freedomTokens(BuildContext context) =>
    Theme.of(context).extension<FreedomTokens>()!;
