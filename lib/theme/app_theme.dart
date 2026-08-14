import 'package:flutter/material.dart';

/// The three looks the app ships with.
///
/// A theme is only ever colour, type and line weight. What arranges the
/// information is [AppLayout], and there are deliberately fewer of those than
/// there are themes — see the note on [AppLayout].
enum AppTheme {
  /// Material, as the app has always looked.
  modern,

  /// Parchment and ink: warm paper, hairline rules, one oxide red.
  klaf,

  /// The same language after dark: warm charcoal, brass.
  layla;

  String get label => switch (this) {
        AppTheme.modern => 'מודרני',
        AppTheme.klaf => 'קלף',
        AppTheme.layla => 'לילה',
      };

  String get description => switch (this) {
        AppTheme.modern => 'כרטיסים, צבע, מוד כהה לפי המערכת',
        AppTheme.klaf => 'נייר חם, קווי שרטוט, בלי כרטיסים',
        AppTheme.layla => 'פחם ופליז, לכתיבה בלילה',
      };

  static AppTheme fromName(String? name) =>
      AppTheme.values.firstWhere((t) => t.name == name,
          orElse: () => AppTheme.modern);
}

/// How a screen arranges its information.
///
/// There are two, not three, and that is the point. A theme costs one table of
/// colours; a layout costs a widget tree per screen, and every feature added
/// later has to be built once per layout. [AppTheme.klaf] and [AppTheme.layla]
/// are the same design language at two light levels, so they share
/// [AppLayout.rules] — which keeps the ongoing cost of a third look at almost
/// nothing.
enum AppLayout {
  /// Raised cards on a tinted page, filled progress bars, chips.
  cards,

  /// No cards and no shadows. Hairline rules separate content the way ruling
  /// separates the columns of a page.
  rules,
}

/// Everything the two layouts need that Material's own theme does not carry.
@immutable
class SoferTokens extends ThemeExtension<SoferTokens> {
  final AppLayout layout;

  /// Page background.
  final Color paper;

  /// A raised surface in [AppLayout.cards]; the same as [paper] in
  /// [AppLayout.rules], which has no raised surfaces at all.
  final Color panel;

  /// Hairline between rows inside one area.
  final Color rule;

  /// Heavier line between areas.
  final Color ruleStrong;

  final Color ink;
  final Color inkMuted;
  final Color inkFaint;

  /// The single accent. It marks three things and nothing else: the timer is
  /// running, the hourly rate, and what has been completed.
  final Color accent;

  /// Destructive and error states.
  ///
  /// A separate token rather than plain red, because in the parchment theme the
  /// accent is itself an oxide red — a delete button in the same hue would read
  /// as decoration instead of as a warning.
  final Color danger;

  /// A figure that is better than expected: profit, a goal met.
  final Color positive;

  /// Something that needs attention but is not an error — a missing setting, an
  /// estimate resting on an assumption.
  final Color caution;

  /// Numbers and titles.
  final String numeralFamily;

  /// Labels and controls.
  final String labelFamily;

  final double panelRadius;

  const SoferTokens({
    required this.layout,
    required this.paper,
    required this.panel,
    required this.rule,
    required this.ruleStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.accent,
    required this.danger,
    required this.positive,
    required this.caution,
    required this.numeralFamily,
    required this.labelFamily,
    required this.panelRadius,
  });

  bool get isRules => layout == AppLayout.rules;
  bool get isCards => layout == AppLayout.cards;

  /// Reads the tokens for the current theme. Safe to call from any widget below
  /// the app's [MaterialApp].
  static SoferTokens of(BuildContext context) =>
      Theme.of(context).extension<SoferTokens>() ?? _fallback;

  static const SoferTokens _fallback = SoferTokens(
    layout: AppLayout.cards,
    paper: Color(0xFFFDF7FF),
    panel: Colors.white,
    rule: Color(0xFFE0DAE6),
    ruleStrong: Color(0xFFBDB4C6),
    ink: Color(0xFF1D1B20),
    inkMuted: Color(0xFF625B71),
    inkFaint: Color(0xFF938F99),
    accent: Colors.deepPurple,
    danger: Color(0xFFB3261E),
    positive: Color(0xFF2E6B4F),
    caution: Color(0xFF8A5300),
    numeralFamily: 'Heebo',
    labelFamily: 'Heebo',
    panelRadius: 12,
  );

  @override
  SoferTokens copyWith({
    AppLayout? layout,
    Color? paper,
    Color? panel,
    Color? rule,
    Color? ruleStrong,
    Color? ink,
    Color? inkMuted,
    Color? inkFaint,
    Color? accent,
    Color? danger,
    Color? positive,
    Color? caution,
    String? numeralFamily,
    String? labelFamily,
    double? panelRadius,
  }) =>
      SoferTokens(
        layout: layout ?? this.layout,
        paper: paper ?? this.paper,
        panel: panel ?? this.panel,
        rule: rule ?? this.rule,
        ruleStrong: ruleStrong ?? this.ruleStrong,
        ink: ink ?? this.ink,
        inkMuted: inkMuted ?? this.inkMuted,
        inkFaint: inkFaint ?? this.inkFaint,
        accent: accent ?? this.accent,
        danger: danger ?? this.danger,
        positive: positive ?? this.positive,
        caution: caution ?? this.caution,
        numeralFamily: numeralFamily ?? this.numeralFamily,
        labelFamily: labelFamily ?? this.labelFamily,
        panelRadius: panelRadius ?? this.panelRadius,
      );

  @override
  SoferTokens lerp(ThemeExtension<SoferTokens>? other, double t) {
    if (other is! SoferTokens) return this;
    return SoferTokens(
      // Layout and fonts cannot be interpolated — they snap at the halfway
      // point so a theme change never renders a half-built tree.
      layout: t < 0.5 ? layout : other.layout,
      numeralFamily: t < 0.5 ? numeralFamily : other.numeralFamily,
      labelFamily: t < 0.5 ? labelFamily : other.labelFamily,
      panelRadius: t < 0.5 ? panelRadius : other.panelRadius,
      paper: Color.lerp(paper, other.paper, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      ruleStrong: Color.lerp(ruleStrong, other.ruleStrong, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      positive: Color.lerp(positive, other.positive, t)!,
      caution: Color.lerp(caution, other.caution, t)!,
    );
  }
}

/// Builds the [ThemeData] for each look.
class AppThemeBuilder {
  const AppThemeBuilder._();

  static const String _serif = 'FrankRuhlLibre';
  static const String _sans = 'Heebo';

  static ThemeData build(AppTheme theme, {Brightness system = Brightness.light}) =>
      switch (theme) {
        AppTheme.modern => _modern(system),
        AppTheme.klaf => _klaf(),
        AppTheme.layla => _layla(),
      };

  // --- Modern: Material, unchanged in character, now with a dark mode. ---

  static ThemeData _modern(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: brightness,
    );
    final dark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _sans,
      scaffoldBackgroundColor: dark ? scheme.surface : const Color(0xFFFDF7FF),
      extensions: [
        SoferTokens(
          layout: AppLayout.cards,
          paper: dark ? scheme.surface : const Color(0xFFFDF7FF),
          panel: dark ? scheme.surfaceContainerHigh : Colors.white,
          rule: scheme.outlineVariant,
          ruleStrong: scheme.outline,
          ink: scheme.onSurface,
          inkMuted: scheme.onSurfaceVariant,
          inkFaint: scheme.outline,
          accent: scheme.primary,
          danger: scheme.error,
          positive: dark ? const Color(0xFF7FC4A0) : const Color(0xFF2E6B4F),
          caution: dark ? const Color(0xFFE0B65C) : const Color(0xFF8A5300),
          numeralFamily: _sans,
          labelFamily: _sans,
          panelRadius: 12,
        ),
      ],
    );
  }

  // --- Klaf: parchment and ink. ---

  static const Color _kPaper = Color(0xFFF2EADB);
  static const Color _kRule = Color(0xFFCFBFA3);
  static const Color _kInk = Color(0xFF241C12);
  static const Color _kMuted = Color(0xFF6E5B44);
  static const Color _kFaint = Color(0xFFA08E72);
  static const Color _kAccent = Color(0xFF8C2E1F);

  static ThemeData _klaf() => _ruled(
        brightness: Brightness.light,
        paper: _kPaper,
        rule: _kRule,
        ruleStrong: _kInk,
        ink: _kInk,
        inkMuted: _kMuted,
        inkFaint: _kFaint,
        accent: _kAccent,
        danger: const Color(0xFF7A1E10),
        positive: const Color(0xFF3E6B4A),
        caution: const Color(0xFF9C5A16),
      );

  // --- Layla: the same language after dark. ---

  static const Color _nPaper = Color(0xFF14130E);
  static const Color _nRule = Color(0xFF2E2B21);
  static const Color _nRuleStrong = Color(0xFF4A4636);
  static const Color _nInk = Color(0xFFEDE6D6);
  static const Color _nMuted = Color(0xFF8C8471);
  static const Color _nFaint = Color(0xFF5E5849);
  static const Color _nAccent = Color(0xFFC99B3F);

  static ThemeData _layla() => _ruled(
        brightness: Brightness.dark,
        paper: _nPaper,
        rule: _nRule,
        ruleStrong: _nRuleStrong,
        ink: _nInk,
        inkMuted: _nMuted,
        inkFaint: _nFaint,
        accent: _nAccent,
        danger: const Color(0xFFD4643C),
        positive: const Color(0xFF8FB08A),
        caution: const Color(0xFFD9B36A),
      );

  /// Shared construction for the two ruled themes: identical in every respect
  /// except the palette, which is what makes them one design language.
  static ThemeData _ruled({
    required Brightness brightness,
    required Color paper,
    required Color rule,
    required Color ruleStrong,
    required Color ink,
    required Color inkMuted,
    required Color inkFaint,
    required Color accent,
    required Color danger,
    required Color positive,
    required Color caution,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: paper,
      secondary: ink,
      onSecondary: paper,
      error: accent,
      onError: paper,
      surface: paper,
      onSurface: ink,
      surfaceContainerHighest: paper,
      onSurfaceVariant: inkMuted,
      outline: ruleStrong,
      outlineVariant: rule,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _sans,
      scaffoldBackgroundColor: paper,
      dividerTheme: DividerThemeData(color: rule, thickness: 1, space: 1),
      // No raised surfaces anywhere: separation is a line, not a shadow.
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: rule),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _serif,
          fontSize: 21,
          color: ink,
          letterSpacing: .5,
        ),
      ),
      textTheme: _serifDisplay(ink),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: paper,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: ink),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        labelStyle: TextStyle(color: inkMuted, fontFamily: _sans),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: rule),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: ink, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? paper : inkFaint),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : paper),
        trackOutlineColor: WidgetStatePropertyAll(rule),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStatePropertyAll(BorderSide(color: rule)),
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? ink : paper),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? paper : inkMuted),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          )),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: rule,
        circularTrackColor: rule,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: paper,
        elevation: 0,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? accent : inkFaint)),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontFamily: _sans, color: inkMuted),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: paper, fontFamily: _sans),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: rule),
          borderRadius: BorderRadius.circular(2),
        ),
        titleTextStyle:
            TextStyle(fontFamily: _serif, fontSize: 20, color: ink),
      ),
      extensions: [
        SoferTokens(
          layout: AppLayout.rules,
          paper: paper,
          panel: paper,
          rule: rule,
          ruleStrong: ruleStrong,
          ink: ink,
          inkMuted: inkMuted,
          inkFaint: inkFaint,
          accent: accent,
          danger: danger,
          positive: positive,
          caution: caution,
          numeralFamily: _serif,
          labelFamily: _sans,
          panelRadius: 2,
        ),
      ],
    );
  }

  /// Display sizes take the serif; body and labels stay sans, because a label
  /// set in a serif at 12px is harder to read, not more elegant.
  static TextTheme _serifDisplay(Color ink) => TextTheme(
        displayLarge: TextStyle(fontFamily: _serif, color: ink),
        displayMedium: TextStyle(fontFamily: _serif, color: ink),
        displaySmall: TextStyle(fontFamily: _serif, color: ink),
        headlineLarge: TextStyle(fontFamily: _serif, color: ink),
        headlineMedium: TextStyle(fontFamily: _serif, color: ink),
        headlineSmall: TextStyle(fontFamily: _serif, color: ink),
        titleLarge: TextStyle(fontFamily: _serif, color: ink),
      );
}
