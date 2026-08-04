// A month day by day, to print and look at away from the screen.
//
// The figures existed one at a time on the monthly summary. Nothing had laid
// them beside each other, which is where a writer sees that his Sundays are
// twice his Thursdays.

import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/monthly_report.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const dayStart = DayStart.midnight;
  var seq = 0;

  DateTime hebrew(int day) => JewishDate.initDate(
          jewishYear: 5786, jewishMonth: JewishDate.IYAR, jewishDayOfMonth: day)
      .getGregorianCalendar();

  final iyar = JewishDate.fromDateTime(hebrew(1));

  Project project({String id = 'p', double price = 100, double cost = 0}) =>
      Project(
        id: id,
        name: 'ספר',
        type: ProjectType.sefer,
        price: price,
        expenses: cost,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: 10,
      );

  /// A sitting on [day] that wrote [lines] lines in [minutes].
  WorkSession sitting(
    int day, {
    int lines = 10,
    int minutes = 60,
    bool timeRecorded = true,
    String projectId = 'p',
    bool backlog = false,
  }) {
    final d = hebrew(day);
    final start = DateTime(d.year, d.month, d.day, 9);
    return WorkSession(
      id: 'w${seq++}',
      projectId: projectId,
      startTime: start,
      endTime: start.add(Duration(minutes: timeRecorded ? minutes : 0)),
      amount: 1,
      startLine: 1,
      endLine: lines,
      description: '',
      isManual: true,
      timeRecorded: timeRecorded,
      backlogOnly: backlog,
      linesPerPageAtEntry: 10,
    );
  }

  MonthlyReport report(List<WorkSession> history,
          {Project? only, List<Project>? projects}) =>
      MonthlyReport.forMonth(
        project: only ?? project(),
        history: history,
        projects: projects ?? [project()],
        anyDayInMonth: hebrew(1),
        dayStart: dayStart,
      );

  group('the shape of the month', () {
    test('a row for every Hebrew day', () {
      expect(report(const []).days, hasLength(iyar.getDaysInJewishMonth()));
    });

    test('days with no work are present and empty', () {
      // Present, because a printed month with holes in it reads as data lost.
      final r = report([sitting(3)]);
      expect(r.days.where((d) => d.hasWork), hasLength(1));
      expect(r.days.firstWhere((d) => d.hebrewDay == 4).hasWork, isFalse);
    });
  });

  group('what a day comes to', () {
    test('lines, time and sittings', () {
      final r = report([sitting(3, lines: 10, minutes: 60)]);
      final day = r.days.firstWhere((d) => d.hebrewDay == 3);

      expect(day.lines, 10);
      expect(day.worked, const Duration(minutes: 60));
      expect(day.sittings, 1);
      expect(day.minutesPerLine, closeTo(6, 0.01));
    });

    test('two sittings in a day are counted as two', () {
      // Two hours in one go and two hours in six pieces are different days.
      final r = report([sitting(3), sitting(3)]);
      expect(r.days.firstWhere((d) => d.hebrewDay == 3).sittings, 2);
    });

    test('earnings are the price of what was written', () {
      // One page of ten lines on a ten-line page, at 100 less 30 of materials.
      final r = report(
        [sitting(3, lines: 10)],
        only: project(price: 100, cost: 30),
        projects: [project(price: 100, cost: 30)],
      );
      expect(
          r.days
              .firstWhere((d) => d.hebrewDay == 3)
              .earned
              .single(Currency.ils)!
              .amount,
          closeTo(70, 0.01));
    });
  });

  group('time that was never measured', () {
    test('is left out of the average rather than counted as zero', () {
      // Counting it would report the writer as faster than he is — the one
      // direction an average must never be wrong in.
      final r = report([
        sitting(3, lines: 10, minutes: 60),
        sitting(3, lines: 10, timeRecorded: false),
      ]);
      final day = r.days.firstWhere((d) => d.hebrewDay == 3);

      expect(day.lines, 20, reason: 'the output still counts');
      expect(day.worked, const Duration(minutes: 60));
      expect(day.minutesPerLine, closeTo(3, 0.01));
    });

    test('a day with no time at all has no average', () {
      final r = report([sitting(3, timeRecorded: false)]);
      expect(r.days.firstWhere((d) => d.hebrewDay == 3).minutesPerLine, isNull);
    });
  });

  group('the month as a whole', () {
    test('totals its days', () {
      final r = report([sitting(3), sitting(5), sitting(7)]);
      expect(r.totalLines, 30);
      expect(r.totalTime, const Duration(hours: 3));
    });

    test('the average comes from the totals, not from averaging averages', () {
      // Averaging daily averages weights a day of one line the same as a day of
      // forty, which is how a single slow morning ruins a good month.
      final r = report([
        sitting(3, lines: 40, minutes: 40),
        sitting(4, lines: 1, minutes: 20),
      ]);
      // 60 minutes over 41 lines.
      expect(r.minutesPerLine, closeTo(60 / 41, 0.01));
    });

    test('backlog work is left out entirely', () {
      expect(report([sitting(3, backlog: true)]).totalLines, 0);
    });
  });

  group('as a table', () {
    test('has a row per day and a total at the foot', () {
      final t = report([sitting(3)]).toExportTable(
          currency: Currency.ils, useGregorianDates: false);

      expect(t.rows, hasLength(iyar.getDaysInJewishMonth() + 1));
      expect(t.rows.last.cells.first, 'סה״כ');
      expect(t.rows.last.strong, isTrue);
    });

    test('names the commission and the month', () {
      final t = report(const []).toExportTable(
          currency: Currency.ils, useGregorianDates: false);
      expect(t.title, contains('ספר'));
    });

    test('a day with no work is muted and blank, not zeroed', () {
      // A column of zeros reads as "I wrote nothing", which is a claim. A blank
      // is the absence of one.
      final t = report([sitting(3)]).toExportTable(
          currency: Currency.ils, useGregorianDates: false);
      final idle = t.rows[3];
      expect(idle.muted, isTrue);
      expect(idle.cells[2], isEmpty);
    });

    test('says why a figure may be missing', () {
      final t = report(const []).toExportTable(
          currency: Currency.ils, useGregorianDates: false);
      expect(t.note, contains('בלי זמן'));
    });

    test('and survives being turned into a spreadsheet', () {
      final csv = report([sitting(3)])
          .toExportTable(currency: Currency.ils, useGregorianDates: false)
          .toCsv();
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('דק׳ לשורה'));
    });
  });

  group('across several commissions', () {
    test('all of them together when none is named', () {
      final a = project(id: 'a');
      final b = project(id: 'b');
      final r = MonthlyReport.forMonth(
        project: null,
        history: [
          sitting(3, projectId: 'a'),
          sitting(3, projectId: 'b'),
        ],
        projects: [a, b],
        anyDayInMonth: hebrew(1),
        dayStart: dayStart,
      );
      expect(r.totalLines, 20);
      expect(r.days.firstWhere((d) => d.hebrewDay == 3).sittings, 2);
    });
  });
}
