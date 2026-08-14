import '../models.dart';
import 'currency.dart';
import 'profit_calculator.dart';

/// What has been paid on one commission, and what has not.
///
/// Two figures a sofer wants and the app could not answer: how much of this job
/// has actually come in, and how much is still owed. Both are money, so both
/// are kept per currency — a job priced in shekels and part-paid in dollars is
/// unusual and entirely possible, and adding those would give a number that is
/// not a total of anything.
class PaymentLedger {
  /// Payments received against this commission, newest first.
  final List<Payment> payments;

  /// Money that has arrived.
  final MoneyTotal received;

  /// What the writing done so far is worth at the agreed price.
  ///
  /// Not what the whole job is worth: a writer half way through a sefer is not
  /// owed the whole price of it, and showing him that as outstanding would be
  /// inventing a debt.
  final Money earnedSoFar;

  const PaymentLedger._({
    required this.payments,
    required this.received,
    required this.earnedSoFar,
  });

  static PaymentLedger of({
    required Project project,
    required Iterable<Payment> allPayments,
    required Iterable<WorkSession> history,
  }) {
    final mine = allPayments
        .where((p) => !p.isDeleted && p.projectId == project.id)
        .toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

    final received = MoneyTotal();
    for (final p in mine) {
      if (p.amount != 0) received.addAmount(p.amount, p.currency);
    }

    // Backlog entries record work done before the app existed and were never
    // billed through it, so they are not part of what this commission owes.
    final billable = history.where((s) =>
        s.projectId == project.id && !s.isDeleted && !s.backlogOnly);
    final units = ProfitCalculator.billableUnits(project, billable);

    return PaymentLedger._(
      payments: mine,
      received: received,
      earnedSoFar: Money(units * project.price, project.currency),
    );
  }

  /// What is still owed for work already done, or null when the payments are in
  /// a currency the commission is not priced in — there is no subtraction there
  /// that means anything.
  ///
  /// Never negative: a writer paid in advance is not owed a debt by his client,
  /// and showing minus twelve thousand as "outstanding" would read as one.
  Money? get outstanding {
    final paid = received.single(earnedSoFar.currency);
    if (paid == null || paid.currency != earnedSoFar.currency) return null;
    final left = earnedSoFar.amount - paid.amount;
    return Money(left > 0 ? left : 0, earnedSoFar.currency);
  }

  /// Paid more than the work done so far comes to — an advance, which is
  /// ordinary at the start of a commission and worth saying rather than hiding.
  Money? get inAdvance {
    final paid = received.single(earnedSoFar.currency);
    if (paid == null || paid.currency != earnedSoFar.currency) return null;
    final over = paid.amount - earnedSoFar.amount;
    return over > 0 ? Money(over, earnedSoFar.currency) : null;
  }

  bool get isEmpty => payments.isEmpty;
}
