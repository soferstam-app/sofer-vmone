// Money that actually arrived, and the year it belongs to.
//
// The annual report used to call units-written times price "income". It is not:
// it is what the writing was worth. Work finished in Elul and paid for in
// Tishrei landed in the wrong year, work never paid for landed in the report
// anyway, and a price raised afterwards rewrote a year already filed.
//
// A record per payment rather than a "paid" flag, because a sefer torah is paid
// for in stages and one amount with one date describes none of that.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/annual_report.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/merge_service.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  final project = Project(
    id: 'p1',
    name: 'ספר תורה',
    type: ProjectType.sefer,
    price: 400,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 42,
    totalPages: 245,
  );

  Payment paid(double amount, DateTime on,
          {Currency currency = Currency.ils, bool deleted = false}) {
    final p = Payment(
      id: 'y${amount.toInt()}${on.month}',
      projectId: 'p1',
      amount: amount,
      currency: currency,
      receivedAt: on,
    );
    return deleted ? p.copyWith(isDeleted: true) : p;
  }

  AnnualReport report(List<Payment> payments) => AnnualReport.forYear(
        year: 2026,
        projects: [project],
        history: const [],
        expenses: const [],
        dayStart: DayStart.midnight,
        payments: payments,
      );

  group('a payment carries what every record carries', () {
    test('it survives a round trip', () {
      final p = paid(12000, DateTime(2026, 5, 3))
          .copyWith(method: 'העברה', notes: 'מקדמה');
      final back = Payment.fromJson(p.toJson());
      expect(back.amount, 12000);
      expect(back.receivedAt, DateTime(2026, 5, 3));
      expect(back.method, 'העברה');
      expect(back.notes, 'מקדמה');
    });

    test('an id is the only thing it insists on', () {
      expect(() => Payment.fromJson({'amount': 100}),
          throwsA(isA<FormatException>()));
      expect(Payment.fromJson({'id': 'y1'}).amount, 0);
    });

    test('a field from a later version comes back untouched', () {
      final json = paid(500, DateTime(2026, 5, 3)).toJson()
        ..['invoiceNumber'] = 'A-1042';
      expect(Payment.fromJson(json).toJson()['invoiceNumber'], 'A-1042');
    });

    test('deleting is two registers, and an edit does not undo it', () {
      final gone = paid(500, DateTime(2026, 5, 3)).copyWith(isDeleted: true);
      expect(gone.isDeleted, isTrue);
      expect(gone.copyWith(notes: 'מאוחר').isDeleted, isTrue);
    });

    test('two devices keep both, and the deletion stands', () {
      final out = MergeService.mergeBackup(
        localProjects: const [], localHistory: const [], localExpenses: const [],
        incomingProjects: const [], incomingHistory: const [],
        incomingExpenses: const [],
        localPayments: [paid(500, DateTime(2026, 5, 3)).copyWith(isDeleted: true)],
        incomingPayments: [paid(500, DateTime(2026, 5, 3)).copyWith(notes: 'x')],
      );
      expect(out.payments.single.isDeleted, isTrue);
    });
  });

  group('income is the month the money arrived in', () {
    test('an instalment lands on its own date', () {
      final r = report([
        paid(12000, DateTime(2026, 3, 10)),
        paid(28000, DateTime(2026, 9, 4)),
      ]);
      expect(r.months[2].income.single(Currency.ils)!.amount, 12000);
      expect(r.months[8].income.single(Currency.ils)!.amount, 28000);
      expect(r.income.single(Currency.ils)!.amount, 40000);
    });

    test('and not on the month the work was done', () {
      // The whole point: writing finished in one year and paid for in the next
      // belongs to the year it was paid.
      final r = AnnualReport.forYear(
        year: 2026,
        projects: [project],
        history: const [],
        expenses: const [],
        dayStart: DayStart.midnight,
        payments: [paid(5000, DateTime(2025, 12, 20))],
      );
      expect(r.income.single(Currency.ils)!.amount, 0);
    });

    test('a deleted payment is not income', () {
      expect(
          report([paid(500, DateTime(2026, 5, 3), deleted: true)])
              .income
              .single(Currency.ils)!
              .amount,
          0);
    });

    test('two currencies are kept apart', () {
      final r = report([
        paid(12000, DateTime(2026, 3, 10)),
        paid(400, DateTime(2026, 4, 10), currency: const Currency('USD')),
      ]);
      expect(r.income.isMixed, isTrue);
    });
  });

  group('what the writing was worth is a second figure', () {
    test('and it is not the same as what came in', () {
      final r = AnnualReport.forYear(
        year: 2026,
        projects: [project],
        history: [
          WorkSession(
            id: 's1',
            projectId: 'p1',
            startTime: DateTime(2026, 5, 4, 9),
            endTime: DateTime(2026, 5, 4, 11),
            amount: 1,
            startLine: 1,
            endLine: 42,
            linesPerPageAtEntry: 42,
            description: '',
            isManual: true,
            workingDateAtEntry: DateTime(2026, 5, 4),
          )
        ],
        expenses: const [],
        dayStart: DayStart.midnight,
        payments: const [],
      );
      // A page written, nothing yet paid for it.
      expect(r.workValue.single(Currency.ils)!.amount, 400);
      expect(r.income.single(Currency.ils)!.amount, 0);
    });
  });
}
