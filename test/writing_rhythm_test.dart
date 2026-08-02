// When a sofer writes fastest.
//
// Every recorded sitting already carried the hour it began and how long it
// took, and nothing ever asked the obvious question of that. The trap here is
// measuring the wrong thing: an hour that produced twelve lines beats three
// hours that produced twenty, and a writer planning his day needs the pace and
// not the quantity.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/writing_rhythm.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const dayStart = DayStart.midnight;
  var seq = 0;

  final project = Project(
    id: 'p',
    name: 'x',
    type: ProjectType.sefer,
    price: 100,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 42,
  );

  /// A sitting that began at [hour] on [day] and wrote [lines] lines.
  WorkSession sitting({
    required int hour,
    required int lines,
    Duration took = const Duration(hours: 1),
    DateTime? day,
    bool timeRecorded = true,
    bool backlogOnly = false,
    bool deleted = false,
  }) {
    final d = day ?? DateTime(2026, 7, 20);
    final start = DateTime(d.year, d.month, d.day, hour);
    return WorkSession(
      id: 'w${seq++}',
      projectId: 'p',
      startTime: start,
      endTime: start.add(timeRecorded ? took : Duration.zero),
      amount: 1,
      startLine: 1,
      endLine: lines,
      description: '',
      isManual: true,
      timeRecorded: timeRecorded,
      backlogOnly: backlogOnly,
      deletedAt: deleted ? DateTime(2026, 8) : null,
    );
  }

  List<RhythmSlot> byHour(List<WorkSession> s) =>
      WritingRhythm.byHourOfDay(project, s, dayStart);

  group('pace, not quantity', () {
    test('a fast short sitting beats a slow long one', () {
      // Twelve lines in an hour is faster than twenty in three, and a writer
      // choosing when to sit down needs to be told the first.
      final slots = byHour([
        sitting(hour: 6, lines: 12),
        sitting(hour: 21, lines: 20, took: const Duration(hours: 3)),
      ]);

      final morning = slots.firstWhere((s) => s.slot == 6);
      final evening = slots.firstWhere((s) => s.slot == 21);
      expect(morning.linesPerHour, 12);
      expect(evening.linesPerHour, closeTo(6.67, 0.01));
      expect(morning.linesPerHour, greaterThan(evening.linesPerHour));
    });

    test('sittings in the same hour are pooled', () {
      final slots = byHour([
        sitting(hour: 6, lines: 10),
        sitting(hour: 6, lines: 20),
      ]);
      expect(slots, hasLength(1));
      expect(slots.single.lines, 30);
      expect(slots.single.sittings, 2);
      expect(slots.single.linesPerHour, 15);
    });
  });

  group('what is left out of the measure', () {
    test('a record with no working time', () {
      // Not a pace of zero — no pace at all. Averaged as zero it would drag
      // every hour a writer records output in down towards nothing.
      expect(byHour([sitting(hour: 6, lines: 10, timeRecorded: false)]),
          isEmpty);
    });

    test('a sitting too short to judge', () {
      // Twelve lines against four seconds is a slip, not a pace, and one of
      // them would dominate the average of everything else.
      expect(
          byHour([
            sitting(hour: 6, lines: 12, took: const Duration(seconds: 4))
          ]),
          isEmpty);
    });

    test('backlog work, which carries a placeholder time', () {
      expect(byHour([sitting(hour: 6, lines: 10, backlogOnly: true)]), isEmpty);
    });

    test('a deleted record', () {
      expect(byHour([sitting(hour: 6, lines: 10, deleted: true)]), isEmpty);
    });

    test('a sitting that produced nothing', () {
      expect(byHour([sitting(hour: 6, lines: 0)]), isEmpty);
    });
  });

  group('the best hour', () {
    test('is the fastest one measured often enough', () {
      final slots = byHour([
        for (var i = 0; i < 3; i++) sitting(hour: 6, lines: 12),
        for (var i = 0; i < 3; i++) sitting(hour: 21, lines: 6),
      ]);
      expect(WritingRhythm.best(slots)!.slot, 6);
    });

    test('one good evening is not a fact about evenings', () {
      // A single sitting flatters a coincidence. The whole difference between
      // telling a writer something and telling him noise.
      final slots = byHour([
        sitting(hour: 21, lines: 40),
        for (var i = 0; i < 3; i++) sitting(hour: 6, lines: 12),
      ]);
      expect(WritingRhythm.best(slots)!.slot, 6,
          reason: 'the single fast evening is not reliable enough to win');
    });

    test('is nothing at all when nothing has been measured enough', () {
      // The honest answer for a writer who has just started.
      expect(WritingRhythm.best(byHour([sitting(hour: 6, lines: 12)])), isNull);
    });

    test('and a slot says whether it can be trusted', () {
      final slots = byHour([sitting(hour: 6, lines: 12)]);
      expect(slots.single.isReliable, isFalse);
    });
  });

  group('by day of the week', () {
    List<RhythmSlot> byDay(List<WorkSession> s) =>
        WritingRhythm.byDayOfWeek(project, s, dayStart);

    test('Sunday is the first day, as the week is counted here', () {
      // 19 July 2026 is a Sunday.
      final slots = byDay([sitting(hour: 9, lines: 10, day: DateTime(2026, 7, 19))]);
      expect(slots.single.slot, 1);
    });

    test('and Friday is the sixth', () {
      // 24 July 2026 is a Friday.
      final slots = byDay([sitting(hour: 9, lines: 10, day: DateTime(2026, 7, 24))]);
      expect(slots.single.slot, 6);
    });

    test('the day is the one the work was filed under', () {
      // Written at half past midnight by a writer whose day turns over at two:
      // it belongs to the evening before, not to the day the clock reached.
      final s = WorkSession(
        id: 'late',
        projectId: 'p',
        startTime: DateTime(2026, 7, 20, 0, 30),
        endTime: DateTime(2026, 7, 20, 1, 30),
        amount: 1,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
        dayRule: const DayStart(boundary: DayBoundary.fixedHour, hour: 2),
      );
      // 19 July is Sunday, so filed under it the slot is 1, not Monday's 2.
      expect(byDay([s]).single.slot, 1);
    });
  });
}
