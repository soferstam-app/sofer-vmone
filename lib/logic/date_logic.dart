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
}
