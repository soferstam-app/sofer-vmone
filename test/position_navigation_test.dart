import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/mezuza_state.dart';
import 'package:sofer_vmone/logic/tefillin_position.dart';
import 'package:sofer_vmone/logic/tefillin_state.dart';
import 'package:sofer_vmone/logic/tefillin_units.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Project project(ProjectType type) => Project(
        id: 'p',
        name: 'x',
        type: type,
        price: 100,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        targetUnits: 6,
      );

  WorkSession session({
    required String id,
    int amount = 1,
    int endLine = 0,
    int? mezuza,
    int minute = 0,
  }) =>
      WorkSession(
        id: id,
        projectId: 'p',
        startTime: DateTime(2026, 8, 1, 9, minute),
        endTime: DateTime(2026, 8, 1, 9, minute + 1),
        amount: amount,
        startLine: 0,
        endLine: endLine,
        mezuzaIndex: mezuza,
        description: '',
        isManual: false,
      );

  group('individual mezuzot', () {
    test('legacy counts and new indexed stretches form one board', () {
      final slots = MezuzaState.slots(project(ProjectType.mezuza), [
        session(id: 'old', amount: 2),
        session(id: 'm4a', mezuza: 4, endLine: 6),
        session(id: 'm4b', mezuza: 4, endLine: 5),
      ]);

      expect(slots[0].state, MezuzaSlotState.done);
      expect(slots[1].state, MezuzaSlotState.done);
      expect(slots[3].state, MezuzaSlotState.partial);
      expect(slots[3].linesWritten, 11);
      expect(slots[3].resumeLine, 12);
    });

    test('the picker offers stopped work and untouched destinations', () {
      const slots = [
        MezuzaSlot(index: 1, state: MezuzaSlotState.done, linesWritten: 22),
        MezuzaSlot(index: 2, state: MezuzaSlotState.partial, linesWritten: 9),
        MezuzaSlot(index: 3, state: MezuzaSlotState.partial, linesWritten: 4),
        MezuzaSlot(index: 4, state: MezuzaSlotState.empty, linesWritten: 0),
      ];
      final picks = MezuzaPicks.from(slots, current: 3);

      expect(picks.stopped.map((s) => s.index), [2]);
      expect(picks.nextUp.map((s) => s.index), [4]);
    });

    test('a later counted record does not collide with an indexed mezuza', () {
      final history = [
        session(id: 'smart-1', mezuza: 1),
        session(id: 'manual-1', minute: 2),
      ];
      final slots = MezuzaState.slots(project(ProjectType.mezuza), history);

      expect(slots[0].state, MezuzaSlotState.done);
      expect(slots[1].state, MezuzaSlotState.done);
      expect(
          MezuzaState.nextWritingPosition(project(ProjectType.mezuza), history),
          (page: 3, line: 1));
    });

    test('three complete counted mezuzot advance to mezuza four', () {
      final history = [session(id: 'manual-3', amount: 3)];
      expect(
          MezuzaState.nextWritingPosition(project(ProjectType.mezuza), history),
          (page: 4, line: 1));
    });
  });

  group('tefillin order inside one set', () {
    const current =
        TefillinPosition(pair: 1, side: TefillinSide.head, parshiya: 1);

    test('does not offer a later parshiya while its predecessor is partial',
        () {
      const slots = [
        TefillinSlot(
            pair: 1,
            side: TefillinSide.head,
            parshiya: 1,
            state: SlotState.partial,
            linesWritten: 2),
        TefillinSlot(pair: 1, side: TefillinSide.head, parshiya: 2),
        TefillinSlot(pair: 2, side: TefillinSide.head, parshiya: 1),
      ];

      final picks = TefillinPicks.from(slots, current: current);
      expect(picks.nextUp.any((s) => s.pair == 1 && s.parshiya == 2), isFalse);
      expect(picks.nextUp.any((s) => s.pair == 2 && s.parshiya == 1), isTrue);
    });

    test('offers it once the predecessor is complete', () {
      const slots = [
        TefillinSlot(
            pair: 1,
            side: TefillinSide.head,
            parshiya: 1,
            state: SlotState.done),
        TefillinSlot(pair: 1, side: TefillinSide.head, parshiya: 2),
      ];

      final picks = TefillinPicks.from(slots, current: current);
      expect(picks.nextUp.single.parshiya, 2);
    });

    test('does not offer an already-started later parshiya out of order', () {
      const slots = [
        TefillinSlot(
            pair: 1,
            side: TefillinSide.head,
            parshiya: 1,
            state: SlotState.partial,
            linesWritten: 2),
        TefillinSlot(
            pair: 1,
            side: TefillinSide.head,
            parshiya: 2,
            state: SlotState.partial,
            linesWritten: 1),
      ];

      final picks = TefillinPicks.from(slots, current: current);
      expect(picks.stopped, isEmpty);
      expect(TefillinState.canWrite(slots.last, slots), isFalse);
    });

    test('removing a rejected parshiya removes only it and later ones', () {
      WorkSession parshiya(String id, int pair, String side, int number) =>
          WorkSession(
            id: id,
            projectId: 'p',
            startTime: DateTime(2026, 8, 1, 9),
            endTime: DateTime(2026, 8, 1, 10),
            amount: 1,
            startLine: 0,
            endLine: 0,
            tefillinType: side,
            parshiya: number,
            pairIndex: pair,
            description: '',
            isManual: false,
          );

      final removed = TefillinState.removeFrom(
        history: [
          parshiya('p1', 1, 'head', 1),
          parshiya('p2', 1, 'head', 2),
          parshiya('p3', 1, 'head', 3),
          parshiya('hand', 1, 'hand', 3),
          parshiya('other-pair', 2, 'head', 3),
        ],
        projectId: 'p',
        pair: 1,
        side: TefillinSide.head,
        parshiya: 2,
      );

      expect(removed.firstWhere((s) => s.id == 'p1').isDeleted, isFalse);
      expect(removed.firstWhere((s) => s.id == 'p2').isDeleted, isTrue);
      expect(removed.firstWhere((s) => s.id == 'p3').isDeleted, isTrue);
      expect(removed.firstWhere((s) => s.id == 'hand').isDeleted, isFalse);
      expect(
          removed.firstWhere((s) => s.id == 'other-pair').isDeleted, isFalse);
    });
  });

  test('new position identities survive JSON and ordinary edits', () {
    final original = session(id: 'identity', mezuza: 7).copyWith();
    final roundTrip = WorkSession.fromJson({
      ...original.toJson(),
      'pairIndex': 3,
      'tefillinType': 'head',
      'parshiya': 1,
    });

    expect(roundTrip.mezuzaIndex, 7);
    expect(roundTrip.copyWith(description: 'edited').pairIndex, 3);
  });
}
