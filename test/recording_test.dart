// Getting an entry back out of the records it scattered into.
//
// The failure this guards is a quiet one. A page range is entered once, with
// one stretch of time, and stored as one record per page holding a share of it.
// The shares were the only thing kept, and nothing said they were shares of
// anything — so the day the division is found wrong, there is no entry left to
// divide again, only five records that each claim their slice is a fact.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/entry_builder.dart';
import 'package:sofer_vmone/logic/recording.dart';
import 'package:sofer_vmone/logic/smart_session.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Project project(ProjectType type, {int? linesPerPage = 10}) => Project(
        id: 'p',
        name: 'x',
        type: type,
        price: 100,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: linesPerPage,
      );

  final start = DateTime(2026, 7, 20, 9);
  final end = DateTime(2026, 7, 20, 12);

  List<WorkSession> rangeEntry({
    String pageFrom = '1',
    String pageTo = '5',
    String lineFrom = '1',
    String lineTo = '10',
    bool timeRecorded = true,
  }) {
    final outcome = EntryBuilder.build(
      input: EntryInput(
        project: project(ProjectType.sefer),
        start: start,
        end: timeRecorded ? end : start,
        isManual: true,
        timeRecorded: timeRecorded,
        pageFrom: pageFrom,
        pageTo: pageTo,
        lineFrom: lineFrom,
        lineTo: lineTo,
      ),
      history: const [],
    );
    expect(outcome, isA<EntryBuilt>(),
        reason: outcome is EntryRejected ? outcome.message : '');
    return (outcome as EntryBuilt).sessions;
  }

  group('an entry knows which records it became', () {
    test('every record of a range carries the same mark', () {
      final sessions = rangeEntry();
      expect(sessions, hasLength(5));

      final marks = sessions.map((s) => s.entryId).toSet();
      expect(marks, hasLength(1));
      expect(marks.single, isNotNull);
    });

    test('the mark is not the record id', () {
      // They were separate things and staying separate is the whole point: the
      // ids are what merging keys on, the mark is what gathers them.
      final sessions = rangeEntry();
      for (final session in sessions) {
        expect(session.entryId, isNot(session.id));
      }
    });

    test('an entry saved alone is marked too', () {
      // Otherwise an unmarked record is ambiguous between "saved by itself" and
      // "saved before any of this existed", and those want opposite treatment.
      final sessions = rangeEntry(pageFrom: '3', pageTo: '');
      expect(sessions, hasLength(1));
      expect(sessions.single.entryId, isNotNull);
    });

    test('two entries are not confused for one', () {
      final first = rangeEntry(pageFrom: '1', pageTo: '3');
      final second = rangeEntry(pageFrom: '4', pageTo: '6');
      expect(first.first.entryId, isNot(second.first.entryId));

      final gathered = Recording.gather([...first, ...second]);
      expect(gathered, hasLength(2));
      expect(gathered[0].sessions, hasLength(3));
      expect(gathered[1].sessions, hasLength(3));
    });

    test('a sitting in smart mode is one entry across its pages', () {
      final outcome = SmartSessionBuilder.build(
        project: project(ProjectType.sefer),
        from: const SmartPosition(1, 1),
        to: const SmartPosition(3, 5),
        worked: const Duration(hours: 2),
        endedAt: end,
      );
      final sessions = (outcome as SmartRecorded).sessions;
      expect(sessions.length, greaterThan(1));

      final gathered = Recording.gather(sessions);
      expect(gathered, hasLength(1),
          reason: 'one sitting, however many pages it crossed');
      expect(gathered.single.worked, const Duration(hours: 2));
    });
  });

  group('what was entered is recovered from what was stored', () {
    test('the stretch comes back exactly, though only slices were kept', () {
      final gathered = Recording.gather(rangeEntry()).single;
      expect(gathered.start, start);
      expect(gathered.end, end);
      expect(gathered.worked, const Duration(hours: 3));
    });

    test('no record holds the stretch itself', () {
      // Which is why it has to be recoverable rather than read: storing it on
      // every record would be the same conclusion written six times, and six
      // copies of a thing are six chances for them to disagree.
      for (final session in rangeEntry()) {
        expect(session.duration, lessThan(const Duration(hours: 3)));
      }
    });

    test('the slices still add up to it', () {
      final sessions = rangeEntry();
      final total = sessions.fold(
          Duration.zero, (sum, s) => sum + s.endTime.difference(s.startTime));
      expect(total, const Duration(hours: 3));
    });

    test('an entry with no working time recovers as none', () {
      final gathered = Recording.gather(rangeEntry(timeRecorded: false)).single;
      expect(gathered.worked, Duration.zero);
      expect(gathered.timeRecorded, isFalse);
    });
  });

  group('dividing it again', () {
    test('by the same weights changes nothing', () {
      final sessions = rangeEntry();
      final again = Recording.gather(sessions).single.divideBy((_) => 1);

      for (var i = 0; i < sessions.length; i++) {
        expect(again[i].startTime, sessions[i].startTime);
        expect(again[i].endTime, sessions[i].endTime);
      }
    });

    test('by different weights still spends exactly the stretch', () {
      final gathered = Recording.gather(rangeEntry()).single;
      // A rule nobody has asked for: later pages take longer than earlier ones.
      final again = gathered.divideBy((s) => s.amount);

      expect(again.first.startTime, start);
      expect(again.last.endTime, end);

      final total = again.fold(
          Duration.zero, (sum, s) => sum + s.endTime.difference(s.startTime));
      expect(total, const Duration(hours: 3),
          reason: 'a new division may move the shares, never the total');
    });

    test('the new division really is different', () {
      final gathered = Recording.gather(rangeEntry()).single;
      final again = gathered.divideBy((s) => s.amount);
      expect(again.first.duration, lessThan(again.last.duration));
    });

    test('leaves the records themselves alone', () {
      // Everything but the times: dividing an entry again is a statement about
      // when the writing happened, not about what was written.
      final sessions = rangeEntry();
      final again = Recording.gather(sessions).single.divideBy((s) => s.amount);

      for (var i = 0; i < sessions.length; i++) {
        expect(again[i].id, sessions[i].id);
        expect(again[i].entryId, sessions[i].entryId);
        expect(again[i].amount, sessions[i].amount);
        expect(again[i].startLine, sessions[i].startLine);
        expect(again[i].endLine, sessions[i].endLine);
      }
    });

    test('refuses to divide an entry that never had a time', () {
      // Handing it empty slices would be arithmetic; leaving it be says the
      // truth, which is that nobody ever measured this.
      final sessions = rangeEntry(timeRecorded: false);
      final gathered = Recording.gather(sessions).single;
      final again = gathered.divideBy((s) => s.amount);

      expect(again, same(gathered.sessions), reason: 'not even copied');
      for (final session in again) {
        expect(session.timeRecorded, isFalse);
        expect(session.duration, Duration.zero);
      }
    });

    test('a hand-corrected record cannot make the entry run backwards', () {
      // The writer moves one page of a range to the small hours of the morning.
      // The entry now covers more than it was entered as, which is the truth,
      // and a division of it still runs forwards.
      final sessions = rangeEntry();
      final corrected = [
        sessions.first.copyWith(
          startTime: start.subtract(const Duration(hours: 4)),
          endTime: start.subtract(const Duration(hours: 3)),
        ),
        ...sessions.skip(1),
      ];

      final gathered = Recording.gather(corrected).single;
      expect(gathered.worked, greaterThan(Duration.zero));
      expect(gathered.end, end, reason: 'the furthest the entry reaches');

      for (final session in gathered.divideBy((_) => 1)) {
        expect(session.duration, greaterThanOrEqualTo(Duration.zero));
      }
    });

    test('can be repeated without drifting', () {
      var gathered = Recording.gather(rangeEntry()).single;
      for (var i = 0; i < 20; i++) {
        gathered = Recording(
          entryId: gathered.entryId,
          sessions: gathered.divideBy((s) => s.amount),
        );
      }
      expect(gathered.start, start);
      expect(gathered.end, end);
      expect(gathered.worked, const Duration(hours: 3));
    });
  });

  group('records written before any of this', () {
    WorkSession old(String id, DateTime from, DateTime to) => WorkSession(
          id: id,
          projectId: 'p',
          startTime: from,
          endTime: to,
          amount: 1,
          startLine: 1,
          endLine: 10,
          description: '',
          isManual: true,
        );

    test('carry no mark and each stand alone', () {
      final sessions = [
        old('a', start, start.add(const Duration(hours: 1))),
        old('b', start.add(const Duration(hours: 1)), end),
      ];
      expect(sessions.every((s) => s.entryId == null), isTrue);

      final gathered = Recording.gather(sessions);
      expect(gathered, hasLength(2),
          reason: 'nothing says these two belong together, so they do not');
      expect(gathered.every((r) => r.entryId == null), isTrue);
    });

    test('keep their own times when divided', () {
      final session = old('a', start, end);
      final again = Recording.gather([session]).single.divideBy((_) => 1);
      expect(again.single.startTime, start);
      expect(again.single.endTime, end);
    });

    test('an empty mark is read as no mark', () {
      // Or every such record would gather into one entry of its own making.
      final session = WorkSession.fromJson({
        ...old('a', start, end).toJson(),
        'entryId': '',
      });
      expect(session.entryId, isNull);
    });
  });

  group('the mark survives storage', () {
    test('through a save and a load', () {
      final session = rangeEntry().first;
      final revived = WorkSession.fromJson(session.toJson());
      expect(revived.entryId, session.entryId);
    });

    test('through an edit', () {
      // A corrected record is still one of the records that save produced.
      final session = rangeEntry().first;
      expect(session.copyWith(amount: 9).entryId, session.entryId);
      expect(session.copyWith(isDeleted: true).entryId, session.entryId);
    });

    test('through a delete and a restore', () {
      final session = rangeEntry().first;
      final buried = session.withTombstone(deletedAt: DateTime.now());
      expect(buried.entryId, session.entryId);
    });

    test('gathered records come back in the order they were laid down', () {
      final sessions = rangeEntry();
      final shuffled = sessions.reversed.toList();
      final gathered = Recording.gather(shuffled).single;
      expect([for (final s in gathered.sessions) s.amount], [1, 2, 3, 4, 5]);
    });
  });
}
