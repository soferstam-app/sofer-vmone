import '../models.dart';
import 'production_calculator.dart';

/// Money calculations, kept separate from the screens so every view agrees.
///
/// The price on a [Project] is always *per billable unit*, and the unit
/// differs by type — this is what the project form states:
///
/// * sefer    → per page      ("כספים (לעמוד)")
/// * mezuza   → per mezuza    ("כספים (למזוזה)")
/// * tefillin → per full set  ("כספים (ליחידה: ראש+יד)")
class ProfitCalculator {
  const ProfitCalculator._();

  /// Billable units produced by [sessions], as a fraction.
  ///
  /// Half a page is 0.5 pages; a head-only tefillin is 4 of the 8 parshiyot in
  /// a set, so half a set.
  static double billableUnits(Project project, Iterable<WorkSession> sessions) {
    switch (project.type) {
      case ProjectType.sefer:
        return ProductionCalculator.seferLinesTotal(sessions) /
            ProductionCalculator.linesPerPageOf(project);
      case ProjectType.mezuza:
        return ProductionCalculator.mezuzaLinesTotal(sessions) /
            ProductionCalculator.linesPerMezuza;
      case ProjectType.tefillin:
        return ProductionCalculator.parshiyotTotal(sessions) /
            ProductionCalculator.parshiyotPerSet;
    }
  }

  /// Net value of one billable unit.
  static double netPerUnit(Project project) => project.price - project.expenses;

  /// Profit earned from [sessions].
  ///
  /// Callers are responsible for excluding backlog-only sessions, which
  /// represent work done before the app was installed and carry no earnings.
  static double profit(Project project, Iterable<WorkSession> sessions) =>
      billableUnits(project, sessions) * netPerUnit(project);

  /// Effective hourly rate — the number that tells a writer whether a project
  /// is actually worth their time.
  ///
  /// Returns null when no time was recorded, since dividing by zero hours
  /// would otherwise report an infinite rate.
  static double? profitPerHour(
      Project project, Iterable<WorkSession> sessions, Duration workedTime) {
    if (workedTime.inSeconds <= 0) return null;
    final hours = workedTime.inSeconds / Duration.secondsPerHour;
    return profit(project, sessions) / hours;
  }
}
