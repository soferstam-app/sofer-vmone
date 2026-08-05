// Proofreading: the stage of the job the app has been charging for and not
// recording.
//
// "הגהות מזוזות" and "הגהות תפילין" have been expense categories all along,
// with nowhere to say what was sent, to whom, or what came back.
//
// The schema is the part that cannot be taken back once a writer has records in
// it, so it is held to the same rules every other record obeys: an id is the
// only thing required, an unknown field written by a later version survives a
// round trip, the stage is stored by name as well as by index, and a deletion
// is two registers rather than a flag.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/merge_service.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Proofread sample() => Proofread(
        id: 'r1',
        projectId: 'p1',
        stage: ProofreadStage.sent,
        scope: 'עמודים א-ל',
        proofreader: 'ר׳ יעקב',
        sentAt: DateTime(2026, 5, 3),
        cost: 450,
        notes: 'דחוף',
        lastUpdated: DateTime(2026, 5, 3, 10),
      );

  Proofread roundTrip(Proofread r) => Proofread.fromJson(r.toJson());

  group('what a record carries', () {
    test('everything it was given comes back', () {
      final back = roundTrip(sample());
      expect(back.id, 'r1');
      expect(back.projectId, 'p1');
      expect(back.stage, ProofreadStage.sent);
      expect(back.scope, 'עמודים א-ל');
      expect(back.proofreader, 'ר׳ יעקב');
      expect(back.sentAt, DateTime(2026, 5, 3));
      expect(back.cost, 450);
      expect(back.notes, 'דחוף');
    });

    test('the cost carries its currency, like every other amount', () {
      final r = sample().copyWith(currency: const Currency('USD'));
      expect(roundTrip(r).currency, const Currency('USD'));
      // Anything written before currencies existed is shekels, which is the
      // only thing it could have been.
      expect(Proofread.fromJson({'id': 'x', 'projectId': 'p'}).currency,
          Currency.ils);
    });

    test('no findings recorded is not the same as none found', () {
      // A clean return is a fact worth keeping; "nobody wrote it down" is not
      // the same fact, and showing zero for both would invent one.
      expect(roundTrip(sample()).findings, isNull);
      expect(roundTrip(sample().copyWith(findings: 0)).findings, 0);
      expect(roundTrip(sample().copyWith(findings: 7)).findings, 7);
    });
  });

  group('what it refuses and what it forgives', () {
    test('a record with no id is not a record', () {
      expect(() => Proofread.fromJson({'projectId': 'p1'}),
          throwsA(isA<FormatException>()));
    });

    test('everything else missing still reads', () {
      final r = Proofread.fromJson({'id': 'r9'});
      expect(r.stage, ProofreadStage.waiting);
      expect(r.scope, isEmpty);
      expect(r.cost, 0);
      expect(r.isDeleted, isFalse);
    });

    test('a field of the wrong type does not lose the record', () {
      final r = Proofread.fromJson(
          {'id': 'r9', 'cost': 'a lot', 'findings': null, 'scope': 42});
      expect(r.id, 'r9');
      expect(r.cost, 0);
    });
  });

  group('surviving a version that does not know this field', () {
    test('an unknown key comes back bit for bit', () {
      final json = sample().toJson()..['somethingLater'] = {'a': 1};
      final back = Proofread.fromJson(json);
      expect(back.toJson()['somethingLater'], {'a': 1});
    });

    test('editing keeps it', () {
      final json = sample().toJson()..['somethingLater'] = 'kept';
      final edited = Proofread.fromJson(json).copyWith(notes: 'שונה');
      expect(edited.toJson()['somethingLater'], 'kept');
      expect(edited.notes, 'שונה');
    });

    test('the stage is written by name as well as by index', () {
      // An index is a promise that the declaration order never changes, and
      // nothing in the language keeps that promise.
      final json = sample().toJson();
      expect(json['stageName'], 'sent');
      expect(json['stage'], ProofreadStage.sent.index);
    });

    test('and is read by name first', () {
      final json = sample().toJson()
        ..['stageName'] = 'done'
        ..['stage'] = 0;
      expect(Proofread.fromJson(json).stage, ProofreadStage.done);
    });
  });

  group('deletion', () {
    test('is two registers, not a flag', () {
      final gone = sample().copyWith(isDeleted: true);
      expect(gone.isDeleted, isTrue);
      expect(gone.deletedAt, isNotNull);
      expect(roundTrip(gone).isDeleted, isTrue);
    });

    test('is not undone by an edit made afterwards', () {
      // The failure this design exists to prevent: a device editing a stale
      // copy used to bring a deleted record back to life.
      final gone = sample().copyWith(isDeleted: true);
      final edited = gone.copyWith(notes: 'עריכה מאוחרת');
      expect(edited.isDeleted, isTrue);
    });

    test('is undone only by a restore that is genuinely later', () {
      final gone = sample().copyWith(isDeleted: true);
      expect(gone.copyWith(isDeleted: false).isDeleted, isFalse);
    });
  });

  group('two devices', () {
    test('a record only one side has is kept', () {
      final out = MergeService.mergeBackup(
        localProjects: const [], localHistory: const [], localExpenses: const [],
        incomingProjects: const [], incomingHistory: const [],
        incomingExpenses: const [],
        localProofreads: [sample()],
        incomingProofreads: [
          Proofread(id: 'r2', projectId: 'p1', lastUpdated: DateTime(2026, 6)),
        ],
      );
      expect(out.proofreads.map((r) => r.id), containsAll(['r1', 'r2']));
    });

    test('the later edit wins the payload', () {
      final newer = sample().copyWith(proofreader: 'ר׳ שמעון');
      final out = MergeService.mergeBackup(
        localProjects: const [], localHistory: const [], localExpenses: const [],
        incomingProjects: const [], incomingHistory: const [],
        incomingExpenses: const [],
        localProofreads: [sample()],
        incomingProofreads: [newer],
      );
      expect(out.proofreads.single.proofreader, 'ר׳ שמעון');
    });

    test('a deletion on one side survives an edit on the other', () {
      final deleted = sample().copyWith(isDeleted: true);
      final editedElsewhere =
          sample().copyWith(notes: 'נערך במכשיר שלא סונכרן');
      final out = MergeService.mergeBackup(
        localProjects: const [], localHistory: const [], localExpenses: const [],
        incomingProjects: const [], incomingHistory: const [],
        incomingExpenses: const [],
        localProofreads: [deleted],
        incomingProofreads: [editedElsewhere],
      );
      expect(out.proofreads.single.isDeleted, isTrue);
    });
  });

  group('how long it has been out', () {
    test('null before it was sent', () {
      final r = Proofread(id: 'r', projectId: 'p');
      expect(r.turnaround(), isNull);
    });

    test('measured to the return where there is one', () {
      final r = sample().copyWith(returnedAt: DateTime(2026, 5, 13));
      expect(r.turnaround()!.inDays, 10);
    });

    test('and to now while it is still out', () {
      expect(sample().turnaround(now: DateTime(2026, 5, 9))!.inDays, 6);
    });
  });

  group('the stages', () {
    test('read in Hebrew', () {
      expect(ProofreadStage.waiting.label, 'ממתין להגהה');
      expect(ProofreadStage.done.label, 'הושלם');
    });

    test('only the last one is closed', () {
      expect(ProofreadStage.waiting.isOpen, isTrue);
      expect(ProofreadStage.sent.isOpen, isTrue);
      expect(ProofreadStage.returned.isOpen, isTrue);
      expect(ProofreadStage.done.isOpen, isFalse);
    });
  });
}
