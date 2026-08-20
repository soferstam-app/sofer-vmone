// A month laid out day by day.
//
// Asked for by a sofer in his own words: someone who sets himself a page a day
// and is holding at page ten should see, on a calendar, which page he is meant
// to be writing each day. And: on Fridays and Motzei Shabbat he makes up what
// he missed, so it should say what he has to catch up to by the weekend.
//
// The second half falls out of the first. A plan stated as a cumulative
// position — "by the end of this day, be at page fourteen" — already answers
// what has to be made up. A plan stated as "write two pages today" would leave
// the writer to add it up himself, on exactly the day he is already behind.

import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/logic/production_plan.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const dayStart = DayStart.midnight;
  var seq = 0;

  // Iyar 5786 — an ordinary month, with no festivals to complicate the sums.
  final iyar = JewishDate.initDate(
      jewishYear: 5786, jewishMonth: JewishDate.IYAR, jewishDayOfMonth: 1);
  final firstOfIyar = iyar.getGregorianCalendar();

  DateTime hebrew(int day) => JewishDate.initDate(
          jewishYear: 5786, jewishMonth: JewishDate.IYAR, jewishDayOfMonth: day)
      .getGregorianCalendar();

  Project project({int targetDaily = 1, bool inLines = false}) => Project(
        id: 'p',
        name: 'ספר',
        type: ProjectType.sefer,
        price: 100,
        expenses: 0,
        targetDaily: targetDaily,
        targetMonthly: 0,
        dailyGoalInLines: inLines,
        linesPerPage: 10,
        totalPages: 245,
      );

  /// A full page written on [day].
  WorkSession page(int pageNumber, DateTime day) => WorkSession(
        id: 'w${seq++}',
        projectId: 'p',
        startTime: DateTime(day.year, day.month, day.day, 9),
        endTime: DateTime(day.year, day.month, day.day, 12),
        amount: pageNumber,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
        linesPerPageAtEntry: 10,
      );

  ProductionPlan plan({
    Project? p,
    List<WorkSession> history = const [],
    DateTime? now,
    WorkCalendarRules? rules,
    Map<DateTime, double> overrides = const {},
  }) =>
      ProductionPlan.forMonth(
        project: p ?? project(),
        history: history,
        anyDayInMonth: firstOfIyar,
        rules: rules ?? WorkCalendarRules.standard,
        dayStart: dayStart,
        overrides: overrides,
        now: now ?? hebrew(1),
      );

  group('the shape of the month', () {
    test('covers every day of the Hebrew month, in order', () {
      final p = plan();
      expect(p.days, hasLength(iyar.getDaysInJewishMonth()));
      expect(p.days.first.hebrewDay, 1);
      expect(p.days.last.hebrewDay, iyar.getDaysInJewishMonth());
    });

    test('Shabbat asks for nothing', () {
      final saturdays =
          plan().days.where((d) => d.date.weekday == DateTime.saturday);
      expect(saturdays, isNotEmpty);
      for (final d in saturdays) {
        expect(d.isWorkingDay, isFalse);
        expect(d.closedReason, NonWorkReason.shabbat);
      }
    });

    test('a day off does not advance the target', () {
      final days = plan().days;
      for (var i = 1; i < days.length; i++) {
        if (!days[i].isWorkingDay) {
          expect(days[i].plannedTarget, days[i - 1].plannedTarget,
              reason: 'a day nobody writes on cannot move the line');
        }
      }
    });
  });

  group('a page a day, holding at page ten', () {
    // The writer's own example.
    final history = [for (var i = 1; i <= 10; i++) page(i, hebrew(1))];

    test('the month opens from where he already is', () {
      // Written on the first, so it is not "before the month": the opening is
      // zero and the first day's actual is ten.
      final p = plan(history: history, now: hebrew(1));
      expect(p.openingUnits, 0);
      expect(p.days.first.actual, 10);
    });

    test('each working day asks for one more page than the last', () {
      final working = plan().workingDays.toList();
      for (var i = 1; i < working.length; i++) {
        expect(working[i].plannedTarget - working[i - 1].plannedTarget,
            closeTo(1, 0.001));
      }
    });

    test('a goal set in lines is stated in pages, which is what he writes on',
        () {
      // Fifteen lines a day on a ten-line page is a page and a half.
      expect(ProductionPlan.dailyUnits(project(targetDaily: 15, inLines: true)),
          closeTo(1.5, 0.001));
    });
  });

  group('a half day counts as a half', () {
    test('Friday asks for half of what a full day does', () {
      final rules = WorkCalendarRules.standard.copyWith(friday: DayWeight.half);
      final days = plan(rules: rules).days;
      final friday = days.firstWhere((d) => d.date.weekday == DateTime.friday);
      final index = days.indexOf(friday);

      expect(friday.isHalfDay, isTrue);
      expect(friday.plannedTarget - days[index - 1].plannedTarget,
          closeTo(0.5, 0.001));
    });
  });

  group('falling behind', () {
    test('a day that fell short of its line is marked', () {
      // Ten days in, and only three pages written.
      final history = [for (var i = 1; i <= 3; i++) page(i, hebrew(2))];
      final p = plan(history: history, now: hebrew(10));

      final tenth = p.days.firstWhere((d) => d.hebrewDay == 10);
      expect(tenth.isBehind, isTrue);
      expect(p.behindBy, isNotNull);
      expect(p.behindBy, greaterThan(0));
    });

    test('a day still to come is never marked behind', () {
      final p = plan(now: hebrew(2));
      for (final d in p.days.where((d) => d.isFuture)) {
        expect(d.isBehind, isFalse);
        expect(d.actual, isNull, reason: 'nothing is known about it yet');
      }
    });

    test('keeping up is not being behind', () {
      final history = [for (var i = 1; i <= 20; i++) page(i, hebrew(1))];
      expect(plan(history: history, now: hebrew(3)).behindBy, isNull);
    });
  });

  group('the catching up is spread over the days that are left', () {
    // Ten days in, three pages written where the line wanted more.
    final history = [for (var i = 1; i <= 3; i++) page(i, hebrew(2))];

    test('the days ahead ask for more than the original line did', () {
      final p = plan(history: history, now: hebrew(10));
      final ahead = p.days.where((d) => d.isFuture && d.isWorkingDay).toList();

      // Each future working day's own step is larger than a plain daily
      // target, because the shortfall has been shared out across them.
      expect(ahead[1].adjustedTarget - ahead[0].adjustedTarget,
          greaterThan(ProductionPlan.dailyUnits(project())));
    });

    test('and the month still ends where it always meant to', () {
      // The whole point of spreading rather than forgiving: the target does
      // not quietly shrink to whatever the writer managed.
      final p = plan(history: history, now: hebrew(10));
      expect(p.days.last.adjustedTarget, closeTo(p.closingTarget, 0.001));
    });

    test('a past day keeps the line it was actually judged against', () {
      // Otherwise the shortfall disappears the moment it is made up for, and
      // the calendar stops being a record of what happened.
      final p = plan(history: history, now: hebrew(10));
      for (final d in p.days.where((d) => !d.isFuture && !d.isToday)) {
        expect(d.adjustedTarget, d.plannedTarget);
      }
    });

    test('being ahead flattens the days to come', () {
      // The step shrinks, not the target. A cumulative target *below* where the
      // writer already stands would read as "by Thursday, be at page eight" to
      // someone holding at page twenty-five.
      final ahead = [for (var i = 1; i <= 25; i++) page(i, hebrew(2))];
      final p = plan(history: ahead, now: hebrew(10));
      final future = p.days.where((d) => d.isFuture && d.isWorkingDay).toList();

      final step = future[1].adjustedTarget - future[0].adjustedTarget;
      expect(step, lessThan(ProductionPlan.dailyUnits(project())));
    });

    test('and never asks for less than what is already written', () {
      // The invariant that keeps the whole thing sane, in both directions.
      for (final history in [
        [for (var i = 1; i <= 25; i++) page(i, hebrew(2))],
        [for (var i = 1; i <= 3; i++) page(i, hebrew(2))],
      ]) {
        final p = plan(history: history, now: hebrew(10));
        for (final d in p.days.where((d) => d.isFuture)) {
          expect(d.adjustedTarget, greaterThanOrEqualTo(p.actualNow - 0.001));
        }
      }
    });
  });

  group('a commission with no daily target', () {
    test('plans nothing rather than planning zero', () {
      final p = plan(p: project(targetDaily: 0));
      expect(p.closingTarget, p.openingUnits);
      expect(p.behindBy, isNull, reason: 'nothing to fall short of');
    });
  });

  group('a week is the same question over fewer days', () {
    test('runs Sunday to Shabbat, whichever day it is asked about', () {
      // The Hebrew week begins on Sunday, and a week beginning on Monday would
      // cut in half exactly the weekend this writer catches up on.
      for (var offset = 0; offset < 7; offset++) {
        final asked = hebrew(8).add(Duration(days: offset));
        final week = ProductionPlan.forWeek(
          project: project(),
          history: const [],
          anyDayInWeek: asked,
          rules: WorkCalendarRules.standard,
          dayStart: dayStart,
          now: hebrew(1),
        );
        expect(week.days, hasLength(7));
        expect(week.from.weekday % 7, 0, reason: 'Sunday');
        expect(week.to.weekday, DateTime.saturday);
      }
    });

    test('opens from where the writer already was', () {
      // Twelve pages written before the week began: the week plans from twelve,
      // not from zero.
      final history = [for (var i = 1; i <= 12; i++) page(i, hebrew(1))];
      final week = ProductionPlan.forWeek(
        project: project(),
        history: history,
        anyDayInWeek: hebrew(15),
        rules: WorkCalendarRules.standard,
        dayStart: dayStart,
        now: hebrew(15),
      );
      expect(week.openingUnits, 12);
      expect(week.closingTarget, greaterThan(12));
    });

    test('and asks for the same daily step a month does', () {
      final week = ProductionPlan.forWeek(
        project: project(),
        history: const [],
        anyDayInWeek: hebrew(8),
        rules: WorkCalendarRules.standard,
        dayStart: dayStart,
        now: hebrew(1),
      );
      final working = week.workingDays.toList();
      for (var i = 1; i < working.length; i++) {
        expect(working[i].plannedTarget - working[i - 1].plannedTarget,
            closeTo(1, 0.001));
      }
    });
  });

  group('the writer overrules the calendar', () {
    // "If I decide I am not writing on a given day, the whole table should
    // shift." The rules know about Shabbat; they do not know about a wedding.
    DateTime workingDay(ProductionPlan p) =>
        p.days.firstWhere((d) => d.isWorkingDay && d.hebrewDay > 3).date;

    test('taking a day off moves everything after it', () {
      final before = plan();
      final off = workingDay(before);
      final after = plan(overrides: {off: 0});

      final beforeEnd = before.days.last.plannedTarget;
      final afterEnd = after.days.last.plannedTarget;
      expect(afterEnd, closeTo(beforeEnd - 1, 0.001),
          reason: 'one working day less is one page less over the stretch');

      final dayAfter = after.days.firstWhere((d) => d.date.isAfter(off) && d.isWorkingDay);
      final sameBefore =
          before.days.firstWhere((d) => d.date == dayAfter.date);
      expect(dayAfter.plannedTarget, lessThan(sameBefore.plannedTarget));
    });

    test('and the day itself asks for nothing', () {
      final off = workingDay(plan());
      final p = plan(overrides: {off: 0});
      final day = p.days.firstWhere((d) => d.date == off);
      expect(day.isWorkingDay, isFalse);
      expect(day.isOverridden, isTrue);
    });

    test('working a day the calendar closed is allowed too', () {
      // A sofer who writes on a fast day the rules treat as closed.
      final closed = plan().days.firstWhere((d) => !d.isWorkingDay);
      final p = plan(overrides: {closed.date: 1});
      final day = p.days.firstWhere((d) => d.date == closed.date);
      expect(day.isWorkingDay, isTrue);
      expect(day.isOverridden, isTrue);
    });

    test('an override that agrees with the calendar is not a change', () {
      final open = plan().days.firstWhere((d) => d.weight == 1);
      final p = plan(overrides: {open.date: 1});
      expect(p.days.firstWhere((d) => d.date == open.date).isOverridden, isFalse);
    });

    test('a half day can be set by hand', () {
      final open = plan().days.firstWhere((d) => d.weight == 1 && d.hebrewDay > 3);
      final p = plan(overrides: {open.date: 0.5});
      final day = p.days.firstWhere((d) => d.date == open.date);
      expect(day.isHalfDay, isTrue);
    });
  });
}
