// Which day a hand-entered record is filed under.
//
// A writer reported that the day-boundary setting "does not work" on the
// ordinary entry form. It was working — that was the problem. He typed Tuesday
// and 00:30, and with his boundary at 02:00 the app filed it under Monday.
//
// The rule exists to interpret a *measurement*: a moment the app captured and
// has to decide the meaning of. A date a person typed is not a measurement, it
// is an assertion, and re-deriving it from the hour beside it overrules him
// with a rule that was never about him.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/date_logic.dart';
import 'package:sofer_vmone/logic/entry_builder.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const twoAm = DayStart(boundary: DayBoundary.fixedHour, hour: 2);
  final tuesday = DateTime(2026, 7, 21);

  final project = Project(
    id: 'p',
    name: 'ספר',
    type: ProjectType.sefer,
    price: 100,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 42,
  );

  List<WorkSession> build({
    required DateTime start,
    DateTime? statedDate,
    bool isManual = true,
  }) {
    final outcome = EntryBuilder.build(
      input: EntryInput(
        project: project,
        start: start,
        end: start.add(const Duration(hours: 1)),
        statedDate: statedDate,
        isManual: isManual,
        pageFrom: '5',
        lineFrom: '1',
        lineTo: '10',
      ),
      history: const [],
    );
    expect(outcome, isA<EntryBuilt>(),
        reason: outcome is EntryRejected ? outcome.message : '');
    return (outcome as EntryBuilt).sessions;
  }

  group('a date the writer typed', () {
    test('is the day the record is filed under', () {
      // Half past midnight on Tuesday, boundary at two in the morning. He said
      // Tuesday, so it is Tuesday.
      final s = build(
        start: DateTime(2026, 7, 21, 0, 30),
        statedDate: tuesday,
      ).single;

      expect(s.workingDateAtEntry, tuesday);
      expect(DateLogic.workingDateOf(s, twoAm), tuesday);
    });

    test('and the rule is not applied over it', () {
      // The rule would have said Monday. Nothing carries it, so nothing can.
      final s = build(
        start: DateTime(2026, 7, 21, 0, 30),
        statedDate: tuesday,
      ).single;
      expect(s.dayRule, isNull);
    });

    test('whatever the boundary happens to be set to', () {
      final s = build(
        start: DateTime(2026, 7, 21, 0, 30),
        statedDate: tuesday,
      ).single;

      for (final rule in [
        DayStart.midnight,
        twoAm,
        const DayStart(boundary: DayBoundary.fixedHour, hour: 5),
      ]) {
        expect(DateLogic.workingDateOf(s, rule), tuesday);
      }
    });

    test('every record of a page range carries it', () {
      final outcome = EntryBuilder.build(
        input: EntryInput(
          project: project,
          start: DateTime(2026, 7, 21, 9),
          end: DateTime(2026, 7, 21, 12),
          statedDate: tuesday,
          isManual: true,
          pageFrom: '5',
          pageTo: '8',
        ),
        history: const [],
      ) as EntryBuilt;

      expect(outcome.sessions.length, 4);
      for (final s in outcome.sessions) {
        expect(s.workingDateAtEntry, tuesday);
      }
    });
  });

  group('a moment the app measured', () {
    test('carries no stated date, and is left to the rule', () {
      // The timer's own records. Nothing was asserted, so the boundary is the
      // only thing that can decide — which is what it is for.
      final s = build(
        start: DateTime(2026, 7, 21, 0, 30),
        statedDate: null,
        isManual: false,
      ).single;

      expect(s.workingDateAtEntry, isNull);
      expect(DateLogic.workingDateOf(s, twoAm), DateTime(2026, 7, 20),
          reason: 'half past midnight belongs to the day before');
      expect(DateLogic.workingDateOf(s, DayStart.midnight),
          DateTime(2026, 7, 21));
    });
  });
}
