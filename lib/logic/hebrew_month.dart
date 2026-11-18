import 'package:kosher_dart/kosher_dart.dart';

import 'calendar_days.dart';

/// The first day of the Hebrew month [offset] months from [date].
/// Walking across actual month boundaries includes both Adars in leap years
/// and changes the year at Tishrei, even though months are numbered from Nisan.
DateTime shiftHebrewMonth(DateTime date, int offset) {
  var month = JewishDate.fromDateTime(date);
  month.setJewishDayOfMonth(1);
  for (var i = 0; i < offset.abs(); i++) {
    final next = CalendarDays.addDays(month.getGregorianCalendar(),
        offset > 0 ? month.getDaysInJewishMonth() : -1);
    month = JewishDate.fromDateTime(next)..setJewishDayOfMonth(1);
  }
  return CalendarDays.midnight(month.getGregorianCalendar());
}
