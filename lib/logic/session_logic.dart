import '../models.dart';
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
      end = end.add(const Duration(days: 1));
    }
    return (start: start, end: end);
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

  /// Validates a mezuza partial-line value.
  static String? validateMezuzaLine(int line) {
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
  /// [excludeSessionId] skips one session — required when editing, so a
  /// session is not reported as overlapping itself.
  static bool hasSeferOverlap({
    required Iterable<WorkSession> history,
    required String projectId,
    required int page,
    required int startLine,
    required int endLine,
    String? excludeSessionId,
  }) {
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
