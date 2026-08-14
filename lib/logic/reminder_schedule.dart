import 'calendar_days.dart';

/// When the daily reminder should fire, and under which identifier.
///
/// The reminder used to be one repeating notification. Meeting the day's goal
/// cancelled it — and cancelling a repeat cancels every future occurrence, not
/// today's. It was only ever set up again when the app was opened, so a writer
/// who met their target and then did not open the app got no reminder the next
/// day, nor any day after. The reminder turned itself off for exactly the
/// person it exists for.
///
/// The fix is to stop using a repeat. Each day is scheduled on its own, so
/// today's can be dropped while tomorrow's stands. A week is topped up whenever
/// the app is opened or work is recorded, which is often enough that the queue
/// never runs dry for anyone who uses the app at all.
class ReminderSchedule {
  const ReminderSchedule._();

  /// How far ahead to schedule.
  ///
  /// Long enough that a week away from the app does not silence it, short
  /// enough that a changed setting takes effect within a week for everyone —
  /// including someone who never opens the app again after changing it.
  static const int days = 7;

  /// The moments to schedule, starting from the next one still to come.
  ///
  /// Today is included only if the hour has not already passed: scheduling a
  /// notification for this morning at four in the afternoon either fires it
  /// immediately or drops it, and both are wrong.
  static List<DateTime> upcoming({
    required DateTime from,
    required int hour,
    required int minute,
    int count = days,
  }) {
    var first = DateTime(from.year, from.month, from.day, hour, minute);
    if (!first.isAfter(from)) first = CalendarDays.addDaysKeepingTime(first, 1);

    return [
      for (var i = 0; i < count; i++)
        // Rebuilt from the date rather than added as 24 hours, so a daylight
        // saving change does not walk the reminder an hour along the week.
        DateTime(first.year, first.month, first.day + i, hour, minute),
    ];
  }

  /// The notification id for a given day.
  ///
  /// A ring of [days] ids derived from the date itself, so that "cancel
  /// today's" can be answered without keeping a record of what was scheduled —
  /// and so that next week's booking of the same slot replaces the stale one
  /// rather than piling up beside it.
  ///
  /// The whole ring depends on consecutive days getting consecutive numbers.
  /// Counted with `difference().inDays` on local time they did not: the week of
  /// a clock change contains a day of twenty-three hours, the subtraction
  /// truncates, and two of the seven days came out with the same id — so one
  /// day's booking overwrote another's and that day silently had no reminder.
  /// See [CalendarDays.dayNumber].
  static int idFor(DateTime day) => _base + CalendarDays.dayNumber(day) % days;

  /// Every id the ring can hold, for clearing the queue before refilling it.
  static List<int> get allIds =>
      [for (var i = 0; i < days; i++) _base + i];

  /// Above the ids used elsewhere; id 0 was the old repeating reminder.
  static const int _base = 100;
}
