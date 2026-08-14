import '../models.dart';
import 'calendar_days.dart';
import 'profit_calculator.dart';
import 'currency.dart';

/// A spending category and how it is normally charged against the work.
class ExpenseCategory {
  final String name;
  final ExpenseAllocation defaultAllocation;

  const ExpenseCategory(this.name, this.defaultAllocation);
}

/// Rules for attributing expenses to the work they belong to.
///
/// Where a cost lands differs by what was bought. Parchment is consumed by a
/// specific project; ink and tools are used up gradually; a writing room is
/// rented by the month. Charging everything to the month it was paid, as the
/// app did before, made per-project profit wrong for the costs that clearly
/// belong to one job.
class ExpenseLogic {
  const ExpenseLogic._();

  /// Suggested categories, each with the allocation it usually takes.
  ///
  /// The default is a starting point, not a rule — the user can change the
  /// allocation on any individual expense.
  static const List<ExpenseCategory> categories = [
    // Consumed by a specific piece of work
    ExpenseCategory('קלף מזוזות', ExpenseAllocation.project),
    ExpenseCategory('קלף תפילין', ExpenseAllocation.project),
    ExpenseCategory('קלף והגהות מגילות', ExpenseAllocation.project),
    ExpenseCategory('הגהות מזוזות', ExpenseAllocation.project),
    ExpenseCategory('הגהות תפילין', ExpenseAllocation.project),
    ExpenseCategory('מחיקות מזוזות', ExpenseAllocation.project),
    ExpenseCategory('תיקון סופרים', ExpenseAllocation.project),
    // May serve one project or several at once
    ExpenseCategory('משלוחים ונסיעות', ExpenseAllocation.project),
    // Used up gradually over a stretch of time
    ExpenseCategory('דיו, מי קלף, ציוד', ExpenseAllocation.period),
    ExpenseCategory('קולמוס מגילות', ExpenseAllocation.period),
    ExpenseCategory('קולמוס מזוזות', ExpenseAllocation.period),
    ExpenseCategory('קולמוס תש"י', ExpenseAllocation.period),
    ExpenseCategory('קולמוס תש"ר', ExpenseAllocation.period),
    ExpenseCategory('משקפיים', ExpenseAllocation.period),
    ExpenseCategory('שולחן, כסא, פנס, מכשיר אדים', ExpenseAllocation.period),
    // Belongs to the month it covers
    ExpenseCategory('חדר סופרים', ExpenseAllocation.month),
    ExpenseCategory('שונות', ExpenseAllocation.month),
    ExpenseCategory('קורס סת"ם', ExpenseAllocation.month),
    ExpenseCategory('תעודה', ExpenseAllocation.month),
  ];

  /// The allocation normally used for [categoryName]. Falls back to monthly
  /// for anything typed in freehand.
  static ExpenseAllocation defaultAllocationFor(String categoryName) {
    for (final c in categories) {
      if (c.name == categoryName) return c.defaultAllocation;
    }
    return ExpenseAllocation.month;
  }

  /// Human-readable label for an allocation.
  static String allocationLabel(ExpenseAllocation a) => switch (a) {
        ExpenseAllocation.project => 'לפי פרויקט',
        ExpenseAllocation.period => 'לפי תקופה',
        ExpenseAllocation.month => 'לפי חודש',
      };

  /// Total charged to [projectId] from expenses assigned to projects.
  ///
  /// An expense split across several projects contributes its even share. Kept
  /// apart by currency: what a commission is priced in and what its materials
  /// were bought in need not be the same, and there is no rate here to bridge
  /// them with.
  static MoneyTotal totalForProject(
      String projectId, Iterable<Expense> expenses) {
    final total = MoneyTotal();
    for (final e in expenses) {
      if (e.isDeleted) continue;
      if (e.allocation != ExpenseAllocation.project) continue;
      if (!e.projectIds.contains(projectId)) continue;
      total.addAmount(e.amountPerProject, e.currency);
    }
    return total;
  }

  /// Total charged to the calendar month containing [month].
  ///
  /// Monthly expenses count in full. Period expenses contribute the share of
  /// their range that falls inside the month, so a year's supply of ink bought
  /// in Nisan is not charged entirely to Nisan.
  /// Kept apart by currency: a month's costs may have been paid in more than
  /// one, and adding those together produces a number that is not a total of
  /// anything. Almost always there is exactly one.
  /// Set [includeProjectAllocated] where the question is "what did this month
  /// cost" rather than "what does this month owe to no particular job".
  ///
  /// Project-allocated expenses are charged to a commission, not to a month, so
  /// the per-project figures take them and this used to skip them entirely.
  /// That is right for a monthly overhead view and wrong for a tax year: a
  /// writer who bought three thousand shekels of parchment for one sefer, and
  /// filed it exactly as the app suggests, saw none of it in his annual costs.
  static MoneyTotal totalForMonth(DateTime month, Iterable<Expense> expenses,
      {bool includeProjectAllocated = false}) {
    final monthStart = DateTime(month.year, month.month);
    final monthEnd = DateTime(month.year, month.month + 1);

    final total = MoneyTotal();
    for (final e in expenses) {
      if (e.isDeleted) continue;

      switch (e.allocation) {
        case ExpenseAllocation.month:
          if (e.date.year == month.year && e.date.month == month.month) {
            total.addAmount(e.amount, e.currency);
          }
        case ExpenseAllocation.period:
          total.addAmount(
              _periodShareInRange(e, monthStart, monthEnd), e.currency);
        case ExpenseAllocation.project:
          // Charged to a commission rather than to a month — but still money
          // that left the writer's pocket on a date.
          if (includeProjectAllocated &&
              e.date.year == month.year &&
              e.date.month == month.month) {
            total.addAmount(e.amount, e.currency);
          }
      }
    }
    return total;
  }

  /// Portion of a period expense falling between [from] (inclusive) and [to]
  /// (exclusive), pro-rated by days.
  static double _periodShareInRange(
      Expense e, DateTime from, DateTime to) {
    final start = e.periodStart ?? e.date;
    final end = e.periodEnd ?? e.date;

    // A zero or inverted range degenerates to a single day: charge it whole if
    // that day falls in the window.
    // Days counted as a calendar counts them — a range spanning a clock change
    // came out a day short, which quietly inflated every day's share of it.
    final totalDays = CalendarDays.inclusiveLength(start, end);
    if (totalDays <= 1) {
      return (!start.isBefore(from) && start.isBefore(to)) ? e.amount : 0;
    }

    final overlapStart = start.isAfter(from) ? start : from;
    final overlapEnd = end.isBefore(to) ? end : CalendarDays.addDays(to, -1);
    final overlapDays = CalendarDays.inclusiveLength(overlapStart, overlapEnd);
    if (overlapDays <= 0) return 0;

    return e.amount * (overlapDays / totalDays);
  }

  /// What materials have actually cost per unit on past work of [type].
  ///
  /// Built from the expenses already recorded on the expenses screen and the
  /// units those projects produced, so a quote charges what parchment really
  /// costs this writer instead of a number typed from memory.
  ///
  /// Only project-allocated expenses count: ink bought for a season and a
  /// monthly room rental are overheads, not the material cost of one more
  /// mezuza. Returns null when there is nothing to learn from.
  static double? averagePerUnit(
    ProjectType type,
    Iterable<Project> projects,
    Iterable<WorkSession> history,
    Iterable<Expense> expenses,
  ) {
    var totalCost = 0.0;
    var totalUnits = 0.0;

    for (final project in projects.where((p) => p.type == type && !p.isDeleted)) {
      // Averaged only across commissions whose costs are in the currency the
      // commission itself is priced in. A per-unit figure mixing two of them
      // would be a number with no unit.
      final costs = totalForProject(project.id, expenses).single(project.currency);
      final cost = costs != null && costs.currency == project.currency
          ? costs.amount
          : 0.0;
      if (cost <= 0) continue;

      final sessions =
          history.where((s) => s.projectId == project.id && !s.isDeleted);
      final units = ProfitCalculator.billableUnits(project, sessions);
      if (units <= 0) continue;

      totalCost += cost;
      totalUnits += units;
    }

    if (totalUnits <= 0 || totalCost <= 0) return null;
    return totalCost / totalUnits;
  }

  /// Expenses that need a project chosen but have none, so the UI can warn
  /// rather than silently leave money unattributed.
  static List<Expense> unassigned(Iterable<Expense> expenses) => expenses
      .where((e) =>
          !e.isDeleted &&
          e.allocation == ExpenseAllocation.project &&
          e.projectIds.isEmpty)
      .toList();
}
