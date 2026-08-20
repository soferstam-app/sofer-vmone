// Which day a reminder is about, and which day gets cancelled.
//
// Two faults, both of which silence a reminder for a day the writer wanted one
// — the exact failure the whole book-each-day-separately design exists to
// prevent, arrived at from a different direction.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/calendar_days.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/reminder_plan.dart';
import 'package:sofer_vmone/logic/reminder_schedule.dart';

void main() {
  group('once the hour has passed, the next booking is tomorrow', () {
    // The scheduler used to treat the first booking as today's whatever day it
    // landed on. Once the hour is gone the first booking is tomorrow's, so
    // meeting the target in the evening dropped *tomorrow's* reminder and the
    // day after arrived carrying a message about a day already over.
    final evening = DateTime(2026, 5, 4, 21);
    final when = ReminderSchedule.upcoming(from: evening, hour: 8, minute: 0);

    test('the first moment is not today', () {
      expect(when.first.day, 5);
      expect(CalendarDays.between(evening, when.first), 1);
    });

    test('so the working day it belongs to is not today either', () {
      const dayStart = DayStart();
      final today = ReminderPlan.workingDay(evening, dayStart);
      final first = ReminderPlan.workingDay(when.first, dayStart);
      expect(first, isNot(today),
          reason: 'treating it as today drops tomorrow instead');
    });

    test('and today is still today when the hour is yet to come', () {
      const dayStart = DayStart();
      final morning = DateTime(2026, 5, 4, 6);
      final soon = ReminderSchedule.upcoming(from: morning, hour: 8, minute: 0);
      expect(ReminderPlan.workingDay(soon.first, dayStart),
          ReminderPlan.workingDay(morning, dayStart));
    });
  });

  group('cancelling uses the writer\'s day, not the calendar\'s', () {
    // A sofer whose day turns over at 02:00, finishing at half past midnight.
    const rule = DayStart(boundary: DayBoundary.fixedHour, hour: 2);
    final afterMidnight = DateTime(2026, 5, 5, 0, 30);

    test('the working day is still the fourth', () {
      expect(ReminderPlan.workingDay(afterMidnight, rule), DateTime(2026, 5, 4));
    });

    test('and its id is not the new calendar day\'s', () {
      // Cancelling by DateTime.now() would drop the reminder for the fifth --
      // a day he has not started -- and leave the fourth's standing.
      final byWorkingDay =
          ReminderSchedule.idFor(ReminderPlan.workingDay(afterMidnight, rule));
      final byCalendar = ReminderSchedule.idFor(afterMidnight);
      expect(byWorkingDay, isNot(byCalendar));
    });

    test('while a midnight boundary leaves the two the same', () {
      const plain = DayStart();
      expect(
        ReminderSchedule.idFor(ReminderPlan.workingDay(afterMidnight, plain)),
        ReminderSchedule.idFor(afterMidnight),
      );
    });
  });
}
