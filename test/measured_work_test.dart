// One rule, held across every screen that states a rate.
//
// A quantity counts every record. A ratio with time in it counts only records
// that carried time — on both sides. Seven places each decided this separately
// and several got it wrong the same way: they summed time from measured records
// and divided it by all the output, so a writer who records what he wrote but
// not how long it took came out faster and better paid than anything measured
// said. Always flattering, and never visible on screen.
//
// The contract test is the point of this file: adding untimed output must not
// move a measured rate. If a future screen computes one its own way, this is
// what fails.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/measured_work.dart';
import 'package:sofer_vmone/logic/monthly_report.dart';
import 'package:sofer_vmone/logic/project_analytics.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  final sefer = Project(
    id: 'p1',
    name: 'ספר תורה',
    type: ProjectType.sefer,
    price: 100,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 10,
    totalPages: 245,
  );

  WorkSession sitting({
    required int lines,
    int minutes = 0,
    bool timeRecorded = true,
    int day = 3,
  }) {
    final start = DateTime(2026, 5, day, 9);
    return WorkSession(
      id: 'session-$day-$lines-$minutes-$timeRecorded',
      projectId: 'p1',
      startTime: start,
      endTime: start.add(Duration(minutes: minutes)),
      amount: 1,
      startLine: 1,
      endLine: lines,
      linesPerPageAtEntry: 10,
      description: '',
      isManual: true,
      timeRecorded: timeRecorded,
      workingDateAtEntry: DateTime(2026, 5, day),
    );
  }

  group('which records a rate may use', () {
    test('one without time is refused', () {
      expect(MeasuredWork.countsForTime(sitting(lines: 10, timeRecorded: false)),
          isFalse);
    });

    test('so is one whose length is zero', () {
      expect(MeasuredWork.countsForTime(sitting(lines: 10, minutes: 0)), isFalse);
    });

    test('a measured one is not', () {
      expect(
          MeasuredWork.countsForTime(sitting(lines: 10, minutes: 60)), isTrue);
    });

    test('and the time it sums is only theirs', () {
      final all = [
        sitting(lines: 10, minutes: 60),
        sitting(lines: 10, timeRecorded: false),
      ];
      expect(MeasuredWork.time(all), const Duration(minutes: 60));
      expect(MeasuredWork.only(all), hasLength(1));
      expect(MeasuredWork.anyUntimed(all), isTrue);
    });
  });

  group('the contract: untimed output never moves a measured rate', () {
    // Ten lines in an hour is six minutes a line. Adding ten more lines that
    // nobody timed does not make him twice as fast.
    final measuredOnly = [sitting(lines: 10, minutes: 60)];
    final plusUntimed = [
      sitting(lines: 10, minutes: 60),
      sitting(lines: 10, timeRecorded: false, day: 4),
    ];

    MonthlyReport report(List<WorkSession> history) => MonthlyReport.forMonth(
          project: sefer,
          history: history,
          projects: [sefer],
          anyDayInMonth: DateTime(2026, 5, 3),
          dayStart: DayStart.midnight,
        );

    test('the monthly report keeps six minutes a line', () {
      expect(report(measuredOnly).minutesPerLine, closeTo(6, 0.01));
      expect(report(plusUntimed).minutesPerLine, closeTo(6, 0.01));
    });

    test('and still counts every line in the total', () {
      expect(report(plusUntimed).totalLines, 20);
      expect(report(plusUntimed).totalMeasuredLines, 10);
      expect(report(plusUntimed).someWorkUntimed, isTrue);
    });

    test('the profitability ranking keeps its pay per hour', () {
      final before = ProjectAnalytics.measure(sefer, measuredOnly);
      final after = ProjectAnalytics.measure(sefer, plusUntimed);
      expect(after.profitPerHour, closeTo(before.profitPerHour!, 0.01));
    });

    test('and its time per unit', () {
      final before = ProjectAnalytics.measure(sefer, measuredOnly);
      final after = ProjectAnalytics.measure(sefer, plusUntimed);
      expect(after.timePerUnit, before.timePerUnit);
    });

    test('while the units it reports still count everything', () {
      expect(ProjectAnalytics.measure(sefer, plusUntimed).units,
          greaterThan(ProjectAnalytics.measure(sefer, measuredOnly).units));
    });
  });

  group('a length that cannot be right', () {
    test('a negative one is left out rather than subtracted', () {
      // A record written before the midnight-crossing fix can hold one, and
      // subtracting it would report less time than was actually spent.
      final backwards = WorkSession(
        id: 'bad',
        projectId: 'p1',
        startTime: DateTime(2026, 5, 3, 12),
        endTime: DateTime(2026, 5, 3, 11),
        amount: 1,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
      );
      expect(MeasuredWork.countsForTime(backwards), isFalse);
      expect(MeasuredWork.time([sitting(lines: 10, minutes: 60), backwards]),
          const Duration(minutes: 60));
    });
  });

  group('what still counts everything', () {
    test('earnings, which are a quantity and not a rate', () {
      final r = MonthlyReport.forMonth(
        project: sefer,
        history: [
          sitting(lines: 10, minutes: 60),
          sitting(lines: 10, timeRecorded: false, day: 4),
        ],
        projects: [sefer],
        anyDayInMonth: DateTime(2026, 5, 3),
        dayStart: DayStart.midnight,
      );
      // Twenty lines of a ten-line page at 100 a page.
      expect(r.earned.single(Currency.ils)!.amount, closeTo(200, 0.01));
    });
  });
}
