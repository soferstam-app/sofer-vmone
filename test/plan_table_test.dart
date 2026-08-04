// The plan as rows and columns, before anything decides how to draw it.
//
// A PDF, a spreadsheet and a printed page are three renderings of one table.
// Building it once means they cannot drift apart, and it means the thing worth
// checking — what each cell actually says — can be checked without rendering
// anything at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/logic/plan_table.dart';
import 'package:sofer_vmone/logic/production_plan.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const dayStart = DayStart.midnight;
  var seq = 0;

  DateTime hebrew(int day) => JewishDate.initDate(
          jewishYear: 5786, jewishMonth: JewishDate.IYAR, jewishDayOfMonth: day)
      .getGregorianCalendar();

  final project = Project(
    id: 'p',
    name: 'ספר תורה למשפחת כהן',
    type: ProjectType.sefer,
    price: 100,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 10,
  );

  WorkSession page(int n, DateTime day) => WorkSession(
        id: 'w${seq++}',
        projectId: 'p',
        startTime: DateTime(day.year, day.month, day.day, 9),
        endTime: DateTime(day.year, day.month, day.day, 12),
        amount: n,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
        linesPerPageAtEntry: 10,
      );

  PlanTable table({
    List<WorkSession> history = const [],
    DateTime? now,
    Map<DateTime, double> overrides = const {},
    bool gregorian = false,
  }) {
    final plan = ProductionPlan.forMonth(
      project: project,
      history: history,
      anyDayInMonth: hebrew(1),
      rules: WorkCalendarRules.standard,
      dayStart: dayStart,
      overrides: overrides,
      now: now ?? hebrew(1),
    );
    return PlanTable.of(
      project: project,
      plan: plan,
      periodLabel: 'אייר תשפ״ו',
      useGregorianDates: gregorian,
    );
  }

  group('what the table says', () {
    test('is titled with the commission and the stretch', () {
      expect(table().title, contains('ספר תורה למשפחת כהן'));
      expect(table().title, contains('אייר תשפ״ו'));
    });

    test('has a row for every day', () {
      expect(table().rows, hasLength(29));
    });

    test('a working day carries the position to reach', () {
      final row = table().rows.firstWhere((r) => r.isWorkingDay);
      expect(row.target, startsWith('עמוד'));
    });

    test('a day off says why, instead of a number', () {
      // "Shabbat" is the useful thing to print there; a page number would be
      // an instruction to write on it.
      final row = table().rows.firstWhere((r) => !r.isWorkingDay);
      expect(row.target, 'שבת');
    });

    test('a day still to come leaves the actual column blank', () {
      // Which is where the writer fills it in by hand — half the point of
      // printing a sheet at all.
      final row = table(now: hebrew(1)).rows.last;
      expect(row.actual, isEmpty);
    });

    test('a day gone by carries what was actually reached', () {
      final rows = table(history: [page(1, hebrew(1))], now: hebrew(3)).rows;
      // Hebrew numerals carry a geresh: the first page is א׳, not א.
      expect(rows.first.actual, startsWith('עמוד א'));
    });
  });

  group('both calendars are on the page', () {
    test('Hebrew first by default, with the Gregorian date beside it', () {
      // The sofer reads one; whoever else looks at the sheet reads the other.
      expect(table().rows.first.day, matches(RegExp(r'^\S+ \(\d+/\d+\)$')));
    });

    test('and the other way round when he works in Gregorian dates', () {
      expect(table(gregorian: true).rows.first.day,
          matches(RegExp(r'^\d+/\d+ \(\S+\)$')));
    });
  });

  group('a day the writer overruled', () {
    test('is marked as such', () {
      // Chosen from the plan rather than picked out of the air: overriding a
      // day that was already Shabbat changes nothing and tests nothing.
      final open = table().rows.firstWhere((r) => r.isWorkingDay);
      final rows = table(overrides: {open.date: 0}).rows;
      final row = rows.firstWhere((r) => r.date == open.date);

      expect(row.isOverridden, isTrue);
      expect(row.isWorkingDay, isFalse);
      expect(row.target, isNot(startsWith('עמוד')),
          reason: 'a day he is not writing gets no page number');
    });
  });

  group('as a spreadsheet', () {
    test('opens with a byte order mark, or Excel mangles the Hebrew', () {
      // Every "the export is broken" report about a CSV turns out to be this.
      expect(table().toCsv().codeUnitAt(0), 0xFEFF);
    });

    test('has a heading row and one line per day', () {
      final lines = table().toCsv().split('\r\n');
      expect(lines[1], contains('תאריך'));
      expect(lines[1], contains('להגיע עד'));
      // title, headings, 29 days, a blank, the summary
      expect(lines.where((l) => l.isNotEmpty), hasLength(32));
    });

    test('quotes a cell that contains a comma', () {
      // Otherwise one comma in a project name shifts every column after it.
      final wide = Project(
        id: 'p',
        name: 'ספר, מזוזות ותפילין',
        type: ProjectType.sefer,
        price: 1,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 1,
        linesPerPage: 10,
      );
      final t = PlanTable.of(
        project: wide,
        plan: ProductionPlan.forMonth(
          project: wide,
          history: const [],
          anyDayInMonth: hebrew(1),
          rules: WorkCalendarRules.standard,
          dayStart: dayStart,
          now: hebrew(1),
        ),
        periodLabel: 'אייר',
        useGregorianDates: false,
      );
      expect(t.toCsv(), contains('"ספר, מזוזות ותפילין · אייר"'));
    });

    test('ends with the closing line', () {
      expect(table().toCsv(), contains('עד הסוף'));
    });
  });

  group('the closing line', () {
    test('says where the stretch ends up', () {
      expect(table().summary, contains('עד הסוף: עמוד'));
    });

    test('and names a shortfall when there is one', () {
      final t = table(history: [page(1, hebrew(2))], now: hebrew(10));
      expect(t.summary, contains('פיגור'));
    });
  });
}
