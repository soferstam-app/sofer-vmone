import 'package:kosher_dart/kosher_dart.dart';

import 'logic/hebrew_work_calendar.dart';

String formatDisplayDate(DateTime date, bool useGregorian) {
  if (useGregorian) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
  return formatHebrewDate(JewishDate.fromDateTime(date));
}

/// Formats a Hebrew date that has already been computed.
///
/// The completion-date arithmetic works in Hebrew days throughout and hands
/// back a [JewishDate]; formatting it directly avoids converting to Gregorian
/// and straight back again just to print it.
String formatHebrewDate(JewishDate date) {
  final formatter = HebrewDateFormatter()..hebrewFormat = true;
  return formatter.format(date);
}

const List<String> _weekdayNames = [
  'ראשון',
  'שני',
  'שלישי',
  'רביעי',
  'חמישי',
  'שישי',
  'שבת',
];

/// Day of week plus date, for a delivery date — "יום שלישי, כ״ג תמוז תשפ״ו".
///
/// Which day of the week a job lands on is the first thing a sofer checks,
/// so a bare date is less useful here than everywhere else.
String formatDisplayDateWithWeekday(DateTime date, bool useGregorian) {
  final jewishDate = JewishDate.fromDateTime(date);
  final weekday = _weekdayNames[jewishDate.getDayOfWeek() - 1];
  final prefix = jewishDate.getDayOfWeek() == JewishDate.saturday
      ? weekday
      : 'יום $weekday';
  return '$prefix, ${formatDisplayDate(date, useGregorian)}';
}

/// "שבתות (12) · חול המועד (6) · צומות (2)" — why a delivery date sits where
/// it does, longest cause first.
String formatSkippedDays(WorkPlan plan, {int maxReasons = 3}) {
  final entries = plan.skippedByImpact;
  if (entries.isEmpty) return '';

  final shown = entries.take(maxReasons).map((e) => '${e.key.label} (${e.value})');
  final rest = entries.length - maxReasons;
  return rest > 0 ? '${shown.join(' · ')} ועוד' : shown.join(' · ');
}

String formatDisplayDateMonth(DateTime date, bool useGregorian) {
  if (useGregorian) {
    return '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
  final jewishDate = JewishDate.fromDateTime(date);
  return '${getHebrewMonthName(jewishDate.getJewishMonth(), jewishDate.isJewishLeapYear())} ${formatHebrewYear(jewishDate.getJewishYear())}';
}

String formatHebrewYear(int year) {
  final formatter = HebrewDateFormatter()..hebrewFormat = true;
  final tempDate = JewishDate();
  tempDate.setJewishDate(year, 1, 1);
  return formatter.format(tempDate).split(' ').last;
}

String getHebrewMonthName(int monthIndex, bool isLeap) {
  const months = [
    "ניסן",
    "אייר",
    "סיון",
    "תמוז",
    "אב",
    "אלול",
    "תשרי",
    "חשון",
    "כסלו",
    "טבת",
    "שבט"
  ];
  if (monthIndex <= 6) return months[monthIndex - 1];
  if (monthIndex >= 7 && monthIndex <= 11) return months[monthIndex - 1];
  if (isLeap) {
    if (monthIndex == 12) return "אדר א'";
    if (monthIndex == 13) return "אדר ב'";
  } else {
    if (monthIndex == 12) return "אדר";
  }
  return "";
}

String formatHebrewNumber(int n) {
  if (n <= 0) return "";
  const letters = {
    1: 'א',
    2: 'ב',
    3: 'ג',
    4: 'ד',
    5: 'ה',
    6: 'ו',
    7: 'ז',
    8: 'ח',
    9: 'ט',
    10: 'י',
    20: 'כ',
    30: 'ל',
    40: 'מ',
    50: 'נ',
    60: 'ס',
    70: 'ע',
    80: 'פ',
    90: 'צ',
    100: 'ק',
    200: 'ר',
    300: 'ש',
    400: 'ת'
  };
  String hebrew = '';
  int num = n;
  if (num >= 1000) {
    hebrew += "${formatHebrewNumber(num ~/ 1000)}'";
    num %= 1000;
  }
  while (num >= 400) {
    hebrew += 'ת';
    num -= 400;
  }
  if (num >= 100) {
    hebrew += letters[(num ~/ 100) * 100]!;
    num %= 100;
  }
  if (num == 15) {
    hebrew += 'טו';
    num = 0;
  }
  if (num == 16) {
    hebrew += 'טז';
    num = 0;
  }
  if (num >= 10) {
    hebrew += letters[(num ~/ 10) * 10]!;
    num %= 10;
  }
  if (num > 0) hebrew += letters[num]!;
  if (hebrew.length == 1) hebrew += "'";
  return hebrew;
}

int parseHebrewPageToNumber(String input) {
  if (input.isEmpty) return 0;
  final trimmed = input.trim().replaceAll("'", "").replaceAll(" ", "");
  final asInt = int.tryParse(trimmed);
  if (asInt != null) return asInt;
  const letters = {
    'א': 1,
    'ב': 2,
    'ג': 3,
    'ד': 4,
    'ה': 5,
    'ו': 6,
    'ז': 7,
    'ח': 8,
    'ט': 9,
    'י': 10,
    'כ': 20,
    'ך': 20,
    'ל': 30,
    'מ': 40,
    'ם': 40,
    'נ': 50,
    'ן': 50,
    'ס': 60,
    'ע': 70,
    'פ': 80,
    'ף': 80,
    'צ': 90,
    'ץ': 90,
    'ק': 100,
    'ר': 200,
    'ש': 300,
    'ת': 400,
  };
  int n = 0;
  int i = 0;
  while (i < trimmed.length) {
    if (i + 1 < trimmed.length && trimmed[i] == 'ט' && trimmed[i + 1] == 'ו') {
      n += 15;
      i += 2;
      continue;
    }
    if (i + 1 < trimmed.length && trimmed[i] == 'ט' && trimmed[i + 1] == 'ז') {
      n += 16;
      i += 2;
      continue;
    }
    final v = letters[trimmed[i]];
    if (v != null) {
      n += v;
      i++;
    } else {
      i++;
    }
  }
  return n;
}
