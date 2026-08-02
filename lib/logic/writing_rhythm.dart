import '../models.dart';
import 'date_logic.dart';
import 'hebrew_clock.dart';
import 'production_calculator.dart';

/// When a sofer writes fastest.
///
/// Every recorded sitting already carries the hour it began and how long it
/// took. Nothing ever asked the obvious question of that: whether the same
/// writer, on the same commission, gets more done at six in the morning than at
/// nine at night — and which days of the week are worth protecting.
///
/// It is a measure of pace, not of quantity. An hour that produced twelve lines
/// beats three hours that produced twenty, and the writer who wants to plan his
/// day needs the first number and not the second.
class WritingRhythm {
  const WritingRhythm._();

  /// A sitting is ignored below this. A single line recorded against four
  /// seconds is not a pace, it is a slip of the finger, and one of them would
  /// dominate an average of everything else.
  static const Duration _tooShortToJudge = Duration(minutes: 2);

  /// How many sittings a slot needs before its pace is worth reporting.
  ///
  /// One good evening is not a fact about evenings. This is the difference
  /// between telling a writer something and flattering a coincidence.
  static const int minSittings = 3;

  /// A slot of the week, and the pace measured in it.
  static List<RhythmSlot> byHourOfDay(
          Project project, Iterable<WorkSession> sessions, DayStart dayStart) =>
      _measure(project, sessions, dayStart, (s, day) => s.startTime.hour);

  /// Weekday 1–7, Sunday first, which is how the week is counted here.
  static List<RhythmSlot> byDayOfWeek(
          Project project, Iterable<WorkSession> sessions, DayStart dayStart) =>
      _measure(project, sessions, dayStart,
          (s, day) => day.weekday % 7 + 1);

  /// The slot with the best pace, out of those measured often enough to mean
  /// anything. Null when nothing has been measured often enough — which is the
  /// honest answer for a writer who has just started.
  static RhythmSlot? best(List<RhythmSlot> slots) {
    final worth = slots.where((s) => s.sittings >= minSittings).toList();
    if (worth.isEmpty) return null;
    worth.sort((a, b) => b.linesPerHour.compareTo(a.linesPerHour));
    return worth.first;
  }

  static List<RhythmSlot> _measure(
    Project project,
    Iterable<WorkSession> sessions,
    DayStart dayStart,
    int Function(WorkSession, DateTime) slotOf,
  ) {
    final lines = <int, int>{};
    final worked = <int, Duration>{};
    final count = <int, int>{};

    for (final s in sessions) {
      if (s.isDeleted || s.backlogOnly) continue;
      // A record with no time cannot speak about pace at all. It is not a zero
      // and must not be averaged as one.
      if (!s.timeRecorded || s.duration < _tooShortToJudge) continue;

      final written = project.type == ProjectType.sefer
          ? ProductionCalculator.seferLinesInSession(s)
          : ProductionCalculator.mezuzaLinesInSession(s);
      if (written <= 0) continue;

      final slot = slotOf(s, DateLogic.workingDateOf(s, dayStart));
      lines[slot] = (lines[slot] ?? 0) + written;
      worked[slot] = (worked[slot] ?? Duration.zero) + s.duration;
      count[slot] = (count[slot] ?? 0) + 1;
    }

    return [
      for (final slot in lines.keys)
        RhythmSlot(
          slot: slot,
          lines: lines[slot]!,
          worked: worked[slot]!,
          sittings: count[slot]!,
        ),
    ]..sort((a, b) => a.slot.compareTo(b.slot));
  }
}

/// One hour of the day, or one day of the week, and what was written in it.
class RhythmSlot {
  /// The hour (0–23) or the weekday (1–7, Sunday first).
  final int slot;

  final int lines;
  final Duration worked;

  /// How many separate sittings went into this. Reported, because a pace drawn
  /// from one sitting and a pace drawn from thirty look identical otherwise.
  final int sittings;

  const RhythmSlot({
    required this.slot,
    required this.lines,
    required this.worked,
    required this.sittings,
  });

  /// The whole point of the measure.
  double get linesPerHour =>
      worked <= Duration.zero ? 0 : lines / (worked.inSeconds / 3600);

  /// Whether there is enough here to tell a writer anything.
  bool get isReliable => sittings >= WritingRhythm.minSittings;
}
