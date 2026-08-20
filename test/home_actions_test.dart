// Which button is the big one.
//
// During a sitting a writer marks a finished line dozens of times; he breaks
// once and stops once, at the end. The screen had it the other way round — the
// filled, full-width button was "stop and finish", and marking a line was a
// small outlined one beneath it. So the action under the thumb all evening was
// the one pressed last, and the one pressed last was easiest to hit by mistake.
//
// This is a layout decision that no compiler protects and that a later tidy-up
// would quietly undo, which is why it is written down here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/home/ruled_home_body.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/theme/app_theme.dart';
import 'package:sofer_vmone/widgets/sofer_widgets.dart';

void main() {
  final project = Project(
    id: 'p1',
    name: 'ספר תורה לבית הכנסת',
    type: ProjectType.sefer,
    price: 40000,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 42,
    totalPages: 245,
  );

  HomeSnapshot snap({
    bool running = false,
    bool paused = false,
    List<Project>? projects,
  }) =>
      HomeSnapshot(
        project: projects != null && projects.isEmpty ? null : project,
        projects: projects ?? [project],
        hebrewDate: 'כ״ג באב תשפ״ו',
        isRunning: running,
        isPaused: paused,
        elapsed: '01:24:07',
        sinceLastLap: '00:03:12',
        currentLine: 12,
        pageLabel: 'עמוד ק״מ',
        positionUnit: 'שורה',
        todayOutput: '31 שורות',
      );

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

  Future<void> pump(
    WidgetTester tester, {
    required HomeSnapshot snapshot,
    required bool isSmart,
  }) async {
    tester.view.physicalSize = const Size(800, 1720);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.klaf),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: RuledHomeBody(
              snapshot: snapshot, actions: actions, isSmart: isSmart),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  }

  group('mid-sitting, tracking the position', () {
    testWidgets('marking a line is the leading action', (tester) async {
      await pump(tester, snapshot: snap(running: true), isSmart: true);

      expect(find.widgetWithText(SoferPrimaryButton, 'סיימתי שורה'),
          findsOneWidget);
      expect(find.text('זמן כתיבה'), findsOneWidget);
      expect(find.text('זמן השורה'), findsOneWidget);
      expect(find.text('00:03:12'), findsOneWidget);
    });

    testWidgets('stopping and breaking step back', (tester) async {
      await pump(tester, snapshot: snap(running: true), isSmart: true);

      expect(find.widgetWithText(SoferSecondaryButton, 'סיים'), findsOneWidget);
      expect(
          find.widgetWithText(SoferSecondaryButton, 'הפסקה'), findsOneWidget);
      expect(find.widgetWithText(SoferPrimaryButton, 'סיים'), findsNothing);
    });
  });

  group('where there is no line to mark', () {
    testWidgets('a plain sitting marks lines too', (tester) async {
      // Nothing is tracking the position, but the writer still finishes lines
      // and still wants them timed. The cards layout has always offered this;
      // the ruled ones could not, because the action was never passed in.
      await pump(tester, snapshot: snap(running: true), isSmart: false);

      expect(find.widgetWithText(SoferPrimaryButton, 'סיימתי שורה'),
          findsOneWidget);
      expect(find.widgetWithText(SoferSecondaryButton, 'סיים'), findsOneWidget);
    });

    testWidgets('and it marks rather than advances a position', (tester) async {
      var lapped = 0;
      var advanced = 0;
      final spy = HomeActions(
        onStart: () {},
        onStop: () {},
        onBreak: () {},
        onManualEntry: () {},
        onNextLine: () => advanced++,
        onLap: () => lapped++,
        onEditPosition: () {},
        onSkipMezuza: () {},
        onProjectChanged: (_) {},
        onResume: () {},
      );

      tester.view.physicalSize = const Size(800, 1720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.klaf),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: RuledHomeBody(
                snapshot: snap(running: true), actions: spy, isSmart: false),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(SoferPrimaryButton, 'סיימתי שורה'));
      await tester.pump();

      expect(lapped, 1);
      expect(advanced, 0, reason: 'plain mode has no position to advance');
    });

    testWidgets('a paused sitting does too', (tester) async {
      await pump(tester,
          snapshot: snap(running: true, paused: true), isSmart: true);

      expect(find.widgetWithText(SoferPrimaryButton, 'סיים'), findsOneWidget);
      expect(find.widgetWithText(SoferSecondaryButton, 'המשך'), findsOneWidget);
    });

    testWidgets('"המשך" resumes, and does not start another break',
        (tester) async {
      // It called onBreak while saying "המשך", so pressing it paused again: in
      // plain mode the writer was stuck in a break with no way back to writing
      // except ending the sitting, and in smart mode the break dialog reopened.
      var resumed = 0;
      var broke = 0;
      final spy = HomeActions(
        onStart: () {},
        onStop: () {},
        onBreak: () => broke++,
        onManualEntry: () {},
        onNextLine: () {},
        onLap: () {},
        onEditPosition: () {},
        onSkipMezuza: () {},
        onProjectChanged: (_) {},
        onResume: () => resumed++,
      );

      tester.view.physicalSize = const Size(800, 1720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.klaf),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: RuledHomeBody(
                snapshot: snap(running: true, paused: true),
                actions: spy,
                isSmart: false),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.widgetWithText(SoferSecondaryButton, 'המשך'));
      await tester.pump();

      expect(resumed, 1);
      expect(broke, 0, reason: 'pressing "המשך" started another break');
    });
  });

  group('before anything has started', () {
    testWidgets('starting is the leading action', (tester) async {
      await pump(tester, snapshot: snap(), isSmart: false);

      expect(find.widgetWithText(SoferPrimaryButton, 'תחילת כתיבה'),
          findsOneWidget);
      expect(find.widgetWithText(SoferSecondaryButton, 'הזנה ידנית'),
          findsOneWidget);
    });

    testWidgets('with no commissions, the screen says so and offers no timer',
        (tester) async {
      // A first launch. A running clock with nothing to file the sitting
      // against is not a start screen, it is a trap.
      await pump(tester, snapshot: snap(projects: []), isSmart: false);

      expect(find.text('אין עוד פרויקטים'), findsOneWidget);
      expect(find.text('תחילת כתיבה'), findsNothing);
    });
  });
}
