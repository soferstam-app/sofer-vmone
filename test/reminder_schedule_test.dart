// When the daily reminder fires, and under which identifier.
//
// The reminder used to be one repeating notification. Meeting the day's goal
// cancelled it — and cancelling a repeat cancels every future occurrence, not
// today's. It was only set up again when the app was opened, so a writer who
// met their target and then did not open the app got no reminder the next day,
// nor any day after: the reminder turned itself off for exactly the person it
// exists for.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/reminder_schedule.dart';

void main() {
  List<DateTime> upcoming(DateTime from, {int hour = 20, int minute = 0}) =>
      ReminderSchedule.upcoming(from: from, hour: hour, minute: minute);

  group('when it fires', () {
    test('today, when the hour is still ahead', () {
      final when = upcoming(DateTime(2026, 8, 2, 9));
      expect(when.first, DateTime(2026, 8, 2, 20));
    });

    test('tomorrow, when it has already gone by', () {
      // Scheduling this morning's reminder at four in the afternoon either
      // fires it at once or drops it, and both are wrong.
      final when = upcoming(DateTime(2026, 8, 2, 22));
      expect(when.first, DateTime(2026, 8, 3, 20));
    });

    test('tomorrow, when it is exactly now', () {
      expect(upcoming(DateTime(2026, 8, 2, 20)).first, DateTime(2026, 8, 3, 20));
    });

    test('a whole week of them, one a day', () {
      final when = upcoming(DateTime(2026, 8, 2, 9));
      expect(when, hasLength(ReminderSchedule.days));
      for (var i = 1; i < when.length; i++) {
        expect(when[i].difference(when[i - 1]).inDays, 1);
      }
    });

    test('all at the hour that was set', () {
      for (final moment in upcoming(DateTime(2026, 8, 2, 9), hour: 6, minute: 45)) {
        expect(moment.hour, 6);
        expect(moment.minute, 45);
      }
    });

    test('crossing a month, and a year', () {
      expect(upcoming(DateTime(2026, 12, 30, 9)).last, DateTime(2027, 1, 5, 20));
    });
  });

  group('the identifiers', () {
    test('a week of them never collides', () {
      final ids = upcoming(DateTime(2026, 8, 2, 9))
          .map(ReminderSchedule.idFor)
          .toSet();
      expect(ids, hasLength(ReminderSchedule.days),
          reason: 'two days sharing an id means one silently replaces the other');
    });

    test('today can be found without a record of what was booked', () {
      // This is what "cancel today's, leave tomorrow's" rests on.
      final now = DateTime(2026, 8, 2, 21);
      final today = ReminderSchedule.idFor(now);
      expect(today, ReminderSchedule.idFor(DateTime(2026, 8, 2)));
      expect(today, isNot(ReminderSchedule.idFor(DateTime(2026, 8, 3))));
    });

    test('the time of day does not change which day it is', () {
      expect(ReminderSchedule.idFor(DateTime(2026, 8, 2, 0, 1)),
          ReminderSchedule.idFor(DateTime(2026, 8, 2, 23, 59)));
    });

    test('a slot is reused a week later, replacing the stale booking', () {
      expect(ReminderSchedule.idFor(DateTime(2026, 8, 2)),
          ReminderSchedule.idFor(DateTime(2026, 8, 9)));
    });

    test('every id the ring can hold is known, so it can be emptied', () {
      final all = ReminderSchedule.allIds.toSet();
      expect(all, hasLength(ReminderSchedule.days));
      for (final moment in upcoming(DateTime(2026, 8, 2, 9))) {
        expect(all, contains(ReminderSchedule.idFor(moment)));
      }
    });

    test('none of them is zero, which was the old repeating reminder', () {
      expect(ReminderSchedule.allIds, isNot(contains(0)));
    });
  });
}
