import 'package:kosher_dart/kosher_dart.dart';

import '../models.dart';
import 'calendar_days.dart';
import 'hebrew_clock.dart';

/// Single source of truth for "which day does this belong to".
///
/// A sofer who works past midnight still considers it the same working day; one
/// who works by the Hebrew calendar may want the day to turn over at nightfall,
/// as the Hebrew date itself does. [DayStart] holds that choice, and everything
/// that groups work by day goes through here.
///
/// Before this file the rule was applied in only two of the places that group
/// by day, so the home screen could show one date while the daily summary filed
/// the same session under another.
class DateLogic {
  const DateLogic._();

  /// The working day [moment] belongs to, given [dayStart].
  ///
  /// Returns a date at midnight. With the default (midnight) this is simply the
  /// calendar date.
  ///
  /// The two kinds of boundary run in opposite directions, which is why they are
  /// not one subtraction:
  ///
  /// * a morning boundary (02:00) means work before it belongs to *yesterday*;
  /// * an evening boundary (nightfall) means work after it belongs to
  ///   *tomorrow*, exactly as the Hebrew date does.
  static DateTime effectiveDate(DateTime moment, DayStart dayStart) {
    final date = DateTime(moment.year, moment.month, moment.day);

    switch (dayStart.boundary) {
      case DayBoundary.midnight:
        return date;

      case DayBoundary.fixedHour:
        if (dayStart.hour > 0 && moment.hour < dayStart.hour) {
          // A calendar day back, not twenty-four hours. Subtracting a Duration
          // here filed work written at 01:30 on the night the clocks go forward
          // under the day *before* yesterday — see [CalendarDays].
          return CalendarDays.addDays(date, -1);
        }
        return date;

      case DayBoundary.sunset:
      case DayBoundary.nightfall:
        final boundary = HebrewClock.boundaryOn(date, dayStart);
        // A location where the sun never sets would give null. It cannot happen
        // in Israel, but falling back to the calendar date is better than
        // throwing if the reference point ever changes.
        if (boundary == null) return date;
        return moment.isBefore(boundary)
            ? date
            : CalendarDays.addDays(date, 1);
    }
  }

  /// Whether [moment] falls on the working day [day].
  static bool isSameWorkingDay(
      DateTime moment, DateTime day, DayStart dayStart) {
    final a = effectiveDate(moment, dayStart);
    final b = effectiveDate(day, dayStart);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Whether [moment] falls in the same calendar month as [month], after the
  /// day boundary has been applied.
  ///
  /// This matters at a month boundary: work at 01:00 on the 1st belongs to the
  /// last day of the previous month when the boundary is set past that hour.
  static bool isSameWorkingMonth(
      DateTime moment, DateTime month, DayStart dayStart) {
    final a = effectiveDate(moment, dayStart);
    return a.year == month.year && a.month == month.month;
  }

  // -------------------------------------------------------------------------
  // Recorded sessions. Everything that groups history by day must go through
  // these three, never through `session.startTime` directly — the raw
  // timestamp is the clock time, not the day the work was filed under.
  // -------------------------------------------------------------------------

  /// The working day a recorded [session] belongs to.
  ///
  /// Applies the rule that was in force when the work was recorded, rather than
  /// today's. Both halves of that matter and they used to be in conflict:
  /// deriving with the current setting re-filed years of past work the moment a
  /// writer changed his boundary, and freezing the resulting day instead made a
  /// mistake in the sunset computation permanent. Freezing the *rule* and
  /// applying it now gives both — nothing moves when the setting changes, and
  /// everything moves when the computation is corrected.
  ///
  /// A session recorded before the rule was kept has the frozen day and nothing
  /// else, and that is exactly what it was counted under at the time. One older
  /// still has neither, and falls back to the current setting, which is the old
  /// behaviour and the best answer available for a record that never stated one.
  static DateTime workingDateOf(WorkSession session, DayStart dayStart) {
    final rule = session.dayRule;
    if (rule != null) return effectiveDate(session.startTime, rule);
    return session.workingDateAtEntry ??
        effectiveDate(session.startTime, dayStart);
  }

  /// Whether [session] was filed under the working day containing [day].
  static bool sessionIsOnDay(
      WorkSession session, DateTime day, DayStart dayStart) {
    final a = workingDateOf(session, dayStart);
    final b = effectiveDate(day, dayStart);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Whether [session] was filed under a day in the same month as [month].
  /// Whether a session falls in the same **Hebrew** month as [month].
  ///
  /// It used to compare Gregorian months, which is a different span. A sofer
  /// picks his month in a Hebrew picker — "אב תשפ״ו" — and the app then
  /// gathered whichever Gregorian month that day happened to land in, so a
  /// summary of Av showed a mixture of Tammuz, Av and Elul. It was neither the
  /// month asked for nor any other month, and to the writer it simply looked as
  /// though the monthly summary was showing the wrong work.
  ///
  /// Worse, it disagreed with itself: the working days a monthly target is
  /// measured against were already counted over the Hebrew month, so the output
  /// and the target were spans up to a fortnight apart.
  ///
  /// This is the rule the whole app is built on — the Hebrew calendar is the
  /// working representation, the Gregorian one is display.
  static bool sessionIsInMonth(
          WorkSession session, DateTime month, DayStart dayStart) =>
      sessionIsInHebrewMonth(session, JewishDate.fromDateTime(month), dayStart);

  /// The same test with the month already converted.
  ///
  /// Callers loop over the whole history, and the two-argument form converted
  /// the *month* again on every record — the same answer, recomputed once per
  /// session. A conversion is the expensive operation here, which is why the
  /// work-calendar walks days with `forward()` rather than converting each one.
  /// Two thousand records cost four thousand conversions where two thousand and
  /// one would do.
  static bool sessionIsInHebrewMonth(
      WorkSession session, JewishDate month, DayStart dayStart) {
    final a = JewishDate.fromDateTime(workingDateOf(session, dayStart));
    return a.getJewishYear() == month.getJewishYear() &&
        a.getJewishMonth() == month.getJewishMonth();
  }

  /// Which day of the Hebrew month a session was filed under, 1–30.
  ///
  /// What a chart of a month's days is indexed by, for the same reason.
  static int hebrewDayOfMonth(WorkSession session, DayStart dayStart) =>
      JewishDate.fromDateTime(workingDateOf(session, dayStart))
          .getJewishDayOfMonth();
}
