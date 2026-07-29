import '../models.dart';
import 'profit_calculator.dart';

/// Everything worth knowing about how one project actually performed.
///
/// Shared by the profitability comparison and the price quote, which both need
/// the same underlying question answered: at what rate does this writer
/// actually produce this kind of work, and what does it pay?
class ProjectPerformance {
  final Project project;

  /// Billable units produced — pages, mezuzot or full tefillin sets.
  final double units;
  final double profit;
  final Duration timeWorked;

  /// Null when no time was recorded, rather than a misleading zero.
  final double? profitPerHour;
  final Duration? timePerUnit;

  const ProjectPerformance({
    required this.project,
    required this.units,
    required this.profit,
    required this.timeWorked,
    this.profitPerHour,
    this.timePerUnit,
  });

  /// Whether there is enough recorded work to draw any conclusion from.
  bool get hasEnoughData => timeWorked.inMinutes > 0 && units > 0;

  /// The unit this project is measured and priced in.
  String get unitName => switch (project.type) {
        ProjectType.sefer => 'עמוד',
        ProjectType.mezuza => 'מזוזה',
        ProjectType.tefillin => 'סט',
      };

  String get unitNamePlural => switch (project.type) {
        ProjectType.sefer => 'עמודים',
        ProjectType.mezuza => 'מזוזות',
        ProjectType.tefillin => 'סטים',
      };
}

class ProjectAnalytics {
  const ProjectAnalytics._();

  /// Measures one project from its sessions.
  ///
  /// Backlog entries are excluded throughout: they record work done before the
  /// app existed, carry no earnings and hold placeholder timestamps, so
  /// including them would distort both the rate and the pay.
  static ProjectPerformance measure(
      Project project, Iterable<WorkSession> allSessions) {
    final sessions = allSessions
        .where((s) => s.projectId == project.id && !s.isDeleted && !s.backlogOnly)
        .toList();

    var time = Duration.zero;
    for (final s in sessions) {
      // A session cannot take negative time; guard against any legacy record
      // written before the midnight-crossing fix.
      if (s.duration > Duration.zero) time += s.duration;
    }

    final units = ProfitCalculator.billableUnits(project, sessions);
    final profit = ProfitCalculator.profit(project, sessions);

    return ProjectPerformance(
      project: project,
      units: units,
      profit: profit,
      timeWorked: time,
      profitPerHour:
          time.inSeconds > 0 ? profit / (time.inSeconds / 3600) : null,
      timePerUnit: (units > 0 && time.inSeconds > 0)
          ? Duration(seconds: (time.inSeconds / units).round())
          : null,
    );
  }

  /// All projects measured, best paying first.
  ///
  /// Projects without enough data sort last — they cannot be ranked, and
  /// putting them at the top would suggest otherwise.
  static List<ProjectPerformance> rankByHourlyRate(
      Iterable<Project> projects, Iterable<WorkSession> history) {
    final measured = projects
        .where((p) => !p.isDeleted)
        .map((p) => measure(p, history))
        .toList();

    measured.sort((a, b) {
      if (a.hasEnoughData != b.hasEnoughData) return a.hasEnoughData ? -1 : 1;
      return (b.profitPerHour ?? 0).compareTo(a.profitPerHour ?? 0);
    });
    return measured;
  }

  /// Typical time to produce one unit of [type], learned from past work.
  ///
  /// Averages across every project of that type rather than a single one, so a
  /// quote is based on the widest sample available. Returns null when the
  /// writer has never recorded timed work of this kind.
  static Duration? typicalTimePerUnit(
    ProjectType type,
    Iterable<Project> projects,
    Iterable<WorkSession> history,
  ) {
    var totalSeconds = 0;
    var totalUnits = 0.0;

    for (final project in projects.where((p) => p.type == type)) {
      final perf = measure(project, history);
      if (!perf.hasEnoughData) continue;
      totalSeconds += perf.timeWorked.inSeconds;
      totalUnits += perf.units;
    }

    if (totalUnits <= 0 || totalSeconds <= 0) return null;
    return Duration(seconds: (totalSeconds / totalUnits).round());
  }
}
