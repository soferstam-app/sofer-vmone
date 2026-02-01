import 'package:kosher_dart/kosher_dart.dart';

double workDayValue(DateTime date, bool fridayMotzeiHalfDay) {
  final jc = JewishCalendar.fromDateTime(date);
  if (jc.isAssurBemelacha()) return 0;
  final dow = jc.getDayOfWeek(); // 1=Sun .. 7=Sat
  if (dow == JewishDate.saturday) return fridayMotzeiHalfDay ? 0.5 : 0;
  if (dow == JewishDate.friday) return fridayMotzeiHalfDay ? 0.5 : 1;
  return 1;
}

double countWorkDays(DateTime start, DateTime end, bool fridayMotzeiHalfDay) {
  double sum = 0;
  for (DateTime d = DateTime(start.year, start.month, start.day);
      !d.isAfter(DateTime(end.year, end.month, end.day));
      d = d.add(const Duration(days: 1))) {
    sum += workDayValue(d, fridayMotzeiHalfDay);
  }
  return sum;
}

DateTime estimatedCompletionDate({
  required DateTime fromDate,
  required double remainingWorkUnits,
  required double workUnitsPerDay,
  required bool fridayMotzeiHalfDay,
}) {
  if (remainingWorkUnits <= 0 || workUnitsPerDay <= 0) return fromDate;
  double accumulated = 0;
  DateTime d = DateTime(fromDate.year, fromDate.month, fromDate.day);
  while (accumulated < remainingWorkUnits) {
    accumulated += workDayValue(d, fridayMotzeiHalfDay) * workUnitsPerDay;
    if (accumulated >= remainingWorkUnits) break;
    d = d.add(const Duration(days: 1));
  }
  return d;
}

double workDaysNeeded(
  double remainingWorkUnits,
  double workUnitsPerDay,
) {
  if (workUnitsPerDay <= 0) return 0;
  return remainingWorkUnits / workUnitsPerDay;
}
