import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/entry/entry_sheet.dart';
import 'package:sofer_vmone/hebrew_utils.dart';
import 'package:sofer_vmone/logic/calendar_days.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/date_logic.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/logic/monthly_report.dart';
import 'package:sofer_vmone/logic/production_plan.dart';
import 'package:sofer_vmone/logic/writing_journal.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/settings/work_day_exception_dialog.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/summary_screen.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

DateTime adar(int month, [int day = 1]) =>
    CalendarDays.midnight(JewishDate.initDate(
            jewishYear: 5787, jewishMonth: month, jewishDayOfMonth: day)
        .getGregorianCalendar());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Heebo', 'FrankRuhlLibre']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font-var.ttf')))
          .load();
    }
  });
  final project = Project(
      id: 'p',
      name: 'ספר',
      type: ProjectType.sefer,
      price: 100,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      linesPerPage: 42);

  test('every day in both Adars keeps its name in shared date displays', () {
    for (final month in [12, 13]) {
      final first = JewishDate.fromDateTime(adar(month));
      expect(first.isJewishLeapYear(), isTrue);
      for (var day = 1; day <= first.getDaysInJewishMonth(); day++) {
        final date = adar(month, day);
        for (final english in [false, true]) {
          final name = english
              ? (month == 12 ? 'Adar I' : 'Adar II')
              : (month == 12 ? 'אדר א' : 'אדר ב');
          for (final label in [
            formatDisplayDate(date, false, english: english),
            formatDisplayDateMonth(date, false, english: english),
            formatDisplayDateWithWeekday(date, false, english: english),
            WritingJournalLogic.dateLabel(date, JournalDateDisplay.both,
                english: english),
          ]) {
            expect(label, contains(name));
          }
        }
      }
    }
  });

  test(
      'saved sessions, summaries, monthly exports and plans separate the Adars',
      () {
    final history = [
      for (final month in [12, 13])
        WorkSession.fromJson(WorkSession(
          id: '$month',
          projectId: 'p',
          startTime: adar(month, 10).add(const Duration(hours: 9)),
          endTime: adar(month, 10).add(const Duration(hours: 10)),
          amount: 1,
          startLine: 1,
          endLine: month,
          description: '',
          isManual: true,
          workingDateAtEntry: adar(month, 10),
        ).toJson())
    ];
    for (final month in [12, 13]) {
      final date = adar(month);
      final length = month == 12 ? 30 : 29;
      expect(
          history
              .where(
                  (s) => DateLogic.sessionIsInMonth(s, date, DayStart.midnight))
              .map((s) => s.id),
          ['$month']);
      final report = MonthlyReport.forMonth(
          project: project,
          history: history,
          projects: [project],
          anyDayInMonth: date,
          dayStart: DayStart.midnight);
      expect(report.days.length, length);
      expect(report.totalLines, month);
      for (final english in [false, true]) {
        expect(
            report
                .toExportTable(
                    currency: Currency.ils,
                    useGregorianDates: false,
                    english: english)
                .title,
            contains(english
                ? (month == 12 ? 'Adar I' : 'Adar II')
                : (month == 12 ? "אדר א'" : "אדר ב'")));
      }
      final plan = ProductionPlan.forMonth(
          project: project,
          history: history,
          anyDayInMonth: date,
          rules: WorkCalendarRules.standard,
          dayStart: DayStart.midnight);
      expect(plan.days.length, length);
      expect(plan.from, adar(month));
      expect(plan.to, adar(month, length));
    }
  });

  for (final picker in ['entry', 'summary', 'exception']) {
    testWidgets('$picker offers both Adars after selecting 5787',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      StorageService.demoStore = MemoryStore({});
      addTearDown(() => StorageService.demoStore = null);
      tester.view.physicalSize = const Size(1300, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.modern),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Builder(
            builder: (context) => picker == 'summary'
                ? SummaryScreen(
                    projects: [project],
                    history: const [],
                    onHistoryUpdated: (_) {})
                : Scaffold(
                    body: TextButton(
                        onPressed: () {
                          if (picker == 'entry') {
                            showEntrySheet(
                                context: context,
                                isManual: true,
                                projects: [project],
                                history: const [],
                                useGregorianDates: false,
                                dayStart: DayStart.midnight,
                                onProjectCreated: (_) {},
                                onSave: (_) async {},
                                initialProject: project,
                                initialDate: adar(12));
                          } else {
                            showDialog<void>(
                                context: context,
                                builder: (_) => WorkDayExceptionDialog(
                                    date: adar(12),
                                    gregorian: false,
                                    takenDates: const {}));
                          }
                        },
                        child: const Text('open')))),
      ));
      await tester.pumpAndSettle();
      if (picker == 'summary') {
        await tester.tap(find.byIcon(Icons.date_range));
      } else {
        await tester.tap(find.text('open'));
      }
      await tester.pumpAndSettle();
      if (picker == 'entry') {
        await tester.ensureVisible(find.byIcon(Icons.event));
        await tester.tap(find.byIcon(Icons.event));
        await tester.pumpAndSettle();
        final dateButton = find.text(formatDisplayDate(adar(12), false));
        await tester.ensureVisible(dateButton);
        await tester.tap(dateButton);
        await tester.pumpAndSettle();
      }
      // Change away from and back to the leap year, exercising list rebuilds.
      for (final year in [5786, 5787]) {
        final yearDropdown = tester
            .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .firstWhere((w) => w.items!.any((item) => item.value == 5787));
        yearDropdown.onChanged!(year);
        await tester.pumpAndSettle();
        final monthDropdown = tester
            .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
            .firstWhere((w) => w.items!.length == (year == 5787 ? 13 : 12));
        expect(
            monthDropdown.items!.map((item) => item.value),
            year == 5787
                ? [7, 8, 9, 10, 11, 12, 13, 1, 2, 3, 4, 5, 6]
                : [7, 8, 9, 10, 11, 12, 1, 2, 3, 4, 5, 6]);
        if (year == 5787) {
          final labels =
              monthDropdown.items!.map((item) => (item.child as Text).data);
          expect(labels, containsAll(["אדר א'", "אדר ב'"]));
          for (final month in [12, 13]) {
            final current = tester
                .widgetList<DropdownButton<int>>(
                    find.byType(DropdownButton<int>))
                .firstWhere((w) => w.items!.length == 13);
            current.onChanged!(month);
            await tester.pumpAndSettle();
            final updated = tester
                .widgetList<DropdownButton<int>>(
                    find.byType(DropdownButton<int>))
                .firstWhere((w) => w.items!.length == 13);
            expect(updated.value, month);
          }
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
