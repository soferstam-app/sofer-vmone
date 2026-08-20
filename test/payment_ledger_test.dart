// What has been paid on one commission, and what has not.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/payment_ledger.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  // A hundred a page, ten lines to a page.
  final project = Project(
    id: 'p1',
    name: 'ספר תורה',
    type: ProjectType.sefer,
    price: 100,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 10,
    totalPages: 245,
  );

  WorkSession pages(int count, {bool backlog = false}) => WorkSession(
        id: 'w$count$backlog',
        projectId: 'p1',
        startTime: DateTime(2026, 5, 4, 9),
        endTime: DateTime(2026, 5, 4, 11),
        amount: 1,
        startLine: 1,
        endLine: 10 * count,
        linesPerPageAtEntry: 10,
        description: '',
        isManual: true,
        backlogOnly: backlog,
      );

  Payment paid(double amount, {Currency currency = Currency.ils}) => Payment(
        id: 'y$amount$currency',
        projectId: 'p1',
        amount: amount,
        currency: currency,
        receivedAt: DateTime(2026, 5, 1),
      );

  PaymentLedger ledger(List<Payment> payments, List<WorkSession> history) =>
      PaymentLedger.of(
          project: project, allPayments: payments, history: history);

  group('what has come in', () {
    test('nothing, when nothing was recorded', () {
      final l = ledger(const [], [pages(3)]);
      expect(l.isEmpty, isTrue);
      expect(l.received.single(Currency.ils)!.amount, 0);
    });

    test('the instalments added up', () {
      final l = ledger([paid(4000), paid(8000)], [pages(3)]);
      expect(l.received.single(Currency.ils)!.amount, 12000);
    });

    test('a payment on another commission is not this one\'s', () {
      final other = Payment(
        id: 'z',
        projectId: 'p2',
        amount: 5000,
        receivedAt: DateTime(2026, 5, 1),
      );
      expect(ledger([other], [pages(3)]).received.single(Currency.ils)!.amount, 0);
    });

    test('a deleted payment is not counted', () {
      final gone = paid(4000).copyWith(isDeleted: true);
      expect(ledger([gone], [pages(3)]).received.single(Currency.ils)!.amount, 0);
    });
  });

  group('what is still owed', () {
    test('is measured against work done, not the whole job', () {
      // Three pages written at a hundred each. A writer part way through a
      // sefer is not owed the price of all of it.
      final l = ledger(const [], [pages(3)]);
      expect(l.earnedSoFar.amount, 300);
      expect(l.outstanding!.amount, 300);
    });

    test('falls as payments come in', () {
      expect(ledger([paid(100)], [pages(3)]).outstanding!.amount, 200);
    });

    test('is nothing once the work done has been paid for', () {
      expect(ledger([paid(300)], [pages(3)]).outstanding!.amount, 0);
    });

    test('is never negative — an advance is not a debt owed to the client', () {
      final l = ledger([paid(1000)], [pages(3)]);
      expect(l.outstanding!.amount, 0);
      expect(l.inAdvance!.amount, 700);
    });

    test('and there is no advance when there is a balance', () {
      expect(ledger([paid(100)], [pages(3)]).inAdvance, isNull);
    });

    test('backlog work is not owed for', () {
      // It records writing done before the app existed and was never billed
      // through it.
      final l = ledger(const [], [pages(3, backlog: true)]);
      expect(l.earnedSoFar.amount, 0);
    });
  });

  group('more than one currency', () {
    test('has no balance, because the subtraction means nothing', () {
      final l = ledger(
        [paid(100), paid(50, currency: const Currency('USD'))],
        [pages(3)],
      );
      expect(l.received.isMixed, isTrue);
      expect(l.outstanding, isNull);
      expect(l.inAdvance, isNull);
    });
  });

  group('the order they read in', () {
    test('newest first, which is what a writer is looking for', () {
      final older = Payment(
          id: 'a',
          projectId: 'p1',
          amount: 1,
          receivedAt: DateTime(2026, 1, 1));
      final newer = Payment(
          id: 'b',
          projectId: 'p1',
          amount: 2,
          receivedAt: DateTime(2026, 6, 1));
      expect(ledger([older, newer], [pages(3)]).payments.map((p) => p.id),
          ['b', 'a']);
    });
  });
}
