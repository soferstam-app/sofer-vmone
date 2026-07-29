/// Single source of truth for "which day does this belong to".
///
/// A sofer who works past midnight still considers it the same working day.
/// The "day rollover hour" setting lets them say when a new day starts, e.g.
/// 02:00 — so writing at 01:00 counts towards the previous day.
///
/// Before this file the rule was applied in only two of the places that group
/// by day, so the home screen could show one date while the daily summary
/// filed the same session under another.
class DateLogic {
  const DateLogic._();

  /// The working day [moment] belongs to, given [rolloverHour] (0–23).
  ///
  /// Returns a date at midnight. With rolloverHour 0 this is simply the
  /// calendar date, which is the default behaviour.
  static DateTime effectiveDate(DateTime moment, int rolloverHour) {
    final date = DateTime(moment.year, moment.month, moment.day);
    if (rolloverHour > 0 && moment.hour < rolloverHour) {
      return date.subtract(const Duration(days: 1));
    }
    return date;
  }

  /// Whether [moment] falls on the working day [day], honouring the rollover.
  static bool isSameWorkingDay(DateTime moment, DateTime day, int rolloverHour) {
    final a = effectiveDate(moment, rolloverHour);
    final b = effectiveDate(day, rolloverHour);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Whether [moment] falls in the same calendar month as [month], after the
  /// rollover has been applied.
  ///
  /// This matters at a month boundary: work at 01:00 on the 1st belongs to the
  /// last day of the previous month when the rollover is set past that hour.
  static bool isSameWorkingMonth(
      DateTime moment, DateTime month, int rolloverHour) {
    final a = effectiveDate(moment, rolloverHour);
    return a.year == month.year && a.month == month.month;
  }
}
