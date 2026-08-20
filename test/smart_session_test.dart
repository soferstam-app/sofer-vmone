// A sitting recorded in smart mode.
//
// Two hundred and thirty lines of this arithmetic lived in the home screen and
// could only be exercised by starting a timer and writing: which lines of which
// pages a sitting covered, how many that came to, and how the measured time
// divides between them.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/session_logic.dart';
import 'package:sofer_vmone/logic/smart_session.dart';
import 'package:sofer_vmone/logic/smart_live_recording.dart';
import 'package:sofer_vmone/logic/tefillin_state.dart';
import 'package:sofer_vmone/logic/tefillin_units.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Project project(ProjectType type, {int linesPerPage = 42}) => Project(
        id: 'p',
        name: 'x',
        type: type,
        price: 100,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: type == ProjectType.sefer ? linesPerPage : null,
      );

  final endedAt = DateTime(2026, 7, 20, 12);
  const worked = Duration(hours: 2);

  SmartOutcome sitting({
    required ProjectType type,
    required SmartPosition from,
    required SmartPosition to,
    Duration time = worked,
    List<WorkSession> history = const [],
  }) =>
      SmartSessionBuilder.build(
        project: project(type),
        from: from,
        to: to,
        worked: time,
        endedAt: endedAt,
        history: history,
      );

  SmartRecorded recorded(SmartOutcome outcome) {
    expect(outcome, isA<SmartRecorded>());
    return outcome as SmartRecorded;
  }

  group('a sefer', () {
    test('one page, part written', () {
      final result = recorded(sitting(
        type: ProjectType.sefer,
        from: const SmartPosition(5, 1),
        to: const SmartPosition(5, 11),
      ));

      expect(result.linesWritten, 10);
      expect(result.sessions, hasLength(1));
      final s = result.sessions.single;
      expect(s.amount, 5);
      expect(s.startLine, 1);
      expect(s.endLine, 10);
      expect(s.isManual, isFalse);
      expect(s.linesPerPageAtEntry, 42);
    });

    test('a page finished exactly rolls back to that page', () {
      // The stored position is the line about to be written. Standing at the
      // top of page six means page five was finished, not that six was started.
      final result = recorded(sitting(
        type: ProjectType.sefer,
        from: const SmartPosition(5, 1),
        to: const SmartPosition(6, 1),
      ));

      expect(result.linesWritten, 42);
      expect(result.sessions.single.amount, 5);
      expect(result.sessions.single.endLine, 42);
    });

    test('several pages become one record each, with the right lines', () {
      final result = recorded(sitting(
        type: ProjectType.sefer,
        from: const SmartPosition(5, 30),
        to: const SmartPosition(7, 5),
      ));

      expect(result.sessions.map((s) => s.amount), [5, 6, 7]);
      expect(result.sessions.map((s) => s.startLine), [30, 1, 1]);
      expect(result.sessions.map((s) => s.endLine), [42, 42, 4]);
      expect(result.linesWritten, 13 + 42 + 4);
    });

    test('standing where you started is nothing written', () {
      expect(
          sitting(
            type: ProjectType.sefer,
            from: const SmartPosition(5, 10),
            to: const SmartPosition(5, 10),
          ),
          isA<SmartNothingWritten>());
    });

    test('a position moved backwards is nothing written', () {
      // Which is what "ערוך מיקום" makes possible.
      expect(
          sitting(
            type: ProjectType.sefer,
            from: const SmartPosition(7, 1),
            to: const SmartPosition(5, 3),
          ),
          isA<SmartNothingWritten>());
    });
  });

  group('the measured time', () {
    test('is divided in proportion to the lines, and adds back up', () {
      final result = recorded(sitting(
        type: ProjectType.sefer,
        from: const SmartPosition(5, 30),
        to: const SmartPosition(7, 5),
      ));

      final total =
          result.sessions.fold(Duration.zero, (sum, s) => sum + s.duration);
      expect(total, worked, reason: 'two hours of writing are two hours');

      // 13, 42 and 4 lines: the middle page took the most of it.
      final spans = result.sessions.map((s) => s.duration).toList();
      expect(spans[1], greaterThan(spans[0]));
      expect(spans[0], greaterThan(spans[2]));
    });

    test('runs consecutively and ends when the sitting ended', () {
      final result = recorded(sitting(
        type: ProjectType.sefer,
        from: const SmartPosition(5, 30),
        to: const SmartPosition(7, 5),
      ));

      expect(result.sessions.first.startTime, endedAt.subtract(worked));
      expect(result.sessions.last.endTime, endedAt);
      for (var i = 1; i < result.sessions.length; i++) {
        expect(result.sessions[i].startTime, result.sessions[i - 1].endTime);
      }
    });

    test('a sitting that measured nothing still records the writing', () {
      final result = recorded(sitting(
        type: ProjectType.sefer,
        from: const SmartPosition(5, 1),
        to: const SmartPosition(5, 11),
        time: Duration.zero,
      ));
      expect(result.linesWritten, 10);
      expect(result.sessions.single.duration, Duration.zero);
    });
  });

  group('work already recorded', () {
    test('is reported with the pages it is on', () {
      final earlier = WorkSession(
        id: 'old',
        projectId: 'p',
        startTime: DateTime(2026, 7, 1, 9),
        endTime: DateTime(2026, 7, 1, 10),
        amount: 6,
        startLine: 1,
        endLine: 42,
        description: '',
        isManual: false,
      );

      final result = recorded(sitting(
        type: ProjectType.sefer,
        from: const SmartPosition(5, 30),
        to: const SmartPosition(7, 5),
        history: [earlier],
      ));

      expect(result.overlapsRecordedWork, isTrue);
      expect(result.overlappingPages, [6]);
      expect(result.sessions, hasLength(3),
          reason: 'reported, not refused — the writer decides');
    });

    test('is not reported when the pages are untouched', () {
      final result = recorded(sitting(
        type: ProjectType.sefer,
        from: const SmartPosition(5, 1),
        to: const SmartPosition(5, 11),
      ));
      expect(result.overlapsRecordedWork, isFalse);
    });
  });

  group('mezuzot', () {
    test('part of one is recorded as one part-written', () {
      final result = recorded(sitting(
        type: ProjectType.mezuza,
        from: const SmartPosition(1, 5),
        to: const SmartPosition(1, 12),
      ));

      expect(result.linesWritten, 7);
      expect(result.sessions, hasLength(1));
      expect(result.sessions.single.amount, 1);
      expect(result.sessions.single.endLine, 7);
    });

    test('whole ones are counted, not paginated', () {
      final result = recorded(sitting(
        type: ProjectType.mezuza,
        from: const SmartPosition(1, 1),
        to: const SmartPosition(3, 1),
      ));

      expect(result.linesWritten, 44);
      expect(result.sessions, hasLength(2));
      expect(result.sessions.map((s) => s.amount), [1, 1]);
      expect(result.sessions.map((s) => s.mezuzaIndex), [1, 2]);
      expect(result.sessions.map((s) => s.endLine), [0, 0]);
    });

    test('whole ones and a part of the next are two records', () {
      final result = recorded(sitting(
        type: ProjectType.mezuza,
        from: const SmartPosition(1, 1),
        to: const SmartPosition(2, 6),
      ));

      expect(result.linesWritten, 27);
      expect(result.sessions, hasLength(2));
      expect(result.sessions.first.amount, 1);
      expect(result.sessions.first.endLine, 0);
      expect(result.sessions.last.amount, 1);
      expect(result.sessions.last.endLine, 5);

      final total =
          result.sessions.fold(Duration.zero, (sum, s) => sum + s.duration);
      expect(total, worked);
    });
  });

  group('tefillin order', () {
    test('the recorder itself rejects a later unfinished parshiya', () {
      final result = sitting(
        type: ProjectType.tefillin,
        // Slot two is והיה כי יביאך of the first head; קדש is untouched.
        from: const SmartPosition(2, 1),
        to: const SmartPosition(2, 2),
      );

      expect(result, isA<SmartRejected>());
      expect((result as SmartRejected).message, contains('הקודמת'));
    });

    test('saving every line grows one live parshiya record', () {
      final liveProject = project(ProjectType.tefillin);
      var history = <WorkSession>[];
      for (var line = 1; line <= 4; line++) {
        final outcome = SmartSessionBuilder.build(
          project: liveProject,
          from: SmartPosition(1, line),
          to: line == 4
              ? const SmartPosition(2, 1)
              : SmartPosition(1, line + 1),
          worked: const Duration(minutes: 3),
          endedAt: DateTime(2026, 8, 19, 9, line * 3),
          history: history,
          entryId: 'live-sitting',
        );
        final saved = recorded(outcome);
        history = SmartLiveRecording.merge(history, saved.sessions);
      }

      expect(history, hasLength(1));
      expect(history.single.entryId, 'live-sitting');
      expect(history.single.startLine, 1);
      expect(history.single.endLine, 4);
      expect(history.single.duration, const Duration(minutes: 12));
      expect(ProductionCalculator.parshiyotTotal(history), 1);
    });

    test('the recorder allows it after the predecessor is complete', () {
      final earlier = WorkSession(
        id: 'first',
        projectId: 'p',
        startTime: DateTime(2026, 7, 1, 9),
        endTime: DateTime(2026, 7, 1, 10),
        amount: 1,
        startLine: 0,
        endLine: 0,
        tefillinType: 'head',
        parshiya: 1,
        pairIndex: 1,
        description: 'קדש',
        isManual: false,
      );
      final result = sitting(
        type: ProjectType.tefillin,
        from: const SmartPosition(2, 1),
        to: const SmartPosition(2, 2),
        history: [earlier],
      );

      expect(recorded(result).sessions.single.parshiya, 2);
    });

    test('stopping and resuming adds line ranges without double counting', () {
      final first = recorded(sitting(
        type: ProjectType.tefillin,
        from: const SmartPosition(1, 1),
        to: const SmartPosition(1, 3),
      ));
      final resumed = recorded(sitting(
        type: ProjectType.tefillin,
        from: const SmartPosition(1, 3),
        // Top of slot two means lines 3–4 finished slot one.
        to: const SmartPosition(2, 1),
        history: first.sessions,
      ));
      final all = [...first.sessions, ...resumed.sessions];

      expect(first.sessions.single.startLine, 1);
      expect(first.sessions.single.endLine, 2);
      expect(first.sessions.single.amount, 1);
      expect(resumed.sessions.single.startLine, 3);
      expect(resumed.sessions.single.endLine, 4);
      expect(resumed.sessions.single.amount, 0,
          reason: 'the same parshiya is not a second output unit');
      expect(
          TefillinState.slots(project(ProjectType.tefillin), all).first.state,
          SlotState.done);
      expect(ProductionCalculator.parshiyotTotal(all), 1);
      expect(ProductionCalculator.tefillinSeferLinesTotal(all), 16);
    });
  });

  group('where the writer stands after an entry', () {
    test('is the line after the one just written', () {
      expect(SmartPosition.after(page: 5, line: 20, linesPerUnit: 42).line, 21);
      expect(SmartPosition.after(page: 5, line: 20, linesPerUnit: 42).page, 5);
    });

    test('rolls onto the next page when the page is full', () {
      final next = SmartPosition.after(page: 5, line: 42, linesPerUnit: 42);
      expect(next.page, 6);
      expect(next.line, 1);
    });

    test('only counts as progress when it is further along', () {
      // Filling in an earlier gap must not rewind the writer's place.
      expect(const SmartPosition(6, 1).isAfter(const SmartPosition(5, 42)),
          isTrue);
      expect(const SmartPosition(5, 42).isAfter(const SmartPosition(6, 1)),
          isFalse);
      expect(const SmartPosition(5, 10).isAfter(const SmartPosition(5, 10)),
          isFalse);
    });
  });

  group('SessionLogic.splitByWeight', () {
    final start = DateTime(2026, 7, 20, 9);
    final end = DateTime(2026, 7, 20, 12);

    test('gives each part its share and adds back up exactly', () {
      final slices = SessionLogic.splitByWeight(
          start: start, end: end, weights: [1, 2, 3]);

      expect(slices, hasLength(3));
      final total = slices.fold(
          Duration.zero, (sum, s) => sum + s.end.difference(s.start));
      expect(total, end.difference(start));
      expect(slices[0].end.difference(slices[0].start),
          const Duration(minutes: 30));
      expect(
          slices[1].end.difference(slices[1].start), const Duration(hours: 1));
      expect(slices.last.end, end);
    });

    test('nothing to weigh gives every part nothing', () {
      final slices =
          SessionLogic.splitByWeight(start: start, end: end, weights: [0, 0]);
      for (final s in slices) {
        expect(s.end.difference(s.start), Duration.zero);
      }
    });

    test('one part, or none', () {
      expect(SessionLogic.splitByWeight(start: start, end: end, weights: [5]),
          hasLength(1));
      expect(SessionLogic.splitByWeight(start: start, end: end, weights: []),
          isEmpty);
    });
  });
}
