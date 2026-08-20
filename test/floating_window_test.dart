// The small always-on-top window belongs to the app the writer chose.
//
// It was exempt from the themes on the argument that a control surface wants
// contrast rather than character. A writer who chose parchment and shrank the
// window got a deep purple box on his desk belonging to no app he recognised.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/home/floating_window.dart';
import 'package:sofer_vmone/logic/timer_controller.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  late TimerController clock;

  setUp(() => clock = TimerController(onTick: () {}));
  tearDown(() => clock.dispose());

  /// Builds the window under [theme] and returns the surface it painted
  /// alongside the tokens that were actually in scope while it built.
  Future<({Color surface, SoferTokens tokens})> render(
      WidgetTester tester, AppTheme theme) async {
    late SoferTokens seen;

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(theme),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(builder: (context) {
          seen = SoferTokens.of(context);
          return FloatingTimerWindow(
            clock: clock,
            onStart: () {},
            onPause: () {},
            onStop: () {},
            onLap: () {},
            onRestore: () {},
          );
        }),
      ),
    ));
    // Settled, not pumped once: MaterialApp animates a theme change, so a
    // single frame catches the colour half way between the two.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: theme.name);

    final material = tester.widget<Material>(find
        .descendant(
            of: find.byType(FloatingTimerWindow),
            matching: find.byType(Material))
        .first);
    return (surface: material.color!, tokens: seen);
  }

  testWidgets('it paints the theme\'s own paper, in every theme',
      (tester) async {
    for (final theme in AppTheme.values) {
      final r = await render(tester, theme);
      expect(r.surface, r.tokens.paper, reason: theme.name);
    }
  });

  testWidgets('so parchment and night do not look the same', (tester) async {
    // One hardcoded colour for all of them is what this replaced.
    final klaf = await render(tester, AppTheme.klaf);
    final layla = await render(tester, AppTheme.layla);
    expect(klaf.surface, isNot(layla.surface));
  });

  testWidgets('the clock reads in the theme\'s numerals', (tester) async {
    final r = await render(tester, AppTheme.klaf);
    final clockText = tester.widget<Text>(find.text('00:00:00').first);
    expect(clockText.style!.fontFamily, r.tokens.numeralFamily);
    expect(clockText.style!.color, r.tokens.ink);
    expect(find.text('זמן כתיבה'), findsOneWidget);
    expect(find.text('זמן השורה'), findsOneWidget);
  });

  testWidgets('every action is reachable', (tester) async {
    await render(tester, AppTheme.klaf);
    expect(find.byTooltip("הפסקה"), findsOneWidget);
    expect(find.byTooltip("סיום"), findsOneWidget);
    expect(find.byTooltip("סיום שורה"), findsOneWidget);
    expect(find.byTooltip("החזר חלון"), findsOneWidget);
  });

  testWidgets('marking a line is not offered during a break', (tester) async {
    // The time it would report is time nobody was writing.
    clock.start();
    clock.pause();
    await render(tester, AppTheme.layla);

    expect(find.byTooltip("סיום שורה"), findsNothing);
    expect(find.byTooltip("המשך"), findsOneWidget);

    // A break keeps ticking now — the break clock has to move — so the timer
    // is still live here. tearDown runs after the framework checks for pending
    // timers, which is too late.
    clock.dispose();
  });
}
