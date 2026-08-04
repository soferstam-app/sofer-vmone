import '../models.dart';
import 'daily_goal.dart';
import 'date_logic.dart';
import 'hebrew_clock.dart';

/// What a reminder should say, and when it should arrive.
///
/// Everything here is decided when the reminder is **booked**, not when it
/// fires. `zonedSchedule` hands the notification to the operating system and no
/// Dart runs at the moment it appears — so a reminder cannot look anything up
/// about the day it lands on. What it can do is be booked knowing today, and
/// re-booked every time the app is opened or work is recorded.
///
/// That draws the line cleanly. **Today's reminder can be specific**, because
/// the app knows this minute how much is left of the goal. The days after it
/// cannot be, and are left saying something true of any day rather than a guess
/// that will be stale by the time it arrives.
class ReminderPlan {
  const ReminderPlan._();

  /// A sitting shorter than this says nothing about when the writer works.
  static const Duration _tooShort = Duration(minutes: 5);

  /// How many sittings an hour needs before it counts as a habit.
  static const int _minSittings = 4;

  /// The hour this writer usually begins.
  ///
  /// Not the hour he writes fastest — that is a different question, answered by
  /// WritingRhythm. This is the hour he most often sits down, which is when a
  /// reminder is worth having: a nudge at eight in the evening is no use to
  /// someone who has always finished by noon.
  ///
  /// Null until there is enough of a pattern to call it one. A habit guessed
  /// from three sittings is not a habit, and a reminder at the wrong hour is
  /// worse than one at a dull hour the writer chose himself.
  static int? usualStartHour(
      Iterable<WorkSession> sessions, DayStart dayStart) {
    final counts = <int, int>{};
    for (final s in sessions) {
      if (s.isDeleted || s.backlogOnly || !s.timeRecorded) continue;
      if (s.duration < _tooShort) continue;
      final hour = s.startTime.hour;
      counts[hour] = (counts[hour] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;

    var best = counts.keys.first;
    for (final entry in counts.entries) {
      // Ties go to the earlier hour: a reminder that comes too early can still
      // be acted on, and one that comes too late cannot.
      if (entry.value > counts[best]! ||
          (entry.value == counts[best]! && entry.key < best)) {
        best = entry.key;
      }
    }
    return counts[best]! >= _minSittings ? best : null;
  }

  /// What today's reminder should say.
  ///
  /// Knowable only for today, and only at the moment of booking. Everything it
  /// states is a fact the app holds right now: how much of the goal is left, in
  /// the units the writer works in.
  static String todaysMessage({
    required Project? project,
    required Iterable<WorkSession> history,
    required DateTime day,
    required DayStart dayStart,
  }) {
    if (project == null || project.targetDaily <= 0) return generalMessage;

    final done = DailyGoal.doneOn(
        project: project, history: history, day: day, dayStart: dayStart);
    final target = DailyGoal.targetFor(project);
    final left = target - done;

    // Met already. The caller drops today's reminder entirely in that case, so
    // this is the belt to that pair of braces.
    if (left <= 0) return generalMessage;

    final unit = project.type == ProjectType.sefer
        ? (project.dailyGoalInLines ? 'שורות' : 'שורות')
        : 'יחידות';

    // Nothing at all written today reads differently from nearly finished, and
    // saying "3 left" to someone who has not started is simply wrong-footed.
    if (done <= 0) return 'עוד לא נרשמה כתיבה היום. מתחילים?';
    return 'נשארו $left $unit להשלמת היעד היומי.';
  }

  /// What every other day says.
  ///
  /// True whatever happens between now and then. The reminder this replaced
  /// asked "did you meet your daily target?" of writers who had met it hours
  /// earlier and of writers who had never set one.
  static const String generalMessage = 'סוף היום — רוצה לרשום מה כתבת?';

  /// The hour a reminder should be booked for.
  ///
  /// The writer's own habit when he has asked for that and one can be found;
  /// otherwise the hour he set, which is always a real answer.
  static int hourFor({
    required bool smart,
    required int chosenHour,
    required Iterable<WorkSession> history,
    required DayStart dayStart,
  }) {
    if (!smart) return chosenHour;
    return usualStartHour(history, dayStart) ?? chosenHour;
  }

  /// Which commission a reminder should speak about.
  ///
  /// The one worked on most recently: a writer with three open jobs is not
  /// helped by being told about the one he has not touched in a month.
  static Project? mostRecent(
      Iterable<Project> projects, Iterable<WorkSession> history) {
    WorkSession? latest;
    for (final s in history) {
      if (s.isDeleted || s.backlogOnly) continue;
      if (latest == null || s.startTime.isAfter(latest.startTime)) latest = s;
    }
    if (latest == null) return null;
    for (final p in projects) {
      if (p.id == latest.projectId && !p.isDeleted) return p;
    }
    return null;
  }

  /// Whether today's reminder is worth sending at all.
  static bool isWorthSending({
    required Project? project,
    required Iterable<WorkSession> history,
    required DateTime day,
    required DayStart dayStart,
  }) {
    if (project == null || project.targetDaily <= 0) return true;
    return !DailyGoal.isMet(
        project: project, history: history, day: day, dayStart: dayStart);
  }

  /// The working day a moment belongs to, for callers that need it.
  static DateTime workingDay(DateTime moment, DayStart dayStart) =>
      DateLogic.effectiveDate(moment, dayStart);
}
