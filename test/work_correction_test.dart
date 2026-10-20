import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/tefillin_state.dart';
import 'package:sofer_vmone/logic/tefillin_units.dart';
import 'package:sofer_vmone/logic/work_correction.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  WorkSession session({int from = 1, int to = 10}) {
    final start = DateTime(2026, 8, 23, 9);
    return WorkSession(
      id: 'original',
      projectId: 'p',
      startTime: start,
      endTime: start.add(const Duration(minutes: 100)),
      amount: 12,
      startLine: from,
      endLine: to,
      description: 'עמוד יב',
      isManual: true,
      linesPerPageAtEntry: 42,
    );
  }

  test('removing middle lines splits the range without losing time', () {
    final result = WorkCorrection.removeSeferLines(
      history: [session()],
      projectId: 'p',
      page: 12,
      lines: {4, 5, 6},
    );
    final live = result.history.where((s) => !s.isDeleted).toList();

    expect(live, hasLength(2));
    expect((live[0].startLine, live[0].endLine), (1, 3));
    expect((live[1].startLine, live[1].endLine), (7, 10));
    expect(live.fold(Duration.zero, (sum, s) => sum + s.duration),
        const Duration(minutes: 100));
    expect(result.history.singleWhere((s) => s.id == 'original').isDeleted,
        isTrue);
  });

  test('removing a whole range leaves only the tombstone', () {
    final result = WorkCorrection.removeSeferLines(
      history: [session(from: 4, to: 6)],
      projectId: 'p',
      page: 12,
      lines: {4, 5, 6},
    );

    expect(result.history.where((s) => !s.isDeleted), isEmpty);
    expect(result.createdIds, isEmpty);
  });

  test('removing Sefer lines does not rewrite already-invalid work', () {
    final invalid = session().copyWith(isInvalid: true);
    final result = WorkCorrection.removeSeferLines(
      history: [invalid],
      projectId: 'p',
      page: 12,
      lines: {4, 5, 6},
    );

    expect(result.changed, isFalse);
    expect(result.history.single.id, 'original');
    expect(result.history.single.isInvalid, isTrue);
  });

  test('invalidating keeps the record live and is reversible', () {
    final marked = WorkCorrection.markInvalid([session()], {'original'});
    expect(marked.history.single.isInvalid, isTrue);
    expect(marked.history.single.isDeleted, isFalse);

    final cleared = WorkCorrection.markInvalid(marked.history, {'original'},
        invalid: false);
    expect(cleared.history.single.isInvalid, isFalse);
  });

  test('undoing deletion preserves a pre-existing invalid state', () {
    final invalid = session().copyWith(isInvalid: true);
    final deleted = WorkCorrection.delete([invalid], {'original'});

    final restored = deleted.undo().single;
    expect(restored.isDeleted, isFalse);
    expect(restored.isInvalid, isTrue);
  });

  test('one Mezuzah can be removed from a bundled legacy record', () {
    final start = DateTime(2026, 8, 23, 9);
    final legacy = WorkSession(
      id: 'legacy',
      projectId: 'mezuzot',
      startTime: start,
      endTime: start.add(const Duration(minutes: 66)),
      amount: 3,
      startLine: 0,
      endLine: 0,
      description: '3 מזוזות',
      isManual: true,
    );

    final result = WorkCorrection.deleteMezuza(
      history: [legacy],
      projectId: 'mezuzot',
      index: 2,
    );
    final live = result.history.where((item) => !item.isDeleted).toList();

    expect(live.map((item) => item.mezuzaIndex), [1, 3]);
    expect(live.fold(Duration.zero, (sum, item) => sum + item.duration),
        const Duration(minutes: 44));
    expect(result.history.where((item) => item.isDeleted), hasLength(2));
    expect(result.undo().singleWhere((item) => item.id == 'legacy').isDeleted,
        isFalse);
  });

  group('legacy Tefillin corrections', () {
    final project = Project(
      id: 'tefillin',
      name: 'תפילין',
      type: ProjectType.tefillin,
      price: 0,
      expenses: 0,
      currency: Currency.ils,
      targetDaily: 0,
      targetMonthly: 0,
      dailyGoalInLines: false,
      targetUnits: 1,
    );

    WorkSession legacyPair() {
      final start = DateTime(2026, 8, 23, 8);
      return WorkSession(
        id: 'legacy-pair',
        projectId: project.id,
        startTime: start,
        endTime: start.add(const Duration(minutes: 104)),
        amount: 1,
        startLine: 0,
        endLine: 0,
        description: 'זוג תפילין',
        isManual: true,
      );
    }

    test('one bundled pair maps to its eight physical Parashiyot', () {
      final placements =
          TefillinState.placements(project, [legacyPair()])['legacy-pair']!;

      expect(placements, hasLength(8));
      expect(
        placements.map(
            (piece) => (piece.pair, piece.side, piece.parshiya, piece.lines)),
        [
          (1, TefillinSide.head, 1, 4),
          (1, TefillinSide.head, 2, 4),
          (1, TefillinSide.head, 3, 4),
          (1, TefillinSide.head, 4, 4),
          (1, TefillinSide.hand, 1, 7),
          (1, TefillinSide.hand, 2, 7),
          (1, TefillinSide.hand, 3, 7),
          (1, TefillinSide.hand, 4, 7),
        ],
      );
    });

    test('an invalid slot stays visible even when it has no valid output', () {
      final flagged = Project(
        id: project.id,
        name: project.name,
        type: project.type,
        price: project.price,
        expenses: project.expenses,
        currency: project.currency,
        targetDaily: project.targetDaily,
        targetMonthly: project.targetMonthly,
        dailyGoalInLines: project.dailyGoalInLines,
        tefillinFlags: const {'3:head:2': TefillinState.voidFlag},
      );

      final slot = TefillinState.slots(flagged, const []).singleWhere((item) =>
          item.pair == 3 &&
          item.parshiya == 2 &&
          item.side == TefillinSide.head);
      expect(slot.state, SlotState.voided);
    });

    test('invalidating one legacy Parashah preserves the other seven', () {
      final result = WorkCorrection.markTefillinInvalid(
        history: [legacyPair()],
        project: project,
        pair: 1,
        side: TefillinSide.head,
        parshiya: 2,
      );
      final fragments =
          result.history.where((item) => item.id != 'legacy-pair').toList();

      expect(fragments, hasLength(8));
      expect(fragments.where((item) => item.isInvalid), hasLength(1));
      expect(
        fragments.singleWhere((item) => item.isInvalid).parshiya,
        2,
      );
      expect(
        fragments.fold(Duration.zero, (sum, item) => sum + item.duration),
        const Duration(minutes: 104),
      );
      expect(
        TefillinState.slots(project, result.history)
            .where((slot) => slot.state == SlotState.done),
        hasLength(7),
      );
      final restored =
          result.undo().singleWhere((item) => item.id == 'legacy-pair');
      expect(
        restored.isDeleted,
        isFalse,
      );
      expect(restored.duration, const Duration(minutes: 104));
    });

    test('cascade deletes only this and later Parashiyot in one set', () {
      final result = WorkCorrection.deleteTefillinFrom(
        history: [legacyPair()],
        project: project,
        pair: 1,
        side: TefillinSide.head,
        parshiya: 2,
      );
      final live = result.history.where((item) => !item.isDeleted).toList();

      expect(live, hasLength(5));
      expect(
          live.where((item) => item.tefillinType == 'head').single.parshiya, 1);
      expect(live.where((item) => item.tefillinType == 'hand'), hasLength(4));
      expect(
        live.fold(Duration.zero, (sum, item) => sum + item.duration),
        const Duration(minutes: 68),
      );
    });
  });
}
