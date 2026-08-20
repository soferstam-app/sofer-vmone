// Where "today" is drawn on a commission, and whether the writer is late.
//
// Both sat inside the project summary screen reading its fields, so the only
// way to check either was to open a commission and look at it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/project/commission_timeline.dart';

void main() {
  final begun = DateTime(2026, 1, 1);
  final estimated = DateTime(2026, 12, 31);

  group('the run the line is drawn on', () {
    test('goes from the first day of work to the estimate', () {
      final run = TimelineRun.of(started: begun, estimatedEnd: estimated);
      expect(run.from, begun);
      expect(run.end, estimated);
    });

    test('stretches to the deadline when that is later', () {
      // Or the agreed date would sit off the end of the line, which is exactly
      // when a writer most needs to see it.
      final target = DateTime(2027, 3, 1);
      final run = TimelineRun.of(
          started: begun, estimatedEnd: estimated, target: target);
      expect(run.end, target);
    });

    test('but not shorter, when the deadline is sooner than the estimate', () {
      final run = TimelineRun.of(
          started: begun,
          estimatedEnd: estimated,
          target: DateTime(2026, 6, 1));
      expect(run.end, estimated,
          reason: 'running late does not shorten the run');
    });

    test('starts today when no work has been recorded yet', () {
      final run = TimelineRun.of(started: null, estimatedEnd: estimated);
      expect(run.from.difference(DateTime.now()).inMinutes.abs(),
          lessThan(2));
    });
  });

  group('a date on the run', () {
    final run = TimelineRun(from: begun, end: DateTime(2026, 1, 11));

    test('the start is at nothing and the end is at everything', () {
      expect(run.at(begun), 0);
      expect(run.at(DateTime(2026, 1, 11)), 1);
    });

    test('halfway is halfway', () {
      expect(run.at(DateTime(2026, 1, 6)), closeTo(0.5, 0.001));
    });

    test('nothing falls outside the line', () {
      // A deadline already passed, or a start date edited to the future: both
      // would otherwise be drawn off the end of the widget.
      expect(run.at(DateTime(2025, 6, 1)), 0);
      expect(run.at(DateTime(2030, 1, 1)), 1);
    });

    test('a run of no length is finished, not a division by zero', () {
      final same = TimelineRun(from: begun, end: begun);
      expect(same.at(begun), 1);
      expect(same.at(DateTime(2026, 5, 5)), 1);
    });
  });

  group('the marks', () {
    String date(DateTime d) => '${d.year}-${d.month}-${d.day}';

    test('are start, today and the estimate when nothing was agreed', () {
      final run = TimelineRun.of(started: begun, estimatedEnd: estimated);
      final marks = run.marks(estimatedEnd: estimated, formatDate: date);

      expect(marks.map((m) => m.caption), ['התחלה', 'היום', 'צפי סיום']);
      expect(marks.first.at, 0);
      expect(marks.last.at, 1);
    });

    test('today is the one drawn in the accent, and carries no date', () {
      final run = TimelineRun.of(started: begun, estimatedEnd: estimated);
      final today =
          run.marks(estimatedEnd: estimated, formatDate: date)[1];

      expect(today.current, isTrue);
      expect(today.value, isEmpty,
          reason: 'the caption already says which day it is');
    });

    test('a deadline adds a fourth, drawn quietly', () {
      final target = DateTime(2026, 11, 1);
      final run = TimelineRun.of(
          started: begun, estimatedEnd: estimated, target: target);
      final marks = run.marks(
          estimatedEnd: estimated, target: target, formatDate: date);

      expect(marks, hasLength(4));
      expect(marks.last.caption, 'תאריך יעד');
      expect(marks.last.quiet, isTrue,
          reason: 'a commitment, not a measurement');
    });
  });

  group('the deadline verdict', () {
    ({String text, bool late})? verdict(DateTime? target, DateTime end) =>
        deadlineVerdict(target: target, estimatedEnd: end);

    test('there is none without a deadline', () {
      expect(verdict(null, estimated), isNull);
    });

    test('within three days either way is on time', () {
      // An estimate built from a measured pace is not precise to the day, and
      // "late by one day" from it would claim an accuracy it does not have.
      expect(verdict(DateTime(2026, 12, 29), estimated)!.late, isFalse);
      expect(verdict(DateTime(2027, 1, 2), estimated)!.text,
          'צפוי להסתיים בדיוק בתאריך היעד');
    });

    test('finishing before the deadline is early', () {
      final v = verdict(DateTime(2027, 1, 31), estimated)!;
      expect(v.late, isFalse);
      expect(v.text, startsWith('אתה מקדים'));
    });

    test('finishing after it is late', () {
      final v = verdict(DateTime(2026, 10, 1), estimated)!;
      expect(v.late, isTrue);
      expect(v.text, startsWith('אתה מאחר'));
    });

    test('counts in Hebrew, which has a dual', () {
      // "2 שבועות" and "ב-שבועיים" are both what a program writes and nobody
      // says. One week, two weeks and many weeks are three different words.
      expect(verdict(DateTime(2027, 1, 7), estimated)!.text,
          endsWith('בשבוע'));
      expect(verdict(DateTime(2027, 1, 14), estimated)!.text,
          endsWith('בשבועיים'));
      expect(verdict(DateTime(2027, 1, 21), estimated)!.text,
          endsWith('ב-3 שבועות'));
    });

    test('and in days when it is under a week', () {
      expect(verdict(DateTime(2027, 1, 4), estimated)!.text,
          endsWith('ב-4 ימים'));
    });
  });
}
