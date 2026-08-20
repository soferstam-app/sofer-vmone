// Which month a monthly summary is a summary of.
//
// A sofer picks his month in a Hebrew picker — "אב תשפ״ו" — and the summary
// then gathered whichever *Gregorian* month that day happened to land in. A
// summary of Av showed a mixture of Tammuz, Av and Elul: neither the month
// asked for nor any other. Writers reported it as the monthly summary showing
// the wrong work, which is precisely what it was doing.
//
// It also disagreed with itself. The working days a monthly target is measured
// against were already counted over the Hebrew month, so the output and the
// target were spans up to a fortnight apart.

import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:sofer_vmone/logic/date_logic.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const dayStart = DayStart.midnight;
  var seq = 0;

  WorkSession on(DateTime day) => WorkSession(
        id: 'w${seq++}',
        projectId: 'p',
        startTime: DateTime(day.year, day.month, day.day, 9),
        endTime: DateTime(day.year, day.month, day.day, 11),
        amount: 1,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
      );

  /// The Gregorian date of a Hebrew day, so the tests read in the calendar the
  /// app actually works in.
  DateTime hebrew(int year, int month, int day) =>
      JewishDate.initDate(jewishYear: year, jewishMonth: month, jewishDayOfMonth: day)
          .getGregorianCalendar();

  bool inMonth(WorkSession s, DateTime month) =>
      DateLogic.sessionIsInMonth(s, month, dayStart);

  group('a Hebrew month gathers its own days', () {
    // Av 5786: 1 Av is 25 July 2026, 29 Av is 22 August 2026. So the month
    // straddles two Gregorian months, which is the whole point.
    final firstOfAv = hebrew(5786, JewishDate.AV, 1);
    final lastOfAv = hebrew(5786, JewishDate.AV, 29);

    test('the first day of the month is in it', () {
      expect(inMonth(on(firstOfAv), firstOfAv), isTrue);
    });

    test('and so is the last, though it is a different Gregorian month', () {
      expect(lastOfAv.month, isNot(firstOfAv.month),
          reason: 'the test is pointless if Av does not straddle two');
      expect(inMonth(on(lastOfAv), firstOfAv), isTrue);
    });

    test('the day before the month is not in it', () {
      final lastOfTammuz = hebrew(5786, JewishDate.TAMMUZ, 29);
      expect(inMonth(on(lastOfTammuz), firstOfAv), isFalse);
    });

    test('nor the day after', () {
      final firstOfElul = hebrew(5786, JewishDate.ELUL, 1);
      expect(inMonth(on(firstOfElul), firstOfAv), isFalse);
    });

    test('the same Hebrew month of another year is a different month', () {
      expect(inMonth(on(hebrew(5785, JewishDate.AV, 1)), firstOfAv), isFalse);
    });
  });

  group('what the old rule got wrong', () {
    test('a Gregorian neighbour is no longer swept in', () {
      // 1 Av 5786 falls in July. Under the old rule every July session counted
      // as Av, including the days of Tammuz that share the month.
      final firstOfAv = hebrew(5786, JewishDate.AV, 1);
      final tammuzInTheSameGregorianMonth =
          hebrew(5786, JewishDate.TAMMUZ, 20);

      expect(tammuzInTheSameGregorianMonth.month, firstOfAv.month,
          reason: 'the two share a Gregorian month, which is what misled it');
      expect(inMonth(on(tammuzInTheSameGregorianMonth), firstOfAv), isFalse);
    });
  });

  group('the day of the month a chart is indexed by', () {
    test('is the Hebrew one', () {
      final tenthOfAv = hebrew(5786, JewishDate.AV, 10);
      expect(DateLogic.hebrewDayOfMonth(on(tenthOfAv), dayStart), 10);
    });

    test('and follows the working day, not the clock', () {
      // Written at half past midnight, counted as the previous day by a writer
      // whose day turns over at 02:00 — the bar belongs on the day he was
      // working, not the day the clock had reached.
      final tenthOfAv = hebrew(5786, JewishDate.AV, 10);
      final pastMidnight = WorkSession(
        id: 'late',
        projectId: 'p',
        startTime: DateTime(tenthOfAv.year, tenthOfAv.month, tenthOfAv.day + 1, 0, 30),
        endTime: DateTime(tenthOfAv.year, tenthOfAv.month, tenthOfAv.day + 1, 1, 30),
        amount: 1,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
        dayRule: const DayStart(boundary: DayBoundary.fixedHour, hour: 2),
      );
      expect(DateLogic.hebrewDayOfMonth(pastMidnight, dayStart), 10);
    });
  });
}
