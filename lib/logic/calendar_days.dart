/// Counting days as a calendar counts them, not as a clock does.
///
/// A day is not twenty-four hours. Israel puts the clocks forward on the Friday
/// before the last Sunday in March and back on the last Sunday in October, so
/// twice a year there is a day of twenty-three hours and a day of twenty-five.
/// Every other day of the year the difference does not show, which is exactly
/// why it survives being written the wrong way.
///
/// `date.add(const Duration(days: 1))` adds twenty-four hours of absolute time.
/// On an ordinary day that lands on the next midnight; across a transition it
/// lands at 01:00, or at 23:00 **on the day before the one that was meant**.
/// And `to.difference(from).inDays` truncates, so a range that lost an hour
/// comes out a day short.
///
/// The failures this produced were all of the same shape — quiet, seasonal, and
/// impossible to reproduce in the other ten months:
///
/// * a monthly plan that was missing its last day every March;
/// * a plan whose days went off by one every October, so the Hebrew date and
///   the Gregorian date beside it stopped agreeing;
/// * two days of one week handed the same notification id, so one of the seven
///   silently had no reminder;
/// * work written at 01:30 on the night of the change, by a writer whose day
///   turns over at 02:00, filed two days back instead of one.
///
/// Building a `DateTime` from its fields never does any of this: the
/// constructor takes a wall-clock date and gives back that date. It also
/// normalises out-of-range values, so day 32 of March is the 1st of April and
/// day 0 is the last of February — which is what makes [addDays] safe to use
/// with any offset at all.
class CalendarDays {
  const CalendarDays._();

  /// Midnight on the calendar date of [d].
  static DateTime midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// [days] calendar days after [d], at midnight. Negative counts go back.
  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// [days] calendar days after [d], keeping the wall-clock time of day.
  ///
  /// What "the same hour tomorrow" means to a person, which is not what adding
  /// twenty-four hours means to a clock.
  static DateTime addDaysKeepingTime(DateTime d, int days) => DateTime(
      d.year, d.month, d.day + days, d.hour, d.minute, d.second, d.millisecond);

  /// Whole calendar days from [from] to [to], ignoring the time of day.
  ///
  /// Counted in UTC, where every day really is twenty-four hours, so the answer
  /// is the number of dates crossed and never one fewer.
  static int between(DateTime from, DateTime to) =>
      _utcMidnight(to).difference(_utcMidnight(from)).inDays;

  /// Dates from [from] to [to] inclusive, counted as a calendar counts them.
  /// Zero when [to] is before [from].
  static int inclusiveLength(DateTime from, DateTime to) {
    final n = between(from, to);
    return n < 0 ? 0 : n + 1;
  }

  /// A day number that increases by exactly one per calendar day, for anything
  /// that needs days to be countable — a ring of ids, a modulo, a difference.
  static int dayNumber(DateTime d) =>
      _utcMidnight(d).difference(DateTime.utc(1970)).inDays;

  /// The same calendar date, read as UTC. UTC has no daylight saving, so
  /// subtracting two of these gives whole days every time.
  static DateTime _utcMidnight(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}
