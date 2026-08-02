import '../models.dart';
import 'date_logic.dart';
import 'hebrew_clock.dart';
import 'production_calculator.dart';

/// Whether a day's target has been met.
///
/// The app congratulates a writer on reaching their goal, and this is what
/// decides it. It sat inside the home screen reading that screen's fields, so
/// the one question a sofer asks the app every evening could only be answered
/// by writing for a day and looking.
///
/// The target is counted in whatever the commission is counted in: lines or
/// pages for a sefer, depending on how the goal was set, and units otherwise.
class DailyGoal {
  const DailyGoal._();

  /// How much of [project] was produced on [day].
  ///
  /// Backlog entries record work done before the app existed. They carry a
  /// placeholder date and must not count towards a day's goal — for a while
  /// they were kept out only by accident.
  static int doneOn({
    required Project project,
    required Iterable<WorkSession> history,
    required DateTime day,
    required DayStart dayStart,
  }) {
    var done = 0;
    for (final s in history) {
      if (s.projectId != project.id) continue;
      if (s.isDeleted || s.backlogOnly) continue;
      if (!DateLogic.sessionIsOnDay(s, day, dayStart)) continue;

      done += project.type == ProjectType.sefer
          ? ProductionCalculator.seferLinesInSession(s)
          : s.amount;
    }
    return done;
  }

  /// The target for one day, in the same unit [doneOn] counts in.
  ///
  /// A sefer goal set in pages is multiplied out to lines, because that is what
  /// the sessions are measured in. The page size is the project's current one:
  /// a target is a plan for tomorrow, not a record of the past, so unlike every
  /// stored figure it is right for it to follow the setting.
  static int targetFor(Project project) {
    if (project.type != ProjectType.sefer || project.dailyGoalInLines) {
      return project.targetDaily;
    }
    return project.targetDaily * ProductionCalculator.linesPerPageOf(project);
  }

  /// Whether the day's writing has reached the target.
  ///
  /// A commission with no target is always met: there is nothing to fall short
  /// of, and reporting a miss against a goal nobody set would be an invention.
  static bool isMet({
    required Project project,
    required Iterable<WorkSession> history,
    required DateTime day,
    required DayStart dayStart,
  }) {
    if (project.targetDaily <= 0) return true;
    final done = doneOn(
        project: project, history: history, day: day, dayStart: dayStart);
    return done >= targetFor(project);
  }
}
