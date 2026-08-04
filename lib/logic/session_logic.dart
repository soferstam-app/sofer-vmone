import '../models.dart';
import 'calendar_days.dart';
import 'production_calculator.dart';

/// Rules for building and validating a work session.
///
/// Entry and editing are the same operation performed in two places, and they
/// had drifted apart: the entry dialog handled a session running past midnight
/// and checked line bounds, while the edit dialog did neither. Both now go
/// through here.
class SessionLogic {
  const SessionLogic._();

  /// Parses "HH:MM" (tolerating surrounding spaces). Returns null if the text
  /// is not a valid time.
  static ({int hour, int minute})? parseTimeString(String text) {
    final parts = text.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(parts[1].trim());
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }

  /// Builds a session's start and end from a date and two clock times.
  ///
  /// When the end time is earlier than the start, the session ran past
  /// midnight and the end belongs to the next day. Without this a late-night
  /// session yields a negative duration, which then corrupts every average and
  /// monthly total it feeds into.
  static ({DateTime start, DateTime end}) buildTimeRange({
    required DateTime date,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
  }) {
    final start =
        DateTime(date.year, date.month, date.day, startHour, startMinute);
    var end = DateTime(date.year, date.month, date.day, endHour, endMinute);
    if (end.isBefore(start)) {
      // The same clock time on the following day, which on the two nights the
      // clocks change is not the same as twenty-four hours later.
      end = CalendarDays.addDaysKeepingTime(end, 1);
    }
    return (start: start, end: end);
  }

  /// Divides one stretch of time into [parts] consecutive slices.
  ///
  /// A page range is entered once and recorded as one session per page. Giving
  /// every page the whole stretch multiplied the day by the number of pages:
  /// five pages written in an hour were stored as five hours, and every figure
  /// per hour along with them.
  ///
  /// The last slice takes the remainder, so the slices add back up to exactly
  /// the time that was entered rather than to a rounded-down approximation of
  /// it. An empty stretch — an entry with no working time — yields empty slices,
  /// which is the honest answer and not a division by zero.
  static List<({DateTime start, DateTime end})> splitRange({
    required DateTime start,
    required DateTime end,
    required int parts,
  }) {
    if (parts <= 1) return [(start: start, end: end)];

    final totalMs = end.difference(start).inMilliseconds;
    final sliceMs = totalMs ~/ parts;
    return [
      for (var i = 0; i < parts; i++)
        (
          start: start.add(Duration(milliseconds: sliceMs * i)),
          end: i == parts - 1
              ? end
              : start.add(Duration(milliseconds: sliceMs * (i + 1))),
        ),
    ];
  }

  /// Divides one stretch of time between parts of unequal size.
  ///
  /// A sitting in smart mode crosses several pages, and they are rarely equal:
  /// it may start halfway down one and stop three lines into another. Time is
  /// handed out in proportion to the lines each page took, which is the nearest
  /// the app can get to the truth without asking.
  ///
  /// As in [splitRange], the last slice takes the remainder so the parts add
  /// back up to exactly the stretch that was measured.
  static List<({DateTime start, DateTime end})> splitByWeight({
    required DateTime start,
    required DateTime end,
    required List<int> weights,
  }) {
    if (weights.isEmpty) return const [];
    if (weights.length == 1) return [(start: start, end: end)];

    final total = weights.fold(0, (sum, w) => sum + w);
    if (total <= 0) {
      return [for (final _ in weights) (start: start, end: start)];
    }

    final totalMs = end.difference(start).inMilliseconds;
    final slices = <({DateTime start, DateTime end})>[];
    var cursor = start;
    var used = 0;
    for (var i = 0; i < weights.length; i++) {
      if (i == weights.length - 1) {
        slices.add((start: cursor, end: end));
        break;
      }
      used += weights[i];
      final next = start.add(Duration(milliseconds: totalMs * used ~/ total));
      slices.add((start: cursor, end: next));
      cursor = next;
    }
    return slices;
  }

  /// Validates a sefer line range against the project's page size.
  ///
  /// Returns null when valid, or a ready-to-show Hebrew message.
  static String? validateSeferLines({
    required int startLine,
    required int endLine,
    required int linesPerPage,
  }) {
    if (startLine <= 0 || endLine <= 0) {
      return "יש להזין שורות תקינות (משורה, עד שורה)";
    }
    if (startLine > linesPerPage || endLine > linesPerPage) {
      return "מספר השורות חורג מהגדרת העמוד ($linesPerPage)";
    }
    if (startLine > endLine) {
      return "שורה התחלה חייבת להיות קטנה משורה סיום";
    }
    return null;
  }

  /// Validates a mezuza partial-line value. Zero means none was given.
  static String? validateMezuzaLine(int line) {
    // Only the upper bound was checked, so a negative line passed — and a
    // negative partial subtracts from the lines the session is counted as.
    if (line < 0) return "מספר שורה אינו יכול להיות שלילי";
    if (line > ProductionCalculator.linesPerMezuza) {
      return "במזוזה יש רק ${ProductionCalculator.linesPerMezuza} שורות";
    }
    return null;
  }

  /// Validates a tefillin parshiya line against head/hand limits.
  static String? validateTefillinLine({
    required String tefillinType,
    required int line,
  }) {
    if (line < 0) return "מספר שורה אינו יכול להיות שלילי";
    final maxLines = tefillinType == 'head'
        ? ProductionCalculator.linesPerHeadParshiya
        : ProductionCalculator.linesPerHandParshiya;
    if (line > maxLines) {
      final part = tefillinType == 'head' ? 'של ראש' : 'של יד';
      return "בתפילין $part יש עד $maxLines שורות";
    }
    return null;
  }

  /// Whether the given sefer line range overlaps work already recorded on the
  /// same page of the same project.
  ///
  /// **Sefer projects only.** This reads `amount` as a page number, which is
  /// what it means for sefer and nothing like what it means for mezuza or
  /// tefillin, where it is a count. Passing a project of another type would
  /// compare a page number against a quantity and report nonsense — pass
  /// [projectType] so that is caught rather than silently wrong.
  ///
  /// [excludeSessionId] skips one session — required when editing, so a
  /// session is not reported as overlapping itself.
  static bool hasSeferOverlap({
    required Iterable<WorkSession> history,
    required String projectId,
    required int page,
    required int startLine,
    required int endLine,
    ProjectType projectType = ProjectType.sefer,
    String? excludeSessionId,
  }) {
    assert(
      projectType == ProjectType.sefer,
      'hasSeferOverlap called for a $projectType project; `amount` is a count '
      'there, not a page number',
    );
    if (projectType != ProjectType.sefer) return false;

    for (final session in history) {
      if (session.isDeleted) continue;
      if (session.id == excludeSessionId) continue;
      if (session.projectId != projectId) continue;
      // For sefer projects `amount` carries the page number.
      if (session.amount != page) continue;
      if (startLine <= session.endLine && endLine >= session.startLine) {
        return true;
      }
    }
    return false;
  }
}
