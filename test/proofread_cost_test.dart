// Proofreading is a cost, so it belongs in the year the accountant is given.
//
// "הגהות מזוזות" and "הגהות תפילין" were already expense categories; a batch
// recorded on the board is the same money, and leaving it out would report a
// year that understates what the work cost.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/annual_report.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
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

  Proofread batch({
    required double cost,
    DateTime? returned,
    DateTime? done,
    Currency currency = Currency.ils,
    bool deleted = false,
  }) {
    final r = Proofread(
      id: 'r${cost.toInt()}${returned?.month ?? 0}${done?.month ?? 0}',
      projectId: 'p1',
      cost: cost,
      currency: currency,
      returnedAt: returned,
      doneAt: done,
      stage: done != null ? ProofreadStage.done : ProofreadStage.returned,
    );
    return deleted ? r.copyWith(isDeleted: true) : r;
  }

  AnnualReport report(List<Proofread> proofreads) => AnnualReport.forYear(
        year: 2026,
        projects: [project],
        history: const [],
        expenses: const [],
        dayStart: DayStart.midnight,
        proofreads: proofreads,
      );

  test('a paid batch lands in the month it came back', () {
    final r = report([batch(cost: 450, returned: DateTime(2026, 5, 20))]);
    expect(r.months[4].expenses.single(Currency.ils)!.amount, 450);
    expect(r.months[3].expenses.single(Currency.ils)!.amount, 0);
  });

  test('the month it was finished wins where both are recorded', () {
    // The bill lands when the work comes back to the sofer corrected.
    final r = report([
      batch(cost: 450, returned: DateTime(2026, 5, 20), done: DateTime(2026, 6, 2))
    ]);
    expect(r.months[5].expenses.single(Currency.ils)!.amount, 450);
  });

  test('a batch still out has not been paid for', () {
    final r = report([batch(cost: 450)]);
    expect(r.expenses.single(Currency.ils)!.amount, 0);
  });

  test('a deleted batch is not a cost', () {
    final r = report(
        [batch(cost: 450, returned: DateTime(2026, 5, 20), deleted: true)]);
    expect(r.expenses.single(Currency.ils)!.amount, 0);
  });

  test('a batch with no cost recorded adds nothing', () {
    final r = report([batch(cost: 0, returned: DateTime(2026, 5, 20))]);
    expect(r.expenses.single(Currency.ils)!.amount, 0);
  });

  test('a cost in another currency is kept apart, not added', () {
    final r = report([
      batch(cost: 450, returned: DateTime(2026, 5, 20)),
      batch(
          cost: 100,
          returned: DateTime(2026, 6, 20),
          currency: const Currency('USD')),
    ]);
    expect(r.expenses.isMixed, isTrue);
    expect(r.currenciesPresent, containsAll([Currency.ils, const Currency('USD')]));
  });

  test('a year with no proofreading reads exactly as it did before', () {
    expect(report(const []).expenses.single(Currency.ils)!.amount, 0);
  });
}
