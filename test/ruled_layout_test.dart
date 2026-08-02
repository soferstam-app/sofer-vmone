// Layout regressions in the ruled themes.
//
// These are here because the defects they cover were invisible to the analyzer
// and to every unit test, and were only reported after a release build had been
// used: a row asking its children to stretch to the height of an unbounded
// scroll view produces an infinitely tall page. In a debug build an assertion
// catches it; in a release build there is no assertion, so the page simply
// scrolls for ever and everything below the row is pushed out of reach.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/home/ruled_home_body.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/project/commission_timeline.dart';
import 'package:sofer_vmone/theme/app_theme.dart';
import 'package:sofer_vmone/widgets/sofer_widgets.dart';

void main() {
  Project project() => Project(
        id: 'p',
        name: 'ספר תורה לעילוי נשמת',
        type: ProjectType.sefer,
        price: 40000,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: 42,
      );

  HomeSnapshot snapshot({bool running = false}) => HomeSnapshot(
        project: project(),
        projects: [project()],
        hebrewDate: 'כ״ד באב תשפ״ו',
        isRunning: running,
        isPaused: false,
        elapsed: '00:12:40',
        currentLine: 7,
        pageLabel: 'עמוד קמ״ה',
        positionUnit: 'שורה',
        todayOutput: '38 שורות',
        hourlyRate: '₪72',
        doneOfTotal: '12 מתוך 245 עמודים',
        progress: 0.05,
        completion: 'יום ג׳, ה׳ תשרי תשפ״ח',
        completionDetail: 'בעוד 434 ימים · 270 ימי עבודה',
      );

  final actions = HomeActions(
    onStart: () {},
    onStop: () {},
    onBreak: () {},
    onManualEntry: () {},
    onNextLine: () {},
    onEditPosition: () {},
    onProjectChanged: (_) {},
    onResume: () {},
  );

  Widget host(Widget child, AppTheme theme) => MaterialApp(
        theme: AppThemeBuilder.build(theme),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: child),
        ),
      );

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('the ruled home screen', () {
    for (final theme in [AppTheme.klaf, AppTheme.layla]) {
      testWidgets('has a finite scroll extent side by side — ${theme.name}',
          (tester) async {
        await resize(tester, const Size(1280, 800));
        await tester.pumpWidget(host(
          RuledHomeBody(
              snapshot: snapshot(), actions: actions, isSmart: false),
          theme,
        ));
        await tester.pumpAndSettle();

        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        expect(position.maxScrollExtent.isFinite, isTrue);
        // The content is well short of an 800pt window, so there is nothing to
        // scroll at all. An infinite extent used to let it scroll up for ever.
        expect(position.maxScrollExtent, 0);
      });
    }

    testWidgets('has a finite scroll extent stacked on a phone',
        (tester) async {
      await resize(tester, const Size(360, 720));
      await tester.pumpWidget(host(
        RuledHomeBody(snapshot: snapshot(), actions: actions, isSmart: false),
        AppTheme.klaf,
      ));
      await tester.pumpAndSettle();

      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .maxScrollExtent
            .isFinite,
        isTrue,
      );
    });

    testWidgets('smart mode offers the position before the timer starts',
        (tester) async {
      await resize(tester, const Size(1280, 800));
      await tester.pumpWidget(host(
        RuledHomeBody(snapshot: snapshot(), actions: actions, isSmart: true),
        AppTheme.klaf,
      ));
      await tester.pumpAndSettle();

      // The position and the way to correct it both have to be there while the
      // timer is stopped: that is when a writer says where they are.
      expect(find.text('עמוד קמ״ה'), findsOneWidget);
      expect(find.text('שורה 7'), findsOneWidget);
      expect(find.text('הזנת מיקום ידנית'), findsOneWidget);
    });

    testWidgets('plain mode leads with the clock, not the position',
        (tester) async {
      await resize(tester, const Size(1280, 800));
      await tester.pumpWidget(host(
        RuledHomeBody(snapshot: snapshot(), actions: actions, isSmart: false),
        AppTheme.klaf,
      ));
      await tester.pumpAndSettle();

      expect(find.text('00:12:40'), findsOneWidget);
      expect(find.text('הזנת מיקום ידנית'), findsNothing);
    });
  });

  group('CommissionTimeline', () {
    // Four dates on one line, at every width the app runs at. The labels have to
    // fit and they have to stay off each other, whichever way the dates fall.
    const cases = <({String name, List<TimelineMark> marks, double elapsed})>[
      (
        name: 'a deadline later than the estimate',
        elapsed: 0.3,
        marks: [
          TimelineMark(caption: 'התחלה', value: 'כ״ד שבט תשפ״ו', at: 0),
          TimelineMark(caption: 'היום', at: 0.3, current: true),
          TimelineMark(caption: 'צפי סיום', value: 'ה׳ תשרי תשפ״ח', at: 0.72),
          TimelineMark(
              caption: 'תאריך יעד', value: 'א׳ כסלו תשפ״ח', at: 1, quiet: true),
        ],
      ),
      (
        name: 'a deadline earlier than the estimate',
        elapsed: 0.55,
        marks: [
          TimelineMark(caption: 'התחלה', value: 'כ״ד שבט תשפ״ו', at: 0),
          TimelineMark(caption: 'היום', at: 0.55, current: true),
          TimelineMark(caption: 'צפי סיום', value: 'ה׳ תשרי תשפ״ח', at: 1),
          TimelineMark(
              caption: 'תאריך יעד', value: 'ט״ו אב תשפ״ז', at: 0.6, quiet: true),
        ],
      ),
      (
        name: 'today all but on top of the estimate',
        elapsed: 0.96,
        marks: [
          TimelineMark(caption: 'התחלה', value: 'כ״ד שבט תשפ״ו', at: 0),
          TimelineMark(caption: 'היום', at: 0.96, current: true),
          TimelineMark(caption: 'צפי סיום', value: 'ה׳ תשרי תשפ״ח', at: 1),
        ],
      ),
      (
        name: 'a run with no length at all',
        elapsed: 1,
        marks: [
          TimelineMark(caption: 'התחלה', value: 'כ״ד שבט תשפ״ו', at: 0),
          TimelineMark(caption: 'היום', at: 1, current: true),
          TimelineMark(caption: 'צפי סיום', value: 'כ״ד שבט תשפ״ו', at: 1),
          TimelineMark(
              caption: 'תאריך יעד', value: 'כ״ד שבט תשפ״ו', at: 1, quiet: true),
        ],
      ),
      (
        name: 'a Gregorian date, which is the longest label there is',
        elapsed: 0.4,
        marks: [
          TimelineMark(caption: 'התחלה', value: '23 בפברואר 2026', at: 0),
          TimelineMark(caption: 'היום', at: 0.4, current: true),
          TimelineMark(caption: 'צפי סיום', value: '15 בספטמבר 2027', at: 1),
        ],
      ),
    ];

    for (final width in [320.0, 400.0, 620.0, 860.0]) {
      for (final c in cases) {
        testWidgets('${c.name} — ${width.round()}pt wide', (tester) async {
          await resize(tester, Size(width, 900));
          await tester.pumpWidget(host(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CommissionTimeline(marks: c.marks, elapsed: c.elapsed),
            ),
            AppTheme.klaf,
          ));
          await tester.pumpAndSettle();

          // An overflow raises here, which is the whole point of the sweep.
          expect(tester.takeException(), isNull);

          final rects = <Rect>[
            for (final element in find.byType(Text).evaluate())
              tester.getRect(find.byWidget(element.widget)),
          ];
          for (var i = 0; i < rects.length; i++) {
            for (var j = i + 1; j < rects.length; j++) {
              final overlap = rects[i].intersect(rects[j]);
              expect(overlap.isEmpty || overlap.width <= 0 || overlap.height <= 0,
                  isTrue,
                  reason: 'two labels overlap: ${rects[i]} and ${rects[j]}');
            }
          }
        });
      }
    }
  });

  group('SoferProgress', () {
    // It used to be laid out by a LayoutBuilder, which reports no intrinsic
    // height. Anything measuring a column that contained one got the wrong
    // answer, and IntrinsicHeight threw outright.
    testWidgets('can be measured inside an IntrinsicHeight', (tester) async {
      await resize(tester, const Size(600, 400));
      await tester.pumpWidget(host(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Expanded(child: SoferProgress(0.4)),
              Expanded(child: SoferProgress(0)),
            ],
          ),
        ),
        AppTheme.klaf,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Both bars, including the empty one, report the same measurable height.
      for (final element in find.byType(SoferProgress).evaluate()) {
        expect((element.renderObject as RenderBox).size.height, 3);
      }
    });
  });
}
