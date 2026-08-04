import '../models.dart';
import 'date_logic.dart';
import 'hebrew_clock.dart';
import 'hebrew_work_calendar.dart';
import 'production_calculator.dart';
import 'profit_calculator.dart';

/// How much work is left on a project, and when it will be finished.
class CompletionEstimate {
  /// Size of the whole job in billable units — pages, mezuzot or sets.
  final double totalUnits;
  final double doneUnits;
  final double remainingUnits;

  /// Measured output on a day the writer actually writes — not an average over
  /// the calendar, which Shabbatot and festivals would drag down.
  final double unitsPerWorkDay;

  /// False when there was not enough recorded work and the daily target was
  /// used instead. A screen should say so rather than present a guess as a
  /// measurement.
  final bool paceMeasured;

  final WorkPlan plan;

  const CompletionEstimate({
    required this.totalUnits,
    required this.doneUnits,
    required this.remainingUnits,
    required this.unitsPerWorkDay,
    required this.paceMeasured,
    required this.plan,
  });

  /// 0 to 1. Clamped, since a writer can overshoot a stated page count.
  double get progress =>
      totalUnits <= 0 ? 0 : (doneUnits / totalUnits).clamp(0.0, 1.0);

  /// Days of actual writing still to do.
  double get workDaysLeft => plan.workDaysNeeded;
}

/// Turns recorded work into a delivery date.
///
/// Both the project screen and the price quote go through here, so a date
/// promised to a client in a quote is produced by exactly the same arithmetic
/// as the date shown once the job is under way.
class CompletionEstimator {
  const CompletionEstimator._();

  /// Units of [project] already written, counting backlog entries — they are
  /// real work even though they carry no timing.
  static double doneUnits(Project project, Iterable<WorkSession> history) {
    final sessions = history.where((s) => s.projectId == project.id && !s.isDeleted);
    return ProfitCalculator.billableUnits(project, sessions);
  }

  /// What the writer gets done on a day he actually writes.
  ///
  /// The denominator is **days he wrote on**, counted from the records
  /// themselves. It used to be every working day between his first session and
  /// his last, which is a different quantity and a far smaller one: a sofer who
  /// opened a commission in Tishrei, wrote one page, and started in earnest in
  /// Shevat had four idle months in the divisor. His pace came out at a
  /// fraction of the truth and the delivery date years away, which is exactly
  /// what writers reported — "I do not understand what these figures are."
  ///
  /// Days he did not write are not slow days. They are days that say nothing
  /// about how fast he writes, and a forecast built on them is a forecast about
  /// his calendar rather than about his hand.
  ///
  /// The rules are still needed downstream, to turn a number of writing days
  /// into a date on a calendar that has Shabbatot and festivals in it.
  ///
  /// Returns null when there is nothing to measure.
  static double? measuredPace(
    Project project,
    Iterable<WorkSession> history,
    WorkCalendarRules rules, {
    DayStart dayStart = DayStart.midnight,
  }) {
    final sessions = history
        .where((s) =>
            s.projectId == project.id && !s.isDeleted && !s.backlogOnly)
        .toList();
    if (sessions.isEmpty) return null;

    final units = ProfitCalculator.billableUnits(project, sessions);
    if (units <= 0) return null;

    // The working day each session was filed under, so two sittings either side
    // of midnight are one day and not two — which would halve the pace of
    // anyone who writes late.
    final daysWritten = <DateTime>{};
    for (final s in sessions) {
      final filed = DateLogic.workingDateOf(s, dayStart);
      daysWritten.add(DateTime(filed.year, filed.month, filed.day));
    }
    if (daysWritten.isEmpty) return null;

    return units / daysWritten.length;
  }

  /// The daily target from the project settings, expressed in billable units.
  ///
  /// A sefer may state its target in lines or in pages; the other types are
  /// always counted in whole units.
  static double? targetPace(Project project) {
    if (project.targetDaily <= 0) return null;
    if (project.type == ProjectType.sefer && project.dailyGoalInLines) {
      return project.targetDaily / ProductionCalculator.linesPerPageOf(project);
    }
    return project.targetDaily.toDouble();
  }

  /// When [project] will be finished.
  ///
  /// Returns null when the answer would be invented rather than derived: no
  /// stated job size, nothing left to do, or no pace to work from.
  static CompletionEstimate? estimate({
    required Project project,
    required Iterable<WorkSession> history,
    required WorkCalendarRules rules,
    DateTime? from,
  }) {
    final total = project.plannedUnits;
    if (total == null || total <= 0) return null;

    final done = doneUnits(project, history);
    final remaining = total - done;
    if (remaining <= 0) return null;

    final measured = measuredPace(project, history, rules);
    final pace = measured ?? targetPace(project);
    if (pace == null || pace <= 0) return null;

    final plan = HebrewWorkCalendar.plan(
      from: from ?? DateTime.now(),
      workDaysNeeded: remaining / pace,
      rules: rules,
    );
    if (plan == null) return null;

    return CompletionEstimate(
      totalUnits: total,
      doneUnits: done,
      remainingUnits: remaining,
      unitsPerWorkDay: pace,
      paceMeasured: measured != null,
      plan: plan,
    );
  }

  /// Units per working day needed to hit [deadline], starting from [from].
  ///
  /// Null when the deadline has passed or leaves no working days at all — the
  /// honest answer there is "not by then", not a very large number.
  static double? paceRequiredFor({
    required double remainingUnits,
    required DateTime deadline,
    required WorkCalendarRules rules,
    DateTime? from,
  }) {
    if (remainingUnits <= 0) return null;
    final start = from ?? DateTime.now();
    if (!deadline.isAfter(start)) return null;

    final workDays = HebrewWorkCalendar.countWorkDays(start, deadline, rules);
    if (workDays <= 0) return null;
    return remainingUnits / workDays;
  }
}
