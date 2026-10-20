import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/hebrew_utils.dart';
import 'package:sofer_vmone/logic/completion_estimator.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/logic/production_plan.dart';
import 'package:sofer_vmone/logic/quote_calculator.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    StorageService.demoStore = null;
    StorageService.onChanged = null;
  });
  final monday = DateTime(2026, 2, 2); // 15 Shevat 5786
  final tuesday = DateTime(2026, 2, 3);
  const off = WorkDayException(weight: DayWeight.none, note: 'חתונה');
  const half = WorkDayException(weight: DayWeight.half, note: 'שבע ברכות');
  final rules = WorkCalendarRules.standard.copyWith(exceptions: {
    WorkCalendarRules.dateKey(monday): off,
    WorkCalendarRules.dateKey(tuesday): half,
  });
  Project project({Map<DateTime, double> overrides = const {}}) => Project(
        id: 'p',
        name: 'ספר',
        type: ProjectType.sefer,
        price: 100,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        totalPages: 2,
        linesPerPage: 42,
        planOverrides: overrides,
      );
  WorkDay day(DateTime date, WorkCalendarRules settings, {double? override}) =>
      HebrewWorkCalendar.classify(
          HebrewWorkCalendar.hebrewDayOf(date, settings), settings,
          override: override);

  test('a wedding on 15 Shevat closes only the chosen year and date', () {
    final jd = JewishDate.fromDateTime(monday);
    expect((jd.getJewishYear(), jd.getJewishMonth(), jd.getJewishDayOfMonth()),
        (5786, 11, 15));
    expect(day(monday, rules).value, 0);
    expect(day(tuesday, rules).value, 0.5);
    expect(day(DateTime(2026, 2, 4), rules).value, 1);
    final nextYear = JewishDate.initDate(
            jewishYear: 5787, jewishMonth: 11, jewishDayOfMonth: 15)
        .getGregorianCalendar();
    expect(rules.exceptionOn(nextYear), isNull);
  });

  test('half-day exceptions never open days already closed by the calendar',
      () {
    for (final date in [DateTime(2026, 2, 7), DateTime(2026, 4, 2)]) {
      final settings =
          rules.copyWith(exceptions: {WorkCalendarRules.dateKey(date): half});
      expect(day(date, settings).value, 0);
      expect(day(date, settings).reason, isNot(NonWorkReason.personal));
    }
  });

  test('full project days cannot override personal availability', () {
    expect(day(monday, rules, override: 1).value, 0);
    expect(day(tuesday, rules, override: 1).value, 0.5);
    expect(day(tuesday, rules, override: 0).value, 0);
  });

  test('workday counts, next workday and completion use the same calendar', () {
    expect(
        HebrewWorkCalendar.countWorkDays(monday, DateTime(2026, 2, 5), rules),
        2.5);
    expect(
        WorkCalendarRules.dateKey(
            HebrewWorkCalendar.nextWorkDay(monday, rules)),
        '2026-02-03');
    final plan =
        HebrewWorkCalendar.plan(from: monday, workDaysNeeded: 2, rules: rules)!;
    expect(WorkCalendarRules.dateKey(plan.completionDate), '2026-02-05');
    expect(plan.skipped[NonWorkReason.personal], 1);
    expect(
        formatSkippedDays(plan, english: true), contains('Personal time off'));
    expect(
        HebrewWorkCalendar.daysOff(monday, tuesday, rules)
            .map((d) => d.day.value),
        [0, 0.5]);
  });

  test('forecasts and required pace include global and project exceptions', () {
    final p = project(overrides: {DateTime(2026, 2, 4): 0});
    final estimate = CompletionEstimator.estimate(
        project: p, history: [], rules: rules, from: monday)!;
    expect(
        WorkCalendarRules.dateKey(estimate.plan.completionDate), '2026-02-08');
    final pace = CompletionEstimator.paceRequiredFor(
        remainingUnits: 2,
        deadline: DateTime(2026, 2, 5),
        rules: rules,
        from: monday,
        overrides: p.planOverrides)!;
    expect(pace, closeTo(2 / 1.5, 0.0001));
  });

  test('a quote includes the personal day off without changing its price', () {
    final quote = QuoteCalculator.estimate(
        units: 2,
        timePerUnit: const Duration(hours: 1),
        targetHourlyRate: 100,
        hoursPerDay: 1,
        rules: rules,
        startingFrom: monday)!;
    expect(WorkCalendarRules.dateKey(quote.estimatedCompletion), '2026-02-05');
    expect(quote.suggestedPrice, 200);
  });

  test('the production plan respects personal caps and project overrides', () {
    final p =
        project(overrides: {monday: 1, tuesday: 1, DateTime(2026, 2, 4): 0});
    final plan = ProductionPlan.forRange(
        project: p,
        history: [],
        from: monday,
        to: DateTime(2026, 2, 5),
        rules: rules,
        dayStart: DayStart.midnight,
        overrides: p.planOverrides,
        now: monday);
    expect(plan.days.map((d) => d.weight), [0, 0.5, 0, 1]);
    expect(plan.closingTarget, 1.5);
    expect(plan.days.first.closedReason, NonWorkReason.personal);
  });

  test('storage round-trip and unrelated settings changes preserve notes', () {
    final restored =
        WorkCalendarRules.fromJson(jsonDecode(jsonEncode(rules.toJson())));
    expect(restored.exceptionOn(monday)!.note, 'חתונה');
    expect(restored.copyWith(inIsrael: false).exceptionOn(tuesday)!.weight,
        DayWeight.half);
    expect(
        WorkCalendarRules.fromJson({'schemaVersion': 2}).exceptions, isEmpty);
    expect(WorkCalendarRules.fromJson({}).exceptions, isEmpty);
  });

  test('malformed exceptions are ignored without losing valid entries', () {
    final restored = WorkCalendarRules.fromJson({
      'schemaVersion': 3,
      'exceptions': {
        '2026-02-02': off.toJson(),
        '2026-02-30': half.toJson(),
        '2026-02-03T00:00:00Z': off.toJson(),
        'no-date': off.toJson(),
        '2026-02-04': {'weight': 'full'},
        '2026-02-05': false,
      }
    });
    expect(restored.exceptions.keys, ['2026-02-02']);
  });

  test('saving and importing a backup preserves exact dates and notes',
      () async {
    StorageService.demoStore = MemoryStore({});
    var changes = 0;
    StorageService.onChanged = () async {
      changes++;
    };
    await StorageService().setWorkCalendarRules(rules);
    expect(changes, 1);
    final exported = await StorageService().exportAll();
    StorageService.demoStore = MemoryStore({});
    await StorageService().saveImportedSnapshot(
        projects: [],
        history: [],
        expenses: [],
        proofreads: [],
        payments: [],
        orders: [],
        lastPositions: {},
        settings: Map<String, dynamic>.from(exported['settings']));
    final restored = await StorageService().getWorkCalendarRules();
    expect(restored.toJson(), rules.toJson());
  });
}
