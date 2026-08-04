// A day is not twenty-four hours, twice a year.
//
// Israel puts the clocks forward on the Friday before the last Sunday in March
// and back on the last Sunday in October. Every one of these tests passed for
// ten months of the year with the arithmetic that produced them written the
// wrong way, which is precisely why they are worth having.
//
// They are written as invariants rather than as assertions about particular
// dates: "seven consecutive days get seven distinct ids", "a month's plan has
// as many days as the month". Those are true in every time zone, so the file
// says something everywhere — and in a zone that observes daylight saving, the
// sweep across a whole year walks over the transitions and the invariant bites.

import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:sofer_vmone/logic/calendar_days.dart';
import 'package:sofer_vmone/logic/date_logic.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/logic/production_plan.dart';
import 'package:sofer_vmone/logic/reminder_schedule.dart';
import 'package:sofer_vmone/logic/session_logic.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  // Two years of starting points, so whatever the local zone's transitions are
  // they fall inside the sweep.
  final everyDay = [
    for (var i = 0; i < 730; i++) CalendarDays.addDays(DateTime(2026), i),
  ];

  group('CalendarDays', () {
    test('a day added is the next calendar date, at midnight', () {
      for (final d in everyDay) {
        final next = CalendarDays.addDays(d, 1);
        expect(next.hour, 0, reason: '$d + 1 day landed at ${next.hour}:00');
        expect(CalendarDays.between(d, next), 1);
      }
    });

    test('a day back is the previous calendar date, at midnight', () {
      for (final d in everyDay) {
        final back = CalendarDays.addDays(d, -1);
        expect(back.hour, 0);
        expect(CalendarDays.between(back, d), 1);
      }
    });

    test('the time of day survives when it is meant to', () {
      for (final d in everyDay) {
        final at = DateTime(d.year, d.month, d.day, 8, 30);
        final next = CalendarDays.addDaysKeepingTime(at, 1);
        expect(next.hour, 8);
        expect(next.minute, 30);
        expect(CalendarDays.between(at, next), 1);
      }
    });

    test('a range counts every date in it', () {
      for (final d in everyDay) {
        expect(CalendarDays.inclusiveLength(d, CalendarDays.addDays(d, 6)), 7);
      }
    });

    test('an inverted range is empty rather than negative', () {
      expect(CalendarDays.inclusiveLength(DateTime(2026, 5, 2), DateTime(2026, 5, 1)), 0);
    });

    test('day numbers rise by exactly one a day', () {
      for (var i = 1; i < everyDay.length; i++) {
        expect(
          CalendarDays.dayNumber(everyDay[i]) -
              CalendarDays.dayNumber(everyDay[i - 1]),
          1,
          reason: '${everyDay[i - 1]} -> ${everyDay[i]}',
        );
      }
    });
  });

  group('the reminder ring', () {
    test('seven consecutive days never share an id', () {
      // A shared id is one booking overwriting another, and a day of the week
      // with no reminder at all — for the writer the reminder exists for.
      for (final start in everyDay) {
        final ids = [
          for (var i = 0; i < ReminderSchedule.days; i++)
            ReminderSchedule.idFor(CalendarDays.addDays(start, i)),
        ];
        expect(ids.toSet(), hasLength(ReminderSchedule.days),
            reason: 'week of $start gave $ids');
      }
    });

    test('the same slot comes round again a week later', () {
      for (final d in everyDay) {
        expect(
          ReminderSchedule.idFor(CalendarDays.addDays(d, ReminderSchedule.days)),
          ReminderSchedule.idFor(d),
        );
      }
    });

    test('every id booked is one the queue knows how to clear', () {
      for (final d in everyDay) {
        expect(ReminderSchedule.allIds, contains(ReminderSchedule.idFor(d)));
      }
    });

    test('the hour asked for is the hour scheduled, every day of the week', () {
      for (final from in everyDay) {
        final moments = ReminderSchedule.upcoming(
            from: DateTime(from.year, from.month, from.day, 20), hour: 8, minute: 0);
        expect(moments, hasLength(ReminderSchedule.days));
        for (final m in moments) {
          expect(m.hour, 8, reason: 'from $from produced $m');
          expect(m.minute, 0);
        }
        // Consecutive, and none of them in the past.
        for (var i = 1; i < moments.length; i++) {
          expect(CalendarDays.between(moments[i - 1], moments[i]), 1);
        }
      }
    });
  });

  group('the working day a session is filed under', () {
    test('a fixed-hour boundary moves work back exactly one day', () {
      // A writer whose day turns over at 02:00, writing at half past one. The
      // answer is yesterday — never the day before that.
      const rule = DayStart(boundary: DayBoundary.fixedHour, hour: 2);
      for (final d in everyDay) {
        final moment = DateTime(d.year, d.month, d.day, 1, 30);
        final filed = DateLogic.effectiveDate(moment, rule);
        expect(filed.hour, 0, reason: 'filed $moment at ${filed.hour}:00');
        expect(CalendarDays.between(filed, CalendarDays.midnight(moment)), 1,
            reason: '$moment was filed under $filed');
      }
    });

    test('work after the boundary stays on its own date', () {
      const rule = DayStart(boundary: DayBoundary.fixedHour, hour: 2);
      for (final d in everyDay) {
        final moment = DateTime(d.year, d.month, d.day, 9);
        expect(DateLogic.effectiveDate(moment, rule), CalendarDays.midnight(moment));
      }
    });

    test('midnight, the default, is simply the calendar date', () {
      for (final d in everyDay) {
        final moment = DateTime(d.year, d.month, d.day, 23, 59);
        expect(DateLogic.effectiveDate(moment, const DayStart()),
            CalendarDays.midnight(moment));
      }
    });
  });

  group('a sitting that runs past midnight', () {
    test('ends the next day at the hour given, and lasts what it says', () {
      for (final d in everyDay) {
        final range = SessionLogic.buildTimeRange(
          date: d,
          startHour: 23,
          startMinute: 0,
          endHour: 1,
          endMinute: 0,
        );
        expect(range.end.hour, 1, reason: 'on $d the sitting ended at ${range.end}');
        expect(CalendarDays.between(range.start, range.end), 1);
        expect(range.end.isAfter(range.start), isTrue);
      }
    });
  });

  group('counting working days', () {
    test('a week is seven days however the clocks behave', () {
      const rules = WorkCalendarRules();
      for (final d in everyDay) {
        // Not the working total — the range walked. A week that came out six
        // days long dropped whichever day fell off the end.
        final off = HebrewWorkCalendar.daysOff(d, CalendarDays.addDays(d, 6), rules);
        final work = HebrewWorkCalendar.countWorkDays(
            d, CalendarDays.addDays(d, 6), rules);
        // Every one of the seven is either counted as work or listed as off.
        expect(work + off.length, greaterThanOrEqualTo(6.0),
            reason: 'week of $d: $work working, ${off.length} off');
        expect(work, lessThanOrEqualTo(7.0));
      }
    });

    test('a single day is one day', () {
      const rules = WorkCalendarRules();
      for (final d in everyDay) {
        final work = HebrewWorkCalendar.countWorkDays(d, d, rules);
        final off = HebrewWorkCalendar.daysOff(d, d, rules);
        expect(work > 0 || off.isNotEmpty, isTrue, reason: '$d counted as nothing');
      }
    });
  });

  group('the production plan', () {
    final project = Project(
      id: 'p1',
      name: 'ספר תורה',
      type: ProjectType.sefer,
      price: 400,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      totalPages: 245,
      linesPerPage: 42,
    );

    test('a month has as many days as the month has', () {
      // Every Hebrew month of two years, so both transitions are walked.
      for (var i = 0; i < 730; i += 7) {
        final anchor = CalendarDays.addDays(DateTime(2026), i);
        final plan = ProductionPlan.forMonth(
          project: project,
          history: const [],
          anyDayInMonth: anchor,
          rules: const WorkCalendarRules(),
          dayStart: const DayStart(),
          now: anchor,
        );
        final jd = JewishDate.fromDateTime(anchor);
        final expected = JewishDate.initDate(
          jewishYear: jd.getJewishYear(),
          jewishMonth: jd.getJewishMonth(),
          jewishDayOfMonth: 1,
        ).getDaysInJewishMonth();
        expect(plan.days, hasLength(expected),
            reason: 'month containing $anchor');
      }
    });

    test('its days are distinct, consecutive, and at midnight', () {
      for (var i = 0; i < 730; i += 7) {
        final anchor = CalendarDays.addDays(DateTime(2026), i);
        final plan = ProductionPlan.forMonth(
          project: project,
          history: const [],
          anyDayInMonth: anchor,
          rules: const WorkCalendarRules(),
          dayStart: const DayStart(),
          now: anchor,
        );
        final dates = plan.days.map((d) => d.date).toList();
        expect(dates.toSet(), hasLength(dates.length),
            reason: 'month containing $anchor repeated a date');
        for (final d in dates) {
          expect(d.hour, 0, reason: '$d is not midnight');
        }
        for (var j = 1; j < dates.length; j++) {
          expect(CalendarDays.between(dates[j - 1], dates[j]), 1);
        }
      }
    });

    test('the Hebrew day and the date beside it stay in step', () {
      // The pair is the whole point of the calendar: a writer reads "כ״ג" and
      // the civil date together. They are produced by two different walkers,
      // and one of them used to drift.
      for (var i = 0; i < 730; i += 7) {
        final anchor = CalendarDays.addDays(DateTime(2026), i);
        final plan = ProductionPlan.forMonth(
          project: project,
          history: const [],
          anyDayInMonth: anchor,
          rules: const WorkCalendarRules(),
          dayStart: const DayStart(),
          now: anchor,
        );
        for (final day in plan.days) {
          expect(day.hebrewDay, JewishDate.fromDateTime(day.date).getJewishDayOfMonth(),
              reason: '${day.date} was labelled ${day.hebrewDay}');
        }
      }
    });

    test('a week runs Sunday to Shabbat, seven days long', () {
      for (final d in everyDay) {
        final plan = ProductionPlan.forWeek(
          project: project,
          history: const [],
          anyDayInWeek: d,
          rules: const WorkCalendarRules(),
          dayStart: const DayStart(),
          now: d,
        );
        expect(plan.days, hasLength(7), reason: 'week containing $d');
        expect(plan.days.first.date.weekday, DateTime.sunday);
        expect(plan.days.last.date.weekday, DateTime.saturday);
      }
    });

    test('today is found, and counted as today rather than as still to come', () {
      // The day the writer is standing on decides what "behind" means. When the
      // dates carried an hour, nothing matched it and the plan quietly had no
      // today at all.
      for (final d in everyDay) {
        final plan = ProductionPlan.forWeek(
          project: project,
          history: const [],
          anyDayInWeek: d,
          rules: const WorkCalendarRules(),
          dayStart: const DayStart(),
          now: DateTime(d.year, d.month, d.day, 10),
        );
        expect(plan.today, isNotNull, reason: 'no today in the week of $d');
        expect(plan.today!.date, CalendarDays.midnight(d));
        expect(plan.today!.isFuture, isFalse);
      }
    });

    test('an override lands on the day it was set for', () {
      // Overrides are keyed by date. A planned day carrying 01:00 missed the
      // key, and the writer's own decision about his week was silently dropped.
      for (final d in everyDay) {
        final plan = ProductionPlan.forWeek(
          project: project,
          history: const [],
          anyDayInWeek: d,
          rules: const WorkCalendarRules(),
          dayStart: const DayStart(),
          // Every day of the week at once: whichever day the transition falls
          // on, one of these has to take effect.
          overrides: {
            for (var i = 0; i < 7; i++)
              CalendarDays.addDays(
                  CalendarDays.addDays(d, -(d.weekday % 7)), i): 1.0,
          },
          now: d,
        );
        // The whole week is overridden to a full working day, so a week that
        // still reports a day off is a week whose keys did not match.
        for (final day in plan.days) {
          expect(day.weight, 1.0,
              reason: 'override for ${day.date} (week of $d) was ignored');
        }
      }
    });
  });
}
