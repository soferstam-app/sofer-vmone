import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/hebrew_utils.dart';
import 'package:sofer_vmone/logic/calendar_days.dart';
import 'package:sofer_vmone/logic/hebrew_month.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/plan/production_plan_screen.dart';
import 'package:sofer_vmone/reports/monthly_report_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

DateTime hebrew(int year, int month, [int day = 1]) =>
    CalendarDays.midnight(JewishDate.initDate(
            jewishYear: year, jewishMonth: month, jewishDayOfMonth: day)
        .getGregorianCalendar());

void main() {
  test('5787 includes both Adars in both directions', () {
    final months = [11, 12, 13, 1, 2];
    for (var i = 0; i < months.length; i++) {
      expect(
          shiftHebrewMonth(hebrew(5787, 11, 20), i), hebrew(5787, months[i]));
      expect(shiftHebrewMonth(hebrew(5787, 2, 20), -i),
          hebrew(5787, months[months.length - 1 - i]));
    }
    expect(formatDisplayDateMonth(hebrew(5787, 12), false), contains("אדר א'"));
    expect(formatDisplayDateMonth(hebrew(5787, 13), false), contains("אדר ב'"));
    expect(formatDisplayDateMonth(hebrew(5787, 12), false, english: true),
        contains('Adar I '));
    expect(formatDisplayDateMonth(hebrew(5787, 13), false, english: true),
        contains('Adar II '));
  });

  test('ordinary Adar leads to Nisan in the same year', () {
    expect(shiftHebrewMonth(hebrew(5786, 12, 29), 1), hebrew(5786, 1));
    expect(shiftHebrewMonth(hebrew(5786, 1), -1), hebrew(5786, 12));
  });

  test('the year changes between Elul and Tishrei', () {
    expect(shiftHebrewMonth(hebrew(5786, 6, 29), 1), hebrew(5787, 7));
    expect(shiftHebrewMonth(hebrew(5787, 7), -1), hebrew(5786, 6));
  });

  test('a full 19 year cycle visits every month in chronological order', () {
    final start = hebrew(5780, 7);
    var index = 0;
    for (var year = 5780; year < 5799; year++) {
      final leap = JewishDate.fromDateTime(hebrew(year, 7)).isJewishLeapYear();
      for (final month in [
        7,
        8,
        9,
        10,
        11,
        12,
        if (leap) 13,
        1,
        2,
        3,
        4,
        5,
        6
      ]) {
        final expected = hebrew(year, month);
        expect(shiftHebrewMonth(start, index), expected);
        expect(shiftHebrewMonth(expected, -index), start);
        index++;
      }
    }
    expect(index, 235);
    expect(shiftHebrewMonth(start, index), hebrew(5799, 7));
  });

  final project = Project(
    id: 'p',
    name: 'ספר',
    type: ProjectType.sefer,
    price: 100,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 42,
  );

  testWidgets('a plan day opens and saves from a desktop window',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    StorageService.demoStore = MemoryStore({});
    addTearDown(() => StorageService.demoStore = null);
    tester.view.physicalSize = const Size(1240, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final another = Project(
        id: 'q',
        name: 'ספר שני',
        type: ProjectType.sefer,
        price: 0,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20);
    await StorageService().saveProjects([project, another]);
    final plan =
        ProductionPlanScreen(projects: [project, another], history: const []);
    await tester.pumpWidget(
        MaterialApp(theme: AppThemeBuilder.build(AppTheme.klaf), home: plan));
    await tester.pumpAndSettle();
    await tester.tap(find.text(formatHebrewNumber(1)).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('לא כותב'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final stored = await StorageService().loadProjects();
    expect(stored.length, 2);
    expect(stored.firstWhere((p) => p.id == project.id).planOverrides.values,
        [0.0]);
  });

  for (final theme in AppTheme.values) {
    for (final plan in [false, true]) {
      testWidgets('${plan ? 'plan' : 'report'} month buttons in $theme',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        StorageService.demoStore = MemoryStore({});
        addTearDown(() => StorageService.demoStore = null);
        tester.view.physicalSize = const Size(1300, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final start = DateTime.now();
        await tester.pumpWidget(MaterialApp(
          theme: AppThemeBuilder.build(theme),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: plan
                ? ProductionPlanScreen(projects: [project], history: const [])
                : MonthlyReportScreen(projects: [project], history: const []),
          ),
        ));
        await tester.pumpAndSettle();
        // From any starting date, three years cross both Adars and a year end.
        for (final direction in [1, -1]) {
          for (var step = 1; step <= 36; step++) {
            await tester
                .tap(find.byTooltip(direction > 0 ? 'חודש הבא' : 'חודש קודם'));
            await tester.pumpAndSettle();
            final offset = direction > 0 ? step : 36 - step;
            expect(
                find.text(formatDisplayDateMonth(
                    shiftHebrewMonth(start, offset), false)),
                findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
