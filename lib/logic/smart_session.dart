import '../hebrew_utils.dart';
import '../models.dart';
import 'id_generator.dart';
import 'production_calculator.dart';
import 'session_logic.dart';

/// Where a writer is in a commission: the next line they are about to write.
///
/// Counted from one at both ends. There is no page zero and no line zero, and a
/// zero on screen is always a bug.
class SmartPosition {
  final int page;
  final int line;

  const SmartPosition(this.page, this.line);

  /// Where the writer stands after finishing [line] of [page], rolling onto the
  /// next page when the page is full.
  static SmartPosition after({
    required int page,
    required int line,
    required int linesPerUnit,
  }) {
    final next = line + 1;
    return next > linesPerUnit
        ? SmartPosition(page + 1, 1)
        : SmartPosition(page, next);
  }

  /// Whether this is further along than [other].
  ///
  /// What stops filling in an earlier gap from rewinding the writer's place: a
  /// record typed in for last Tuesday says nothing about where they are now.
  bool isAfter(SmartPosition other) =>
      page > other.page || (page == other.page && line > other.line);

  @override
  String toString() => 'page $page, line $line';
}

/// What a sitting in smart mode came to.
sealed class SmartOutcome {
  const SmartOutcome();
}

/// The writer ended where they began. Nothing to record.
final class SmartNothingWritten extends SmartOutcome {
  const SmartNothingWritten();
}

final class SmartRecorded extends SmartOutcome {
  final List<WorkSession> sessions;
  final int linesWritten;

  /// Pages of this sitting that were already written before.
  ///
  /// Smart mode wrote straight to history without ever looking, so using "edit
  /// position" to jump back and rewriting a stretch produced a silent double
  /// entry.
  final List<int> overlappingPages;

  const SmartRecorded({
    required this.sessions,
    required this.linesWritten,
    this.overlappingPages = const [],
  });

  bool get overlapsRecordedWork => overlappingPages.isNotEmpty;
}

/// Turns a sitting in smart mode — where it began, where it ended, and how long
/// it took — into the records it means.
///
/// Two hundred and thirty lines of this lived in the home screen, and none of it
/// could be tested: the arithmetic that works out which lines of which pages
/// were written, and how the measured time divides between them, was reachable
/// only by starting a timer and writing.
class SmartSessionBuilder {
  const SmartSessionBuilder._();

  static SmartOutcome build({
    required Project project,
    required SmartPosition from,
    required SmartPosition to,
    required Duration worked,
    required DateTime endedAt,
    Iterable<WorkSession> history = const [],
  }) {
    final linesPerUnit = project.type == ProjectType.mezuza
        ? ProductionCalculator.linesPerMezuza
        : ProductionCalculator.linesPerPageOf(project);

    // The stored position is the line about to be written, so the last line
    // actually written is the one before it — and if that is the top of a page,
    // the writer finished the page before.
    var lastPage = to.page;
    var lastLine = to.line - 1;
    if (lastLine < 1) {
      if (lastPage > from.page) {
        lastPage--;
        lastLine = linesPerUnit;
      } else {
        lastLine = from.line - 1;
      }
    }

    final wentBackwards = lastPage < from.page ||
        (lastPage == from.page && lastLine < from.line);
    if (wentBackwards) return const SmartNothingWritten();

    // One mark for the whole sitting: the records below are its pages, and the
    // measured time is divided between them. See [WorkSession.entryId].
    final entryId = IdGenerator.generate();

    return project.type == ProjectType.mezuza
        ? _mezuzot(project, from, lastPage, lastLine, linesPerUnit, worked,
            endedAt, entryId)
        : _pages(project, from, lastPage, lastLine, linesPerUnit, worked,
            endedAt, history, entryId);
  }

  /// Mezuzot are counted, so a sitting across several of them is recorded as
  /// however many were finished plus whatever is part-written of the next.
  static SmartOutcome _mezuzot(
    Project project,
    SmartPosition from,
    int lastUnit,
    int lastLine,
    int linesPerUnit,
    Duration worked,
    DateTime endedAt,
    String entryId,
  ) {
    final int lines;
    if (lastUnit == from.page) {
      lines = lastLine - from.line + 1;
    } else {
      lines = (linesPerUnit - from.line + 1) +
          (lastUnit - from.page - 1) * linesPerUnit +
          lastLine;
    }
    if (lines <= 0) return const SmartNothingWritten();

    final whole = lines ~/ linesPerUnit;
    final partial = lines % linesPerUnit;

    final drafts = <_Draft>[
      if (whole > 0)
        _Draft(
          id: IdGenerator.generate(),
          amount: whole,
          startLine: 0,
          endLine: 0,
          description: "$whole מזוזות",
          weight: whole * linesPerUnit,
        ),
      if (partial > 0)
        _Draft(
          id: IdGenerator.generate(suffix: 'p'),
          amount: 1,
          startLine: 1,
          endLine: partial,
          description: "מזוזה (עד שורה $partial)",
          weight: partial,
        ),
    ];

    return SmartRecorded(
      sessions: _timed(project, drafts, worked, endedAt, entryId),
      linesWritten: lines,
    );
  }

  /// A sefer is paginated, so a sitting becomes one record per page it touched,
  /// each carrying the lines written on that page.
  static SmartOutcome _pages(
    Project project,
    SmartPosition from,
    int lastPage,
    int lastLine,
    int linesPerPage,
    Duration worked,
    DateTime endedAt,
    Iterable<WorkSession> history,
    String entryId,
  ) {
    final drafts = <_Draft>[];
    var lines = 0;

    for (var page = from.page; page <= lastPage; page++) {
      final start = page == from.page ? from.line : 1;
      final end = page == lastPage ? lastLine : linesPerPage;
      if (end < start) continue;

      lines += end - start + 1;
      drafts.add(_Draft(
        id: IdGenerator.generate(suffix: '$page'),
        amount: page,
        startLine: start,
        endLine: end,
        description: "כתיבה רציפה (עמוד ${formatHebrewNumber(page)})",
        linesPerPage: linesPerPage,
        weight: end - start + 1,
      ));
    }

    if (lines == 0) return const SmartNothingWritten();

    final overlapping = [
      for (final draft in drafts)
        if (SessionLogic.hasSeferOverlap(
          history: history,
          projectId: project.id,
          page: draft.amount,
          startLine: draft.startLine,
          endLine: draft.endLine,
          projectType: project.type,
        ))
          draft.amount,
    ];

    return SmartRecorded(
      sessions: _timed(project, drafts, worked, endedAt, entryId),
      linesWritten: lines,
      overlappingPages: overlapping,
    );
  }

  /// Hands the measured time out between the records, in proportion to the
  /// lines each of them holds, ending where the sitting ended.
  static List<WorkSession> _timed(
    Project project,
    List<_Draft> drafts,
    Duration worked,
    DateTime endedAt,
    String entryId,
  ) {
    final slices = SessionLogic.splitByWeight(
      start: endedAt.subtract(worked),
      end: endedAt,
      weights: [for (final d in drafts) d.weight],
    );
    return [
      for (var i = 0; i < drafts.length; i++)
        WorkSession(
          id: drafts[i].id,
          projectId: project.id,
          startTime: slices[i].start,
          endTime: slices[i].end,
          amount: drafts[i].amount,
          startLine: drafts[i].startLine,
          endLine: drafts[i].endLine,
          description: drafts[i].description,
          isManual: false,
          linesPerPageAtEntry: drafts[i].linesPerPage,
          entryId: entryId,
        ),
    ];
  }
}

/// A record waiting for its share of the sitting's time.
class _Draft {
  final String id;
  final int amount;
  final int startLine;
  final int endLine;
  final String description;
  final int? linesPerPage;

  /// Lines written, which is what the time is divided by.
  final int weight;

  const _Draft({
    required this.id,
    required this.amount,
    required this.startLine,
    required this.endLine,
    required this.description,
    required this.weight,
    this.linesPerPage,
  });
}
