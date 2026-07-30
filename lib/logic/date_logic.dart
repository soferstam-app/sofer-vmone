import '../models.dart';
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
          return date.subtract(const Duration(days: 1));
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
            : date.add(const Duration(days: 1));
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
  /// Prefers the day frozen onto the session when it was entered. Deriving it
  /// afresh on every read would mean that a writer who moves his day boundary
  /// re-files all of his past work — but how a past day was reckoned is a fact
  /// about that day, not about today's setting.
  ///
  /// Sessions from before the snapshot existed fall back to deriving it, which
  /// is the old behaviour.
  static DateTime workingDateOf(WorkSession session, DayStart dayStart) =>
      session.workingDateAtEntry ?? effectiveDate(session.startTime, dayStart);

  /// Whether [session] was filed under the working day containing [day].
  static bool sessionIsOnDay(
      WorkSession session, DateTime day, DayStart dayStart) {
    final a = workingDateOf(session, dayStart);
    final b = effectiveDate(day, dayStart);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Whether [session] was filed under a day in the same month as [month].
  static bool sessionIsInMonth(
      WorkSession session, DateTime month, DayStart dayStart) {
    final a = workingDateOf(session, dayStart);
    return a.year == month.year && a.month == month.month;
  }
}
