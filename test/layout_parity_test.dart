// The two home layouts must carry the same features.
//
// This exists because they did not. The break overrun clock was built into the
// cards layout and not the ruled one, and the settings switch that governs it
// went into the cards settings body and not the ruled one — so a writer on
// klaf or layla pressed "הפסקת קפה", saw no clock, went to settings, and found
// no switch. Both halves of the feature were invisible to exactly the people
// who use those themes.
//
// The layouts arrange differently. They never differ in what they can do.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/home/cards_smart_body.dart';
import 'package:sofer_vmone/home/ruled_home_body.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  Project project() => Project(
        id: 'p',
        name: 'ספר תורה',
        type: ProjectType.sefer,
        price: 40000,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: 42,
        totalPages: 245,
      );

  HomeSnapshot onBreak({
    required String remaining,
    required bool overrun,
  }) =>
      HomeSnapshot(
        project: project(),
        projects: [project()],
        hebrewDate: 'כ״ד באב תשפ״ו',
        isRunning: false,
        isPaused: true,
        elapsed: '00:41:10',
        sinceLastLap: '00:04:12',
        breakElapsed: '14:05',
        breakRemaining: remaining,
        breakOverrun: overrun,
        currentLine: 7,
        pageLabel: 'עמוד קמ״ה',
        positionUnit: 'שורה',
        todayOutput: '38 שורות',
        hourlyRate: '₪72',
        doneOfTotal: '12 מתוך 245 עמודים',
        progress: 0.05,
        completion: 'יום ג׳, ה׳ תשרי תשפ״ח',
        completionDetail: 'בעוד 434 ימים',
      );

  HomeSnapshot mezuzaRunning() {
    final mezuza = Project(
      id: 'm',
      name: 'מזוזות',
      type: ProjectType.mezuza,
      price: 180,
      expenses: 0,
      targetDaily: 2,
      targetMonthly: 40,
    );
    return HomeSnapshot(
      project: mezuza,
      projects: [mezuza],
      hebrewDate: 'כ״ד באב תשפ״ו',
      isRunning: true,
      isPaused: false,
      elapsed: '00:41:10',
      sinceLastLap: '00:04:12',
      currentLine: 7,
      pageLabel: 'מזוזה 4',
      positionUnit: 'שורה',
      todayOutput: '2 מזוזות',
    );
  }

  final actions = HomeActions(
    onStart: () {},
    onStop: () {},
    onBreak: () {},
    onManualEntry: () {},
    onNextLine: () {},
    onLap: () {},
    onEditPosition: () {},
    onSkipMezuza: () {},
    onProjectChanged: (_) {},
    onResume: () {},
  );

  Future<void> show(WidgetTester tester, Widget body, AppTheme theme) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(theme),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: body)),
      ),
    ));
    await tester.pump();
  }

  group('the break overrun reaches both layouts', () {
    testWidgets('cards says how much is left', (tester) async {
      await show(
        tester,
        CardsSmartBody(
            snapshot: onBreak(remaining: '03:12', overrun: false),
            actions: actions,
            pulse: const AlwaysStoppedAnimation(1.0)),
        AppTheme.modern,
      );
      expect(find.textContaining('03:12'), findsWidgets);
    });

    testWidgets('ruled says how much is left', (tester) async {
      await show(
        tester,
        RuledHomeBody(
            snapshot: onBreak(remaining: '03:12', overrun: false),
            actions: actions,
            isSmart: true),
        AppTheme.klaf,
      );
      expect(find.textContaining('03:12'), findsWidgets,
          reason: 'the ruled layout showed nothing at all');
    });

    testWidgets('cards shows the overrun', (tester) async {
      await show(
        tester,
        CardsSmartBody(
            snapshot: onBreak(remaining: '-04:05', overrun: true),
            actions: actions,
            pulse: const AlwaysStoppedAnimation(1.0)),
        AppTheme.modern,
      );
      expect(find.textContaining('-04:05'), findsWidgets);
      expect(find.textContaining('חריגה'), findsWidgets);
    });

    testWidgets('ruled shows the overrun', (tester) async {
      await show(
        tester,
        RuledHomeBody(
            snapshot: onBreak(remaining: '-04:05', overrun: true),
            actions: actions,
            isSmart: true),
        AppTheme.klaf,
      );
      expect(find.textContaining('-04:05'), findsWidgets);
      expect(find.textContaining('חריגה'), findsWidgets);
    });
  });

  group('with no length set, neither layout invents one', () {
    testWidgets('cards', (tester) async {
      await show(
        tester,
        CardsSmartBody(
            snapshot: onBreak(remaining: '', overrun: false),
            actions: actions,
            pulse: const AlwaysStoppedAnimation(1.0)),
        AppTheme.modern,
      );
      expect(find.textContaining('נותרו'), findsNothing);
      expect(find.textContaining('חריגה'), findsNothing);
    });

    testWidgets('ruled', (tester) async {
      await show(
        tester,
        RuledHomeBody(
            snapshot: onBreak(remaining: '', overrun: false),
            actions: actions,
            isSmart: true),
        AppTheme.klaf,
      );
      expect(find.textContaining('נותרו'), findsNothing);
      expect(find.textContaining('חריגה'), findsNothing);
    });
  });

  group('the large smart position changes the location in both layouts', () {
    HomeActions spy(VoidCallback onEdit) => HomeActions(
          onStart: () {},
          onStop: () {},
          onBreak: () {},
          onManualEntry: () {},
          onNextLine: () {},
          onLap: () {},
          onEditPosition: onEdit,
          onSkipMezuza: () {},
          onProjectChanged: (_) {},
          onResume: () {},
        );

    testWidgets('cards', (tester) async {
      var edits = 0;
      await show(
        tester,
        CardsSmartBody(
          snapshot: onBreak(remaining: '', overrun: false),
          actions: spy(() => edits++),
          pulse: const AlwaysStoppedAnimation(1),
        ),
        AppTheme.modern,
      );
      await tester.tap(find.text('שורה 7'));
      expect(edits, 1);
      expect(find.text('ערוך מיקום'), findsNothing);
    });

    for (final theme in [AppTheme.klaf, AppTheme.layla]) {
      testWidgets('ruled — ${theme.name}', (tester) async {
        var edits = 0;
        await show(
          tester,
          RuledHomeBody(
            snapshot: onBreak(remaining: '', overrun: false),
            actions: spy(() => edits++),
            isSmart: true,
          ),
          theme,
        );
        await tester.tap(find.text('שורה 7'));
        expect(edits, 1);
        expect(find.text('הזנת מיקום ידנית'), findsNothing);
      });
    }
  });

  group('skipping a mezuza is present in every layout', () {
    HomeActions spy(VoidCallback onSkip) => HomeActions(
          onStart: () {},
          onStop: () {},
          onBreak: () {},
          onManualEntry: () {},
          onNextLine: () {},
          onLap: () {},
          onEditPosition: () {},
          onSkipMezuza: onSkip,
          onProjectChanged: (_) {},
          onResume: () {},
        );

    testWidgets('cards', (tester) async {
      var skips = 0;
      await show(
        tester,
        CardsSmartBody(
          snapshot: mezuzaRunning(),
          actions: spy(() => skips++),
          pulse: const AlwaysStoppedAnimation(1),
        ),
        AppTheme.modern,
      );
      await tester.tap(find.text('עבור למזוזה הבאה'));
      expect(skips, 1);
    });

    for (final theme in [AppTheme.klaf, AppTheme.layla]) {
      testWidgets('ruled — ${theme.name}', (tester) async {
        var skips = 0;
        await show(
          tester,
          RuledHomeBody(
            snapshot: mezuzaRunning(),
            actions: spy(() => skips++),
            isSmart: true,
          ),
          theme,
        );
        await tester.tap(find.text('עבור למזוזה הבאה'));
        expect(skips, 1);
      });
    }
  });
}
