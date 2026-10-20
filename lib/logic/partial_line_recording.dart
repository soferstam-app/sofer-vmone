import '../models.dart';
import 'id_generator.dart';
import 'production_calculator.dart';
import 'smart_session.dart';
import 'tefillin_position.dart';

/// Persists writing time that stopped before the current line was completed.
///
/// The fragment is a real [WorkSession], so its duration stays on the day it
/// was measured.  Its deliberately empty legacy geometry and
/// [WorkSession.isPartialLine] flag make it zero output in both this build and
/// older builds that do not know the flag.
class PartialLineRecording {
  const PartialLineRecording._();

  static WorkSession create({
    required Project project,
    required SmartPosition position,
    required Duration worked,
    required DateTime endedAt,
  }) {
    final safeWorked = worked.isNegative ? Duration.zero : worked;
    final start = endedAt.subtract(safeWorked);

    var amount = 0;
    var startLine = 0;
    var endLine = 0;
    int? mezuzaIndex;
    String? tefillinType;
    int? parshiya;
    int? pairIndex;
    int? linesPerPage;

    switch (project.type) {
      case ProjectType.sefer:
      case ProjectType.megillah:
        amount = position.page;
        // Inclusive line arithmetic in old builds reads this as zero lines.
        startLine = 1;
        endLine = 0;
        linesPerPage = ProductionCalculator.linesPerPageOf(project);
        break;
      case ProjectType.mezuza:
        // Old builds read amount 0/endLine 0 as zero mezuzot.
        mezuzaIndex = position.page;
        break;
      case ProjectType.tefillin:
        final at = TefillinPosition.fromSlotIndex(position.page);
        tefillinType = at.side.name;
        parshiya = at.parshiya;
        pairIndex = at.pair;
        // An explicit reversed range is zero physical and comparable lines.
        startLine = 2;
        endLine = 1;
        break;
    }

    return WorkSession(
      id: IdGenerator.generate(suffix: 'partial-line'),
      projectId: project.id,
      startTime: start,
      endTime: endedAt,
      amount: amount,
      startLine: startLine,
      endLine: endLine,
      mezuzaIndex: mezuzaIndex,
      tefillinType: tefillinType,
      parshiya: parshiya,
      pairIndex: pairIndex,
      description: 'זמן חלקי בשורה ${position.line}',
      isManual: false,
      isPartialLine: true,
      partialPositionPage: position.page,
      partialPositionLine: position.line,
      linesPerPageAtEntry: linesPerPage,
    );
  }

  static bool matches(
    WorkSession session,
    Project project,
    SmartPosition position,
  ) =>
      session.isTimeOnly &&
      !session.partialLineCompleted &&
      !session.isDeleted &&
      !session.isInvalid &&
      session.projectId == project.id &&
      session.partialPositionPage == position.page &&
      session.partialPositionLine == position.line;

  static Duration carriedTime(
    Iterable<WorkSession> history,
    Project project,
    SmartPosition position,
  ) {
    var total = Duration.zero;
    for (final session in history) {
      if (matches(session, project, position) &&
          session.timeRecorded &&
          session.duration > Duration.zero) {
        total += session.duration;
      }
    }
    return total;
  }

  /// Keeps the fragments for daily time totals, but removes them from the
  /// carry shown on the next visit to this line.
  static List<WorkSession> resolve(
    Iterable<WorkSession> history,
    Project project,
    SmartPosition position,
  ) =>
      [
        for (final session in history)
          if (matches(session, project, position))
            session.copyWith(partialLineCompleted: true)
          else
            session,
      ];
}
