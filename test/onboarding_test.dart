// The opening explanation: who sees it, and what it says.
//
// Two things are worth holding still here. The first is that it must not be
// shown to a sofer who has been working for months — he updated from an older
// version, has never seen it, and being told what a project is would insult
// him before it helped. The second is the wording itself: the screen exists
// because the app's model is not self-evident, so the words are the feature.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/logic/onboarding.dart';
import 'package:sofer_vmone/onboarding/onboarding_screen.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('who is shown it', () {
    test('someone opening the app for the first time', () {
      expect(
          shouldShowOnboarding(
              seen: false, hasProjects: false, hasHistory: false),
          isTrue);
    });

    test('not someone who has already read it', () {
      expect(
          shouldShowOnboarding(
              seen: true, hasProjects: false, hasHistory: false),
          isFalse);
    });

    test('not someone updating from an older version', () {
      // He has never seen it and does not need it: the projects prove it.
      expect(
          shouldShowOnboarding(
              seen: false, hasProjects: true, hasHistory: false),
          isFalse);
      expect(
          shouldShowOnboarding(
              seen: false, hasProjects: false, hasHistory: true),
          isFalse);
    });
  });

  group('what it says', () {
    test('five pages, and the second is the one that explains the model', () {
      expect(onboardingPages.length, 5);
      final method = onboardingPages[1];
      expect(method.kind, OnboardingKind.steps);
      expect(method.items.map((i) => i.label),
          containsAllInOrder(['פרויקט', 'ישיבה', 'שורה']));
    });

    test('the first page answers the three questions before they are asked',
        () {
      final opening = onboardingPages.first.footnote!;
      expect(opening, contains('אין הרשמה'));
      expect(opening, contains('אין תשלום'));
      expect(opening, contains('אין צורך באינטרנט'));
    });

    test('it ends by asking rather than telling', () {
      expect(onboardingPages.last.kind, OnboardingKind.appearance);
    });

    test('nothing is left empty', () {
      for (final page in onboardingPages) {
        expect(page.title, isNotEmpty);
        final hasBody = page.paragraphs.isNotEmpty ||
            page.items.isNotEmpty ||
            page.footnote != null ||
            page.kind == OnboardingKind.appearance;
        expect(hasBody, isTrue, reason: 'page "${page.title}" says nothing');
      }
    });
  });

  group('on screen', () {
    Widget harness(void Function({required bool createProject}) onDone) =>
        MaterialApp(
          theme: AppThemeBuilder.build(AppTheme.klaf),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: OnboardingScreen(onDone: onDone),
          ),
        );

    testWidgets('opens on the first page, counted from one', (tester) async {
      await tester.pumpWidget(harness(({required createProject}) {}));
      expect(find.text('1 מתוך 5'), findsOneWidget);
      expect(find.text('סופר ומונה'), findsOneWidget);
    });

    testWidgets('walks all five and ends on the last button', (tester) async {
      var done = false;
      var asked = false;
      await tester.pumpWidget(harness(({required createProject}) {
        done = true;
        asked = createProject;
      }));

      for (var page = 1; page < 5; page++) {
        await tester.tap(find.text('הבא'));
        await tester.pumpAndSettle();
        expect(find.text('${page + 1} מתוך 5'), findsOneWidget);
      }

      expect(find.text('הבא'), findsNothing, reason: 'the last page asks');
      await tester.tap(find.text('פתיחת פרויקט ראשון'));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(asked, isTrue, reason: 'it opens what it spent five pages on');
    });

    testWidgets('skipping leaves without asking for a project',
        (tester) async {
      var asked = true;
      await tester.pumpWidget(harness(({required createProject}) {
        asked = createProject;
      }));

      await tester.tap(find.text('דלג'));
      await tester.pumpAndSettle();
      expect(asked, isFalse);
    });

    testWidgets('survives the system font being raised', (tester) async {
      // The readers are older than average and many of them enlarge text. A
      // page laid out to an exact height loses its button off the bottom.
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.klaf),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: OnboardingScreen(onDone: ({required createProject}) {}),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('הבא'), findsOneWidget,
          reason: 'the button must stay reachable');
    });

    testWidgets('is dressed by the theme, not by hardcoded colour',
        (tester) async {
      for (final theme in AppTheme.values) {
        await tester.pumpWidget(MaterialApp(
          theme: AppThemeBuilder.build(theme),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: OnboardingScreen(onDone: ({required createProject}) {}),
          ),
        ));
        await tester.pumpAndSettle();

        final tokens =
            AppThemeBuilder.build(theme).extension<SoferTokens>()!;
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.backgroundColor, tokens.paper, reason: theme.name);
      }
    });
  });
}
