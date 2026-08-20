// How a duration reads on screen.
//
// Five private copies of these lived in the screens, and one of them counted in
// Hebrew as though Hebrew counted like English: "1 שעות ו-1 דקות", and "0 שעות"
// for three quarters of an hour. Nothing on the way to the screen would have
// caught it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/format.dart';
import 'package:sofer_vmone/logic/currency.dart';

void main() {
  group('money', () {
    test('rounds to the shekel where agorot are noise', () {
      expect(formatMoney(1234.56, Currency.ils), '₪1235');
      expect(formatMoney(0, Currency.ils), '₪0');
    });

    test('keeps the agorot where they have to reconcile', () {
      expect(formatMoneyExact(1234.5, Currency.ils), '₪1234.50');
      expect(formatMoneyExact(0.07, Currency.ils), '₪0.07');
    });

    test('the symbol is written in one place', () {
      // The whole reason these exist. Forty-five call sites had it typed out,
      // and the day a writer abroad wants another currency, this is the file
      // that changes.
      expect(formatMoney(1, Currency.ils), startsWith('₪'));
      expect(formatMoneyExact(1, Currency.ils), startsWith('₪'));
    });
  });

  group('as a clock', () {
    test('pads to two digits', () {
      expect(formatClock(const Duration(hours: 1, minutes: 4, seconds: 9)),
          '01:04:09');
    });

    test('drops the seconds when asked', () {
      expect(
          formatClock(const Duration(hours: 1, minutes: 14, seconds: 32),
              seconds: false),
          '01:14');
    });

    test('does not wrap the hours at a day', () {
      // A commission is measured in tens of hours, and 06:12 for thirty of them
      // would be a shorter answer and a false one.
      expect(formatClock(const Duration(hours: 30, minutes: 12)), '30:12:00');
    });

    test('nothing reads as nothing', () {
      expect(formatClock(Duration.zero), '00:00:00');
      expect(formatClock(Duration.zero, seconds: false), '00:00');
    });
  });

  group('as a passing mention', () {
    test('hours and minutes', () {
      expect(formatSpan(const Duration(hours: 1, minutes: 14)), "1 שע' 14 דק'");
    });

    test('a whole number of hours drops the minutes', () {
      expect(formatSpan(const Duration(hours: 2)), "2 שע'");
    });

    test('under an hour is minutes alone', () {
      expect(formatSpan(const Duration(minutes: 45)), "45 דק'");
    });
  });

  group('spelled out', () {
    test('one is not "1"', () {
      expect(formatSpanLong(const Duration(hours: 1)), 'שעה');
      expect(formatSpanLong(const Duration(minutes: 1)), 'דקה');
    });

    test('two is neither "2" nor a plural', () {
      // Hebrew has a dual. "2 שעות" is what a program writes and nobody says.
      expect(formatSpanLong(const Duration(hours: 2)), 'שעתיים');
      expect(formatSpanLong(const Duration(minutes: 2)), 'שתי דקות');
    });

    test('three and up take the numeral', () {
      expect(formatSpanLong(const Duration(hours: 3)), '3 שעות');
      expect(formatSpanLong(const Duration(minutes: 45)), '45 דקות');
    });

    test('the vav is hyphenated onto a numeral, joined onto a word', () {
      expect(formatSpanLong(const Duration(hours: 1, minutes: 14)),
          'שעה ו-14 דקות');
      expect(formatSpanLong(const Duration(hours: 2, minutes: 2)),
          'שעתיים ושתי דקות');
      expect(formatSpanLong(const Duration(hours: 3, minutes: 1)),
          '3 שעות ודקה');
    });

    test('an empty half is left out, not printed as zero', () {
      // What the old copy did instead: "0 שעות ו-45 דקות" for three quarters of
      // an hour, and "3 שעות ו-0 דקות" for three of them.
      expect(formatSpanLong(const Duration(minutes: 45)), isNot(contains('0 שעות')));
      expect(formatSpanLong(const Duration(hours: 3)), isNot(contains('דקות')));
    });

    test('seconds are not nothing', () {
      // A sitting that was measured and came to seconds must not read the same
      // as one that was never measured at all.
      expect(formatSpanLong(const Duration(seconds: 40)), 'פחות מדקה');
      expect(formatSpanLong(Duration.zero), 'אין זמן');
    });
  });
}
