import '../models.dart';
import 'currency.dart';
import 'date_logic.dart';
import 'expense_logic.dart';
import 'hebrew_clock.dart';
import 'profit_calculator.dart';

/// A year's income and costs, month by month, for the writer's accountant.
///
/// Every figure in it already existed somewhere in the app; nothing had ever
/// gathered them into the shape a self-employed sofer is actually asked for
/// once a year.
///
/// **Counted in Gregorian months, alone among everything here.** The rest of
/// the app reckons in the Hebrew calendar because that is how the work is
/// thought about — but a tax year is January to December, set by an authority
/// that does not care how the writer counts his days. Reporting Tishrei to Elul
/// to a tax office would be handing them a year that does not exist.
/// Income less costs, when there is one currency to say it in.
///
/// Decided by the currencies actually recorded, not by the fallback. Asking
/// each side for its own single() gave an empty side a zero in the *default*
/// currency, which then disagreed with the side that had data: a year holding
/// nothing but dollars reported "more than one currency" and refused to state
/// a net at all. The fallback is only for the case where there is no data on
/// either side, where zero is zero in any currency.
Money? _netOf(MoneyTotal income, MoneyTotal expenses, Currency fallback) {
  final present = {...income.currencies, ...expenses.currencies};
  if (present.length > 1) return null;
  final currency = present.isEmpty ? fallback : present.first;
  return income.single(currency)! - expenses.single(currency)!;
}

class AnnualReport {
  final int year;
  final List<ReportMonth> months;

  /// Every currency the year touched — commissions and expenses alike.
  ///
  /// More than one means [income] and [expenses] cannot be stated as a single
  /// number, and [net] returns null. Almost always there is exactly one.
  final Set<Currency> currenciesPresent;

  const AnnualReport({
    required this.year,
    required this.months,
    required this.currenciesPresent,
  });

  /// Money that actually arrived, by the date it arrived.
  MoneyTotal get income => _sum((m) => m.income);

  /// What the year's writing was worth at the agreed prices. Not the same
  /// question, and not a figure for a tax return: it counts work that has not
  /// been paid for and misses payments for work done in another year.
  MoneyTotal get workValue => _sum((m) => m.workValue);

  MoneyTotal get expenses => _sum((m) => m.expenses);

  /// Income less costs. Null when the year holds more than one currency, since
  /// there is no single number to state.
  Money? net(Currency fallback) => _netOf(income, expenses, fallback);

  MoneyTotal _sum(MoneyTotal Function(ReportMonth) of) {
    final total = MoneyTotal();
    for (final month in months) {
      for (final part in of(month).parts) {
        total.add(part);
      }
    }
    return total;
  }

  static AnnualReport forYear({
    required int year,
    required Iterable<Project> projects,
    required Iterable<WorkSession> history,
    required Iterable<Expense> expenses,
    required DayStart dayStart,
    Iterable<Proofread> proofreads = const [],
    Iterable<Payment> payments = const [],
  }) {
    final live = projects.where((p) => !p.isDeleted).toList();
    final months = <ReportMonth>[];
    final currencies = <Currency>{};

    for (var month = 1; month <= 12; month++) {
      final produced = MoneyTotal();
      final earned = MoneyTotal();
      final spent = MoneyTotal();

      // Income is money that arrived, on the date it arrived. Work finished in
      // Elul and paid for in Tishrei belongs to Tishrei, and work never paid
      // for belongs to no year at all.
      for (final p in payments) {
        if (p.isDeleted || p.amount == 0) continue;
        if (p.receivedAt.year != year || p.receivedAt.month != month) continue;
        earned.addAmount(p.amount, p.currency);
        currencies.add(p.currency);
      }

      for (final project in live) {
        // Backlog entries record work done before the app existed and were
        // never paid for in this year — including them would invent income.
        final inMonth = history.where((s) =>
            s.projectId == project.id &&
            !s.isDeleted &&
            !s.backlogOnly &&
            _inGregorianMonth(s, year, month, dayStart));
        if (inMonth.isEmpty) continue;

        final units = ProfitCalculator.billableUnits(project, inMonth);
        if (units <= 0) continue;

        currencies.add(project.currency);
        // The value of what was written this month. Not income — see
        // [ReportMonth.workValue].
        produced.addAmount(units * project.price, project.currency);
        // `project.expenses` is a per-unit *estimate* the writer typed into the
        // commission form. It does not belong in a year handed to an
        // accountant beside real receipts, and counting both would charge the
        // same parchment twice. It still drives the per-project profit figures,
        // where an estimate is what is wanted.
      }

      // Proofreading, charged to the month it was paid for — which is taken to
      // be the month the work came back, since that is when the bill lands. A
      // batch still out has not been paid for yet.
      for (final r in proofreads) {
        if (r.isDeleted || r.cost <= 0) continue;
        final when = r.doneAt ?? r.returnedAt;
        if (when == null || when.year != year || when.month != month) continue;
        spent.addAmount(r.cost, r.currency);
        currencies.add(r.currency);
      }

      // Expenses recorded in their own right: whatever falls in this month,
      // with a period expense contributing only its share of it.
      final recorded = ExpenseLogic.totalForMonth(
          DateTime(year, month), expenses,
          includeProjectAllocated: true);
      for (final part in recorded.parts) {
        spent.add(part);
        currencies.add(part.currency);
      }

      months.add(ReportMonth(
        year: year,
        month: month,
        income: earned,
        workValue: produced,
        expenses: spent,
      ));
    }

    return AnnualReport(
      year: year,
      months: months,
      currenciesPresent: currencies,
    );
  }

  /// Which Gregorian month a session was filed under.
  ///
  /// The working day, not the clock time: a sitting at half past midnight on
  /// the first of the month belongs to the month the writer was working in.
  static bool _inGregorianMonth(
      WorkSession session, int year, int month, DayStart dayStart) {
    final filed = DateLogic.workingDateOf(session, dayStart);
    return filed.year == year && filed.month == month;
  }
}

/// One month of the year.
class ReportMonth {
  final int year;
  final int month;
  /// Payments received in this month.
  final MoneyTotal income;

  /// Value of the writing done in this month, at the agreed prices. Shown
  /// beside the income so the gap between them is visible rather than implied.
  final MoneyTotal workValue;

  final MoneyTotal expenses;

  ReportMonth({
    required this.year,
    required this.month,
    required this.income,
    required this.workValue,
    required this.expenses,
  });

  bool get isEmpty =>
      income.isEmpty && expenses.isEmpty && workValue.isEmpty;

  /// Income less costs for the month, when both are in one currency.
  Money? net(Currency fallback) => _netOf(income, expenses, fallback);

  static const List<String> names = [
    'ינואר',
    'פברואר',
    'מרץ',
    'אפריל',
    'מאי',
    'יוני',
    'יולי',
    'אוגוסט',
    'ספטמבר',
    'אוקטובר',
    'נובמבר',
    'דצמבר',
  ];

  String get name => names[month - 1];
}
