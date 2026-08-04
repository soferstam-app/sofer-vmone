// How fast the writer actually writes, which decides when he is told he will
// finish.
//
// The divisor used to be every working day between his first session and his
// last. That is a different quantity and a far smaller one: a sofer who opened
// a commission in Tishrei, wrote a page, and started in earnest in Shevat had
// four idle months in it. His pace came out a fraction of the truth and his
// delivery date years away — which is what writers reported, in the words "I do
// not understand what these figures are".
//
// Days he did not write are not slow days. They say nothing about how fast he
// writes.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/completion_estimator.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  final rules = WorkCalendarRules.standard;
  var seq = 0;

  final project = Project(
    id: 'p',
    name: 'ספר',
    type: ProjectType.sefer,
    price: 100,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 10,
    totalPages: 245,
  );

  /// A full page written on [day].
  WorkSession page(DateTime day, {bool backlog = false, bool deleted = false}) =>
      WorkSession(
        id: 'w${seq++}',
        projectId: 'p',
        startTime: DateTime(day.year, day.month, day.day, 9),
        endTime: DateTime(day.year, day.month, day.day, 12),
        amount: 1,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
        backlogOnly: backlog,
        deletedAt: deleted ? DateTime(2027) : null,
        linesPerPageAtEntry: 10,
      );

  double? pace(List<WorkSession> history) =>
      CompletionEstimator.measuredPace(project, history, rules);

  group('pace is per day written', () {
    test('three pages over three days is a page a day', () {
      expect(
        pace([
          page(DateTime(2026, 7, 20)),
          page(DateTime(2026, 7, 21)),
          page(DateTime(2026, 7, 22)),
        ]),
        closeTo(1, 0.001),
      );
    });

    test('two pages in one day is two a day', () {
      expect(
        pace([page(DateTime(2026, 7, 20)), page(DateTime(2026, 7, 20))]),
        closeTo(2, 0.001),
      );
    });

    test('a long idle gap does not make him slow', () {
      // The failure that started this. One page in Tishrei, then real work
      // months later: the gap used to sit in the divisor.
      final withGap = [
        page(DateTime(2026, 1, 5)),
        for (var d = 1; d <= 5; d++) page(DateTime(2026, 7, d)),
      ];
      // Six pages over six days he wrote on.
      expect(pace(withGap), closeTo(1, 0.001));
    });

    test('and the same work without the gap measures the same', () {
      // Which is the point: the gap is not information about his hand.
      final tight = [for (var d = 1; d <= 6; d++) page(DateTime(2026, 7, d))];
      final gapped = [
        page(DateTime(2026, 1, 5)),
        for (var d = 1; d <= 5; d++) page(DateTime(2026, 7, d)),
      ];
      expect(pace(tight), closeTo(pace(gapped)!, 0.001));
    });
  });

  group('what a day is', () {
    test('two sittings either side of midnight are one day', () {
      // Otherwise anyone who writes late has his pace halved.
      final late = WorkSession(
        id: 'late',
        projectId: 'p',
        startTime: DateTime(2026, 7, 21, 0, 30),
        endTime: DateTime(2026, 7, 21, 1, 30),
        amount: 1,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
        linesPerPageAtEntry: 10,
        dayRule: const DayStart(boundary: DayBoundary.fixedHour, hour: 2),
      );
      // Both filed under the 20th: one page in the evening, one after midnight.
      expect(pace([page(DateTime(2026, 7, 20)), late]), closeTo(2, 0.001));
    });
  });

  group('what is left out of the measure', () {
    test('backlog work, which carries no timing', () {
      expect(pace([page(DateTime(2026, 7, 20), backlog: true)]), isNull);
    });

    test('deleted records', () {
      expect(pace([page(DateTime(2026, 7, 20), deleted: true)]), isNull);
    });

    test('nothing at all', () {
      expect(pace(const []), isNull);
    });
  });

  group('the estimate it feeds', () {
    test('a steady page a day finishes in about the pages remaining', () {
      final history = [for (var d = 1; d <= 10; d++) page(DateTime(2026, 7, d))];
      final estimate = CompletionEstimator.estimate(
        project: project,
        history: history,
        rules: rules,
      )!;

      expect(estimate.doneUnits, closeTo(10, 0.001));
      expect(estimate.remainingUnits, closeTo(235, 0.001));
      expect(estimate.unitsPerWorkDay, closeTo(1, 0.001));
      expect(estimate.paceMeasured, isTrue);
      // 235 pages at a page a writing day.
      expect(estimate.workDaysLeft, closeTo(235, 1));
    });

    test('and a gap does not push the date years out', () {
      final gapped = [
        page(DateTime(2026, 1, 5)),
        for (var d = 1; d <= 9; d++) page(DateTime(2026, 7, d)),
      ];
      final estimate = CompletionEstimator.estimate(
        project: project,
        history: gapped,
        rules: rules,
      )!;
      expect(estimate.unitsPerWorkDay, closeTo(1, 0.001));
    });
  });
}
