import '../models.dart';
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

  /// Units produced per working day, measured from the writer's own history.
  ///
  /// The denominator is working days between the first and last session — not
  /// elapsed days — so a project written over a Pesach is not judged to be slow
  /// because of the fortnight nobody was writing.
  ///
  /// Returns null when there is nothing timed to measure.
  static double? measuredPace(
    Project project,
    Iterable<WorkSession> history,
    WorkCalendarRules rules,
  ) {
    final sessions = history
        .where((s) =>
            s.projectId == project.id && !s.isDeleted && !s.backlogOnly)
        .toList();
    if (sessions.isEmpty) return null;

    final units = ProfitCalculator.billableUnits(project, sessions);
    if (units <= 0) return null;

    var first = sessions.first.startTime;
    var last = sessions.first.endTime;
    for (final s in sessions) {
      if (s.startTime.isBefore(first)) first = s.startTime;
      if (s.endTime.isAfter(last)) last = s.endTime;
    }

    final workDays = HebrewWorkCalendar.countWorkDays(first, last, rules);
    if (workDays <= 0) return null;
    return units / workDays;
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
