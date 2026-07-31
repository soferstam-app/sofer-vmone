// Every screen, in every theme, on the same data.
//
// The three themes are meant to differ in arrangement and in nothing else: the
// same commissions, the same settings, the same figures. Nothing in the code is
// supposed to read the theme to decide what to show — only how to show it — but
// that is an invariant no compiler checks, and the layouts are written
// separately. So this builds each screen under all three and asserts both that
// it renders without an exception and that the data on it is the same.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/expenses_screen.dart';
import 'package:sofer_vmone/features_screen.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/project_comparison_screen.dart';
import 'package:sofer_vmone/project_summary_screen.dart';
import 'package:sofer_vmone/projects_screen.dart';
import 'package:sofer_vmone/quote_screen.dart';
import 'package:sofer_vmone/recycle_bin_screen.dart';
import 'package:sofer_vmone/settings_screen.dart';
import 'package:sofer_vmone/summary_screen.dart';
import 'package:sofer_vmone/theme/app_theme.dart';
import 'package:sofer_vmone/work_calendar_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const seferName = 'ספר תורה לבית הכנסת';
  const mezuzaName = 'הזמנת מזוזות';

  final projects = <Project>[
    Project(
      id: 'p1',
      name: seferName,
      type: ProjectType.sefer,
      price: 40000,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      linesPerPage: 42,
      totalPages: 245,
    ),
    Project(
      id: 'p2',
      name: mezuzaName,
      type: ProjectType.mezuza,
      price: 180,
      expenses: 40,
      targetDaily: 2,
      targetMonthly: 40,
      targetUnits: 12,
    ),
  ];

  final history = <WorkSession>[
    WorkSession(
      id: 's1',
      projectId: 'p1',
      startTime: DateTime(2026, 7, 20, 9),
      endTime: DateTime(2026, 7, 20, 12),
      amount: 3,
      startLine: 1,
      endLine: 42,
      description: 'עמוד ג',
      isManual: false,
    ),
    WorkSession(
      id: 's2',
      projectId: 'p2',
      startTime: DateTime(2026, 7, 21, 9),
      endTime: DateTime(2026, 7, 21, 11),
      amount: 2,
      startLine: 1,
      endLine: 22,
      description: 'שתי מזוזות',
      isManual: false,
    ),
  ];

  setUp(() {
    // Every screen reads its settings through StorageService; without this the
    // platform channel is missing and each of them fails for the same, wrong,
    // reason.
    SharedPreferences.setMockInitialValues({});
  });

  Widget host(Widget screen, AppTheme theme) => MaterialApp(
        theme: AppThemeBuilder.build(theme),
        home: Directionality(textDirection: TextDirection.rtl, child: screen),
      );

  /// Builds [screen] under every theme and hands each rendering to [check].
  ///
  /// The assertion that matters is that [check] passes identically all three
  /// times: same data, whatever the arrangement.
  Future<void> inEveryTheme(
    WidgetTester tester,
    Widget Function() screen,
    Future<void> Function(WidgetTester tester, AppTheme theme) check,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final theme in AppTheme.values) {
      await tester.pumpWidget(host(screen(), theme));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull,
          reason: '${theme.name} threw while building');
      await check(tester, theme);
    }
  }

  testWidgets('the projects screen lists the same commissions', (tester) async {
    await inEveryTheme(
      tester,
      () => ProjectsScreen(
        projects: projects,
        onProjectAdded: (_) {},
        onProjectUpdated: (_) {},
        onProjectDeleted: (_) {},
        onResetAllData: () {},
      ),
      (tester, theme) async {
        expect(find.text(seferName), findsOneWidget, reason: theme.name);
        expect(find.text(mezuzaName), findsOneWidget, reason: theme.name);
      },
    );
  });

  testWidgets('the commission screen shows the same figures', (tester) async {
    await inEveryTheme(
      tester,
      () => ProjectSummaryScreen(projects: projects, history: history),
      (tester, theme) async {
        // The first project is selected on entry in every theme.
        expect(find.text(seferName), findsWidgets, reason: theme.name);
        // 42 lines written of a 42-line page: one page, no odd lines.
        expect(find.textContaining('1 עמודים'), findsWidgets,
            reason: theme.name);
      },
    );
  });

  testWidgets('the daily summary opens on the same day', (tester) async {
    await inEveryTheme(
      tester,
      () => SummaryScreen(
        projects: projects,
        history: history,
        onHistoryUpdated: (_) {},
      ),
      (tester, theme) async {
        expect(find.textContaining('סיכום פרויקט'), findsWidgets,
            reason: theme.name);
      },
    );
  });

  testWidgets('the quote offers the same three kinds of work', (tester) async {
    await inEveryTheme(
      tester,
      () => QuoteScreen(projects: projects, history: history),
      (tester, theme) async {
        expect(find.text('ספר תורה'), findsOneWidget, reason: theme.name);
        expect(find.text('מזוזות'), findsOneWidget, reason: theme.name);
        expect(find.text('תפילין'), findsOneWidget, reason: theme.name);
      },
    );
  });

  testWidgets('the expenses screen opens empty in the same way', (tester) async {
    await inEveryTheme(
      tester,
      () => ExpensesScreen(projects: projects),
      (tester, theme) async {
        expect(find.textContaining('הוצאות'), findsWidgets, reason: theme.name);
      },
    );
  });

  testWidgets('the working-day rules read the same', (tester) async {
    await inEveryTheme(
      tester,
      () => const WorkCalendarSettingsScreen(),
      (tester, theme) async {
        expect(find.textContaining('אינם ימי עבודה'), findsWidgets,
            reason: theme.name);
        // The fixed list is stated in full, and says what it means.
        expect(find.textContaining('תשעה באב וערב תשעה באב'), findsWidgets,
            reason: theme.name);
      },
    );
  });

  testWidgets('the tools screen offers the same tools', (tester) async {
    await inEveryTheme(
      tester,
      () => FeaturesScreen(projects: projects, history: history),
      (tester, theme) async {
        expect(find.text('השוואת רווחיות'), findsOneWidget, reason: theme.name);
        expect(find.text('מחשבון הצעת מחיר'), findsOneWidget,
            reason: theme.name);
      },
    );
  });

  testWidgets('the comparison ranks the same work', (tester) async {
    await inEveryTheme(
      tester,
      () => ProjectComparisonScreen(projects: projects, history: history),
      (tester, theme) async {
        expect(find.textContaining('משתלם'), findsWidgets, reason: theme.name);
      },
    );
  });

  testWidgets('settings offer the same settings', (tester) async {
    await inEveryTheme(
      tester,
      () => const SettingsScreen(),
      (tester, theme) async {
        // Every entry, in both arrangements. A setting that exists in one look
        // and not in another is the failure this is here to catch.
        for (final entry in [
          'התראות יומיות',
          'תאריכים לועזיים',
          'עיצוב',
          'ימי עבודה',
          'מעבר יום',
          'שם הסופר',
          'גיבוי הנתונים',
        ]) {
          expect(find.text(entry), findsOneWidget,
              reason: '$entry is missing in ${theme.name}');
        }
      },
    );
  });

  testWidgets('the recycle bin reports the same emptiness', (tester) async {
    await inEveryTheme(
      tester,
      () => const RecycleBinScreen(),
      (tester, theme) async {
        expect(find.textContaining('סל מחזור'), findsWidgets,
            reason: theme.name);
      },
    );
  });
}
