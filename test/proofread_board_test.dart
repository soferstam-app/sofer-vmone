// What is out for proofreading, what is waiting, and what it has cost.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/proofread_board.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Proofread r(
    String id,
    ProofreadStage stage, {
    String project = 'p1',
    DateTime? sent,
    DateTime? returned,
    double cost = 0,
    Currency currency = Currency.ils,
    int? findings,
    bool deleted = false,
  }) {
    final base = Proofread(
      id: id,
      projectId: project,
      stage: stage,
      sentAt: sent,
      returnedAt: returned,
      cost: cost,
      currency: currency,
      findings: findings,
      lastUpdated: DateTime(2026, 5, 1),
    );
    return deleted ? base.copyWith(isDeleted: true) : base;
  }

  group('what the board holds', () {
    test('deleted records are not on it', () {
      final board = ProofreadBoard.of([
        r('a', ProofreadStage.sent),
        r('b', ProofreadStage.sent, deleted: true),
      ]);
      expect(board.records.map((x) => x.id), ['a']);
    });

    test('one commission at a time, when asked', () {
      final board = ProofreadBoard.of([
        r('a', ProofreadStage.sent),
        r('b', ProofreadStage.sent, project: 'p2'),
      ], projectId: 'p2');
      expect(board.records.map((x) => x.id), ['b']);
    });

    test('ordered by stage, so the job reads in order', () {
      final board = ProofreadBoard.of([
        r('done', ProofreadStage.done),
        r('sent', ProofreadStage.sent),
        r('waiting', ProofreadStage.waiting),
        r('returned', ProofreadStage.returned),
      ]);
      expect(board.records.map((x) => x.id),
          ['waiting', 'sent', 'returned', 'done']);
    });
  });

  group('whose turn it is', () {
    final board = ProofreadBoard.of([
      r('w', ProofreadStage.waiting),
      r('s', ProofreadStage.sent),
      r('r', ProofreadStage.returned),
      r('d', ProofreadStage.done),
    ]);

    test('open is everything unfinished', () {
      expect(board.open.map((x) => x.id), ['w', 's', 'r']);
    });

    test('mine is what the sofer has to act on', () {
      // "With the magiah" is somebody else's turn. These two are his.
      expect(board.mine.map((x) => x.id), ['w', 'r']);
    });
  });

  group('out too long', () {
    test('counted from the day it was sent', () {
      final board = ProofreadBoard.of([
        r('old', ProofreadStage.sent, sent: DateTime(2026, 4, 1)),
        r('new', ProofreadStage.sent, sent: DateTime(2026, 5, 20)),
      ]);
      final late = board.overdue(days: 21, now: DateTime(2026, 5, 25));
      expect(late.map((x) => x.id), ['old']);
    });

    test('a batch already back is never late', () {
      final board = ProofreadBoard.of([
        r('back', ProofreadStage.returned,
            sent: DateTime(2026, 1, 1), returned: DateTime(2026, 4, 1)),
      ]);
      expect(board.overdue(now: DateTime(2026, 5, 25)), isEmpty);
    });

    test('nor is one that was never sent', () {
      final board = ProofreadBoard.of([r('w', ProofreadStage.waiting)]);
      expect(board.overdue(now: DateTime(2026, 5, 25)), isEmpty);
    });
  });

  group('what it cost', () {
    test('summed per currency', () {
      final board = ProofreadBoard.of([
        r('a', ProofreadStage.done, cost: 450),
        r('b', ProofreadStage.done, cost: 300),
      ]);
      expect(board.spent.single(Currency.ils)!.amount, 750);
    });

    test('two currencies are not added together', () {
      final board = ProofreadBoard.of([
        r('a', ProofreadStage.done, cost: 450),
        r('b', ProofreadStage.done, cost: 100, currency: const Currency('USD')),
      ]);
      expect(board.spent.isMixed, isTrue);
      expect(board.spent.single(Currency.ils), isNull);
    });

    test('nothing spent is zero, not absent', () {
      final board = ProofreadBoard.of([r('a', ProofreadStage.waiting)]);
      expect(board.spent.single(Currency.ils)!.amount, 0);
    });
  });

  group('corrections that came back', () {
    test('averaged over the batches anyone wrote down', () {
      final board = ProofreadBoard.of([
        r('a', ProofreadStage.done, findings: 4),
        r('b', ProofreadStage.done, findings: 2),
        r('c', ProofreadStage.done),
      ]);
      expect(board.averageFindings, 3);
    });

    test('null when nobody did — an average of nothing is not zero', () {
      final board = ProofreadBoard.of([r('a', ProofreadStage.done)]);
      expect(board.averageFindings, isNull);
    });

    test('a clean return counts as an observation', () {
      final board = ProofreadBoard.of([
        r('a', ProofreadStage.done, findings: 0),
        r('b', ProofreadStage.done, findings: 4),
      ]);
      expect(board.averageFindings, 2);
    });
  });
}
