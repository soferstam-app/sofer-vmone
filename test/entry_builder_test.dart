// The rules that turn what a sofer types into what the app records.
//
// This is where the app's correctness lives, and until it was pulled out of the
// home screen none of it could be tested: three hundred lines that parsed,
// validated, checked for overlap, built records and saved them, all inside a
// dialog callback. Everything here used to be reachable only by tapping.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/entry_builder.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Project project(ProjectType type, {int? totalPages, int? linesPerPage}) =>
      Project(
        id: 'p',
        name: 'x',
        type: type,
        price: 100,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        totalPages: totalPages,
        linesPerPage: linesPerPage,
      );

  final start = DateTime(2026, 7, 20, 9);
  final end = DateTime(2026, 7, 20, 12);

  EntryOutcome build(EntryInput input, {List<WorkSession> history = const []}) =>
      EntryBuilder.build(input: input, history: history);

  EntryBuilt built(EntryOutcome outcome) {
    expect(outcome, isA<EntryBuilt>(),
        reason: outcome is EntryRejected ? outcome.message : '');
    return outcome as EntryBuilt;
  }

  String rejection(EntryOutcome outcome) {
    expect(outcome, isA<EntryRejected>());
    return (outcome as EntryRejected).message;
  }

  EntryInput sefer({
    String pageFrom = '',
    String pageTo = '',
    String lineFrom = '',
    String lineTo = '',
    int? totalPages,
    int? linesPerPage = 42,
    bool isManual = true,
    bool backlogOnly = false,
    bool timeRecorded = true,
  }) =>
      EntryInput(
        project: project(ProjectType.sefer,
            totalPages: totalPages, linesPerPage: linesPerPage),
        start: start,
        end: end,
        isManual: isManual,
        backlogOnly: backlogOnly,
        timeRecorded: timeRecorded,
        pageFrom: pageFrom,
        pageTo: pageTo,
        lineFrom: lineFrom,
        lineTo: lineTo,
      );

  group('a sefer, one page', () {
    test('becomes one record on the page and lines given', () {
      final result =
          built(build(sefer(pageFrom: '11', lineFrom: '5', lineTo: '20')));

      expect(result.sessions, hasLength(1));
      final s = result.sessions.single;
      expect(s.amount, 11);
      expect(s.startLine, 5);
      expect(s.endLine, 20);
      expect(s.startTime, start);
      expect(s.endTime, end);
      expect(s.linesPerPageAtEntry, 42);
      expect(s.description, contains('(5-20)'));
      expect(result.reachedPage, 11);
      expect(result.reachedLine, 20);
    });

    test('reads a page written as a Hebrew numeral', () {
      // "יא" is how a sofer says eleven, and the field takes either.
      final result =
          built(build(sefer(pageFrom: 'יא', lineFrom: '1', lineTo: '42')));
      expect(result.sessions.single.amount, 11);
    });

    test('refuses without a page', () {
      expect(rejection(build(sefer(lineFrom: '1', lineTo: '42'))),
          contains('עמוד התחלה'));
    });

    test('refuses a page past the end of the book', () {
      expect(
          rejection(build(
              sefer(pageFrom: '300', lineFrom: '1', lineTo: '42', totalPages: 245))),
          contains('245'));
    });

    test('refuses lines that do not fit the page', () {
      expect(rejection(build(sefer(pageFrom: '5', lineFrom: '1', lineTo: '50'))),
          contains('42'));
      expect(rejection(build(sefer(pageFrom: '5', lineFrom: '20', lineTo: '3'))),
          isNotEmpty);
      expect(rejection(build(sefer(pageFrom: '5'))), isNotEmpty);
    });
  });

  group('a sefer, a range of pages', () {
    test('becomes one record per page, each written in full', () {
      final result = built(build(sefer(pageFrom: '1', pageTo: '5')));

      expect(result.sessions, hasLength(5));
      expect(result.sessions.map((s) => s.amount), [1, 2, 3, 4, 5]);
      for (final s in result.sessions) {
        expect(s.startLine, 1);
        expect(s.endLine, 42);
      }
      expect(result.reachedPage, 5);
      expect(result.reachedLine, 42);
    });

    test('divides the time it was given instead of repeating it', () {
      // The defect this replaced: five pages written in three hours were
      // recorded as fifteen hours, and every figure per hour with them.
      final result = built(build(sefer(pageFrom: '1', pageTo: '5')));

      final total = result.sessions
          .fold(Duration.zero, (sum, s) => sum + s.duration);
      expect(total, end.difference(start));
      expect(result.sessions.first.startTime, start);
      expect(result.sessions.last.endTime, end);
    });

    test('an end page below the start is not a range', () {
      final result = built(build(
          sefer(pageFrom: '7', pageTo: '3', lineFrom: '1', lineTo: '42')));
      expect(result.sessions, hasLength(1));
      expect(result.sessions.single.amount, 7);
    });

    test('refuses a range that runs past the end of the book', () {
      expect(
          rejection(
              build(sefer(pageFrom: '240', pageTo: '260', totalPages: 245))),
          contains('245'));
    });
  });

  group('work already recorded', () {
    WorkSession recorded(int page, int from, int to) => WorkSession(
          id: 'old',
          projectId: 'p',
          startTime: DateTime(2026, 7, 1, 9),
          endTime: DateTime(2026, 7, 1, 10),
          amount: page,
          startLine: from,
          endLine: to,
          description: '',
          isManual: false,
        );

    test('is reported, not refused — writing over lines is a correction', () {
      final result = built(build(
        sefer(pageFrom: '5', lineFrom: '1', lineTo: '20'),
        history: [recorded(5, 10, 30)],
      ));
      expect(result.overlapsRecordedWork, isTrue);
      expect(result.sessions, hasLength(1));
    });

    test('is not reported for a different page', () {
      final result = built(build(
        sefer(pageFrom: '5', lineFrom: '1', lineTo: '20'),
        history: [recorded(6, 1, 42)],
      ));
      expect(result.overlapsRecordedWork, isFalse);
    });

    test('is found anywhere inside a range', () {
      final result = built(build(
        sefer(pageFrom: '1', pageTo: '5'),
        history: [recorded(4, 1, 42)],
      ));
      expect(result.overlapsRecordedWork, isTrue);
    });
  });

  group('mezuzot', () {
    EntryInput mezuza({String amount = '', String partialLine = ''}) =>
        EntryInput(
          project: project(ProjectType.mezuza),
          start: start,
          end: end,
          isManual: true,
          amount: amount,
          partialLine: partialLine,
        );

    test('are counted, and carry no page geometry', () {
      final result = built(build(mezuza(amount: '3')));
      final s = result.sessions.single;
      expect(s.amount, 3);
      expect(s.endLine, 0);
      expect(s.linesPerPageAtEntry, isNull);
      expect(s.description, contains('3 מזוזות'));
    });

    test('can be left part-written', () {
      final result = built(build(mezuza(amount: '2', partialLine: '14')));
      expect(result.sessions.single.endLine, 14);
      expect(result.sessions.single.description, contains('14'));
    });

    test('refuse a line past the end of a mezuza', () {
      expect(rejection(build(mezuza(amount: '1', partialLine: '30'))),
          contains('22'));
    });

    test('refuse without a quantity', () {
      expect(rejection(build(mezuza())), contains('כמות'));
    });
  });

  group('tefillin', () {
    EntryInput tefillin({
      String amount = '',
      String mode = 'set',
      String part = 'head',
      int parshiya = 1,
      String partialLine = '',
    }) =>
        EntryInput(
          project: project(ProjectType.tefillin),
          start: start,
          end: end,
          isManual: true,
          amount: amount,
          partialLine: partialLine,
          tefillinMode: mode,
          tefillinPart: part,
          tefillinParshiya: parshiya,
        );

    test('count as sets, as heads or as hands', () {
      expect(built(build(tefillin(amount: '2'))).sessions.single.tefillinType,
          isNull);
      final head =
          built(build(tefillin(amount: '2', mode: 'head'))).sessions.single;
      expect(head.tefillinType, 'head');
      expect(head.description, contains('של ראש'));
      expect(
          built(build(tefillin(amount: '2', mode: 'hand')))
              .sessions
              .single
              .tefillinType,
          'hand');
    });

    test('a single parshiya names itself', () {
      final result = built(build(tefillin(mode: 'parshiya', parshiya: 3)));
      final s = result.sessions.single;
      expect(s.amount, 1);
      expect(s.parshiya, 3);
      expect(s.tefillinType, 'head');
      expect(s.description, contains('שמע'));
    });

    test('a parshiya has its own line count, head and hand differing', () {
      expect(
          rejection(build(
              tefillin(mode: 'parshiya', part: 'head', partialLine: '6'))),
          contains('4'));
      // The same six lines are fine on a hand parshiya, which has seven.
      expect(
          built(build(
                  tefillin(mode: 'parshiya', part: 'hand', partialLine: '6')))
              .sessions
              .single
              .endLine,
          6);
    });
  });

  group('every record an entry produces', () {
    test('carries how the entry was made, not how it was worked out', () {
      final result = built(build(sefer(
        pageFrom: '1',
        pageTo: '3',
        isManual: true,
        backlogOnly: true,
        timeRecorded: false,
      )));

      for (final s in result.sessions) {
        expect(s.isManual, isTrue);
        expect(s.backlogOnly, isTrue);
        expect(s.timeRecorded, isFalse);
        expect(s.projectId, 'p');
        // Which working day a session is filed under depends on a setting this
        // file knows nothing about. The caller stamps it, through one place, so
        // the two paths cannot answer it differently.
        expect(s.workingDateAtEntry, isNull);
      }
    });

    test('has an id of its own', () {
      final result = built(build(sefer(pageFrom: '1', pageTo: '4')));
      expect(result.sessions.map((s) => s.id).toSet(), hasLength(4));
    });
  });
}
