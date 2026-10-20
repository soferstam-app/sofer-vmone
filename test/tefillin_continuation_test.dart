import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/tefillin_state.dart';
import 'package:sofer_vmone/logic/tefillin_units.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  final project = Project(
    id: 'p',
    name: 'תפילין',
    type: ProjectType.tefillin,
    price: 1000,
    expenses: 0,
    targetDaily: 0,
    targetMonthly: 0,
    targetUnits: 3,
  );
  WorkSession part(int parshiya,
          {int pair = 2, String side = 'head', int end = 0}) =>
      WorkSession(
        id: '$pair-$side-$parshiya',
        projectId: 'p',
        startTime: DateTime(2026, 10, 1, 9),
        endTime: DateTime(2026, 10, 1, 10),
        amount: 1,
        startLine: 0,
        endLine: end,
        description: '',
        isManual: true,
        pairIndex: pair,
        tefillinType: side,
        parshiya: parshiya,
      );

  test('a completed Parashah offers the next in the same set', () {
    final next = TefillinState.continuations(project, [part(1), part(2)]);
    expect(next, hasLength(1));
    expect(next.single.pair, 2);
    expect(next.single.side, TefillinSide.head);
    expect(next.single.parshiya, 3);
    expect(next.single.linesWritten, 0);
  });

  test('partial work is continued before the next Parashah', () {
    final next =
        TefillinState.continuations(project, [part(1), part(2, end: 2)]);
    expect(next.single.parshiya, 2);
    expect(next.single.linesWritten, 2);
  });

  test('invalid and deleted work never unlocks the next Parashah', () {
    for (final missing in [
      part(2).copyWith(isInvalid: true),
      part(2).copyWith(isDeleted: true)
    ]) {
      final next = TefillinState.continuations(project, [part(1), missing]);
      expect(next.single.parshiya, 2);
    }
    final flagged = project.copyWith(tefillinFlags: {'2:head:2': 'void'});
    expect(TefillinState.continuations(flagged, [part(1), part(2)]), isEmpty);
  });

  test('a completed head continues on the hand of the same pair', () {
    final next = TefillinState.continuations(
        project, [for (var p = 1; p <= 4; p++) part(p)]);
    expect(next.single.pair, 2);
    expect(next.single.side, TefillinSide.hand);
    expect(next.single.parshiya, 1);
  });

  test('fully completed pairs and new projects do not offer existing work', () {
    expect(TefillinState.continuations(project, []), isEmpty);
    expect(
        TefillinState.continuations(project, [
          for (final side in ['head', 'hand'])
            for (var p = 1; p <= 4; p++) part(p, side: side),
        ]),
        isEmpty);
  });

  test('old positions follow their own pair rather than the furthest work', () {
    final next = TefillinState.positionAfterCompleted(
      project: project,
      history: [part(1), part(2), part(1, pair: 3)],
      page: 10,
      line: 4,
    );
    expect(next, (page: 11, line: 1));
  });

  test('position repair resumes partial work and stops at invalidation', () {
    expect(
        TefillinState.positionAfterCompleted(
          project: project,
          history: [part(1), part(2, end: 2)],
          page: 9,
          line: 4,
        ),
        (page: 10, line: 3));
    expect(
        TefillinState.positionAfterCompleted(
          project: project.copyWith(tefillinFlags: {'2:head:2': 'void'}),
          history: [part(1), part(2)],
          page: 9,
          line: 4,
        ),
        (page: 10, line: 1));
  });
}
