import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/hebrew_utils.dart';
import 'package:sofer_vmone/home/cards_smart_body.dart';
import 'package:sofer_vmone/home/ruled_home_body.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/logic/calendar_days.dart';
import 'package:sofer_vmone/logic/date_logic.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/writing_journal.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/summary_screen.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const twoAm = DayStart(boundary: DayBoundary.fixedHour, hour: 2);
  final yesterday = DateTime(2026, 11, 8);
  final today = DateTime(2026, 11, 9);
  final project = Project(
    id: 'p',
    name: 'ספר לבדיקה',
    type: ProjectType.sefer,
    price: 4200,
    expenses: 0,
    targetDaily: 0,
    targetMonthly: 0,
    totalPages: 10,
    linesPerPage: 42,
  );

  WorkSession record(DateTime start, DayStart rule, {String id = 'saved'}) =>
      WorkSession(
        id: id,
        projectId: project.id,
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        amount: 1,
        startLine: 1,
        endLine: 31,
        description: '31 שורות',
        isManual: false,
        linesPerPageAtEntry: 42,
        dayRule: rule,
      );

  setUpAll(() async {
    for (final font in ['Heebo', 'FrankRuhlLibre']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font-var.ttf')))
          .load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => StorageService.demoStore = null);

  Widget host(WidgetTester tester, AppTheme theme, Widget home) {
    tester.view.physicalSize = const Size(1400, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return MaterialApp(
      theme: AppThemeBuilder.build(theme),
      home: Directionality(textDirection: TextDirection.rtl, child: home),
    );
  }

  Future<void> openHome(WidgetTester tester, AppTheme theme,
      DateTime Function() now, DayStart rule, List<WorkSession> records) async {
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([project.toJson()]),
      'history': jsonEncode([for (final s in records) s.toJson()]),
      'day_start': jsonEncode(rule.toJson()),
      'use_gregorian_dates': true,
      'smart_workflow_enabled': true,
    });
    await tester
        .pumpWidget(host(tester, theme, SoferHome(workingDayClock: now)));
    await tester.pumpAndSettle();
  }

  HomeSnapshot snapshot(WidgetTester tester, AppTheme theme) =>
      theme == AppTheme.modern
          ? tester.widget<CardsSmartBody>(find.byType(CardsSmartBody)).snapshot
          : tester.widget<RuledHomeBody>(find.byType(RuledHomeBody)).snapshot;

  for (final theme in AppTheme.values) {
    testWidgets('home in $theme excludes yesterday after a 02:00 boundary',
        (tester) async {
      await openHome(tester, theme, () => today.add(const Duration(hours: 8)),
          twoAm, [record(yesterday.add(const Duration(hours: 18)), twoAm)]);
      final current = snapshot(tester, theme);
      expect(current.hebrewDate, contains('09.11.2026'));
      expect(current.todayOutput, '0 שורות');
      expect(current.hourlyRate, isNull);
    });
  }

  testWidgets('idle home refreshes both date and totals at the fixed hour',
      (tester) async {
    var now = today.add(const Duration(hours: 1, minutes: 59));
    final old = record(yesterday.add(const Duration(hours: 18)), twoAm);
    await openHome(tester, AppTheme.klaf, () => now, twoAm, [old]);
    expect(snapshot(tester, AppTheme.klaf).hebrewDate, contains('08.11.2026'));
    expect(snapshot(tester, AppTheme.klaf).todayOutput, '31 שורות');
    expect(snapshot(tester, AppTheme.klaf).hourlyRate, isNotNull);

    now = today.add(const Duration(hours: 2));
    await tester.pump(const Duration(minutes: 1));
    final current = snapshot(tester, AppTheme.klaf);
    expect(current.hebrewDate, contains('09.11.2026'));
    expect(current.todayOutput, '0 שורות');
    expect(current.hourlyRate, isNull);
    expect(
        (await StorageService().loadHistory()).single.toJson(), old.toJson());
  });

  testWidgets('home refreshes on resume without waiting for the idle check',
      (tester) async {
    var now = yesterday.add(const Duration(hours: 23));
    await openHome(tester, AppTheme.klaf, () => now, DayStart.midnight,
        [record(yesterday.add(const Duration(hours: 18)), DayStart.midnight)]);
    expect(snapshot(tester, AppTheme.klaf).todayOutput, '31 שורות');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    now = today;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(snapshot(tester, AppTheme.klaf).hebrewDate, contains('09.11.2026'));
    expect(snapshot(tester, AppTheme.klaf).todayOutput, '0 שורות');
  });

  for (final boundary in [DayBoundary.sunset, DayBoundary.nightfall]) {
    testWidgets('home switches to the new working date at $boundary',
        (tester) async {
      final rule = DayStart(boundary: boundary);
      final change = HebrewClock.boundaryOn(yesterday, rule)!;
      var now = change.subtract(const Duration(seconds: 30)).toLocal();
      final old =
          record(change.subtract(const Duration(hours: 2)).toLocal(), rule);
      await openHome(tester, AppTheme.klaf, () => now, rule, [old]);
      expect(
          snapshot(tester, AppTheme.klaf).hebrewDate, contains('08.11.2026'));
      expect(snapshot(tester, AppTheme.klaf).todayOutput, '31 שורות');

      now = change.toLocal();
      await tester.pump(const Duration(minutes: 1));
      final current = snapshot(tester, AppTheme.klaf);
      expect(current.hebrewDate, contains('09.11.2026'));
      expect(current.todayOutput, '0 שורות');
    });
  }

  test('journal dates are literal, while clock moments use the boundary', () {
    final old = record(yesterday.add(const Duration(hours: 18)), twoAm);
    final early =
        record(today.add(const Duration(minutes: 30)), twoAm, id: 'early');
    final newWork =
        record(today.add(const Duration(hours: 9)), twoAm, id: 'new');
    final all = [old, early, newWork];
    expect(WritingJournalLogic.sessionsOnDay(all, today, twoAm), [newWork]);
    expect(
        WritingJournalLogic.sessionsOnDay(all, yesterday, twoAm), [old, early]);
    expect(DateLogic.sessionIsOnDay(early, today, twoAm), isTrue);
    expect(DateLogic.sessionIsFiledOnDate(early, today, twoAm), isFalse);
  });

  testWidgets('summary opens on the working date and shows that day’s rows',
      (tester) async {
    // Pick a boundary after the current hour, except in the last hour of the
    // day. This exercises the rule without depending on the test host's time.
    final now = DateTime.now();
    final rule = DayStart(
        boundary: DayBoundary.fixedHour,
        hour: now.hour < 23 ? now.hour + 1 : 2);
    final day = DateLogic.effectiveDate(now, rule);
    final start = DateTime(day.year, day.month, day.day, rule.hour);
    final selected = record(start, rule);
    final previous =
        record(CalendarDays.addDaysKeepingTime(start, -1), rule, id: 'previous')
            .copyWith(endLine: 7, description: '7 שורות');
    StorageService.demoStore = MemoryStore({
      'day_start': jsonEncode(rule.toJson()),
    });
    await tester.pumpWidget(host(
        tester,
        AppTheme.klaf,
        SummaryScreen(
          projects: [project],
          history: [selected, previous],
          useGregorianDates: true,
          onHistoryUpdated: (_) {},
        )));
    await tester.pumpAndSettle();
    expect(find.text(formatDisplayDate(day, true)), findsOneWidget);
    expect(find.textContaining('31 שורות'), findsWidgets);
    expect(find.textContaining('7 שורות'), findsNothing);
    await tester.tap(find.byTooltip('עריכת רשומות'));
    await tester.pumpAndSettle();
    expect(find.textContaining('31 שורות'), findsWidgets);
    expect(find.textContaining('7 שורות'), findsNothing);
  });
}
