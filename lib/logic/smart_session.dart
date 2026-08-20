import '../hebrew_utils.dart';
import '../models.dart';
import 'id_generator.dart';
import 'production_calculator.dart';
import 'session_logic.dart';
import 'tefillin_position.dart';
import 'tefillin_state.dart';
import 'tefillin_units.dart';

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

/// The position describes work that the project rules do not allow.
final class SmartRejected extends SmartOutcome {
  final String message;

  const SmartRejected(this.message);
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
    String? entryId,
  }) {
    // Tefillin is not paginated and its units are not all the same height, so
    // it cannot be walked with one lines-per-unit. It has its own arithmetic
    // below; before this it fell through to the sefer branch and was recorded
    // as pages of a scroll, which is not a thing that exists.
    if (project.type == ProjectType.tefillin) {
      return _tefillin(project, from, to, worked, endedAt, history, entryId);
    }

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

    final wentBackwards =
        lastPage < from.page || (lastPage == from.page && lastLine < from.line);
    if (wentBackwards) return const SmartNothingWritten();

    // One mark for the whole sitting: the records below are its pages, and the
    // measured time is divided between them. See [WorkSession.entryId].
    final recordingId = entryId ?? IdGenerator.generate();

    return project.type == ProjectType.mezuza
        ? _mezuzot(project, from, lastPage, lastLine, linesPerUnit, worked,
            endedAt, recordingId)
        : _pages(project, from, lastPage, lastLine, linesPerUnit, worked,
            endedAt, history, recordingId);
  }

  /// A sitting on tefillin, recorded as one record per parshiya it touched.
  ///
  /// The position is a slot in the commission and a ruled line inside it —
  /// see [TefillinPosition.slotIndex]. Each record names its pair, its side and
  /// its parshiya, so what the writer did is recoverable exactly, and a
  /// parshiya left part-way carries the line he stopped on.
  static SmartOutcome _tefillin(
    Project project,
    SmartPosition from,
    SmartPosition to,
    Duration worked,
    DateTime endedAt,
    Iterable<WorkSession> history,
    String? entryId,
  ) {
    final startAt = TefillinPosition.fromSlotIndex(from.page);
    final slots = TefillinState.slots(project, history);
    final startSlot = slots.firstWhere(
      (s) =>
          s.pair == startAt.pair &&
          s.side == startAt.side &&
          s.parshiya == startAt.parshiya,
      orElse: () => TefillinSlot(
        pair: startAt.pair,
        side: startAt.side,
        parshiya: startAt.parshiya,
      ),
    );
    if (!TefillinState.canWrite(startSlot, slots)) {
      final name = TefillinUnits.names[startAt.parshiya - 1];
      final reason = switch (startSlot.state) {
        SlotState.done => 'פרשיית $name כבר הסתיימה',
        SlotState.voided =>
          'פרשיית $name נפסלה; יש להסיר אותה לפני שמתחילים מחדש',
        _ => 'אי אפשר לכתוב את $name לפני שהפרשייה הקודמת הסתיימה באותו סט',
      };
      return SmartRejected(reason);
    }

    // The stored line is the one about to be written, so the last one actually
    // written is the one before — and a slot standing at its first line means
    // the slot before it was finished.
    var lastSlot = to.page;
    var lastLine = to.line - 1;
    if (lastLine < 1) {
      if (lastSlot > from.page) {
        lastSlot--;
        lastLine = TefillinUnits.linesIn(
            TefillinPosition.fromSlotIndex(lastSlot).side);
      } else {
        lastLine = from.line - 1;
      }
    }

    if (lastSlot < from.page ||
        (lastSlot == from.page && lastLine < from.line)) {
      return const SmartNothingWritten();
    }

    final recordingId = entryId ?? IdGenerator.generate();
    final drafts = <_Draft>[];
    var lines = 0;

    for (var slot = from.page; slot <= lastSlot; slot++) {
      final at = TefillinPosition.fromSlotIndex(slot);
      final ruled = TefillinUnits.linesIn(at.side);
      final start = slot == from.page ? from.line : 1;
      final end = slot == lastSlot ? lastLine : ruled;
      if (end < start) continue;

      lines += end - start + 1;
      final whole = end >= ruled;
      final part = at.side == TefillinSide.head ? 'ראש' : 'יד';

      drafts.add(_Draft(
        id: IdGenerator.generate(suffix: '$slot'),
        // The first stretch introduces one parshiya. A later stretch carries
        // zero so 0.4.0 does not count the same physical parshiya twice when a
        // writer stops and resumes it. Current builds still read its exact
        // line contribution from the range below.
        amount: start == 1 ? 1 : 0,
        startLine: start,
        // Smart records keep an explicit range. Legacy/manual records use
        // startLine 0 and endLine 0 for a whole parshiya; both shapes remain
        // readable, but a range is the only way to add resumed work correctly.
        endLine: end,
        description: whole
            ? 'פרשיית ${at.parshiyaName} של $part (זוג ${at.pair})'
            : 'פרשיית ${at.parshiyaName} של $part (זוג ${at.pair}, עד שורה $end)',
        tefillinType: at.side == TefillinSide.head ? 'head' : 'hand',
        parshiya: at.parshiya,
        pairIndex: at.pair,
        weight: end - start + 1,
      ));
    }

    if (lines == 0) return const SmartNothingWritten();

    return SmartRecorded(
      sessions: _timed(project, drafts, worked, endedAt, recordingId),
      linesWritten: lines,
    );
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
    final drafts = <_Draft>[];
    var lines = 0;

    // One record per physical mezuza. A counted record could say that three
    // were written, but it could not say which of them was left at line 11 and
    // therefore could not bring the writer back to it after they skipped on.
    // `amount` remains one, so an older build still counts the record correctly;
    // the new identity travels in a field it carries through untouched.
    for (var unit = from.page; unit <= lastUnit; unit++) {
      final start = unit == from.page ? from.line : 1;
      final end = unit == lastUnit ? lastLine : linesPerUnit;
      if (end < start) continue;

      final written = end - start + 1;
      lines += written;
      drafts.add(_Draft(
        id: IdGenerator.generate(suffix: 'm$unit'),
        amount: 1,
        startLine: 0,
        // Zero means that this record by itself contains a whole mezuza.
        // A resumed final stretch is stored as its actual number of lines;
        // MezuzaState adds it to the earlier stretch carrying the same index.
        endLine: written == linesPerUnit ? 0 : written,
        description: written == linesPerUnit
            ? 'מזוזה $unit'
            : 'מזוזה $unit ($written שורות)',
        mezuzaIndex: unit,
        weight: written,
      ));
    }

    if (lines <= 0) return const SmartNothingWritten();

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
          mezuzaIndex: drafts[i].mezuzaIndex,
          tefillinType: drafts[i].tefillinType,
          parshiya: drafts[i].parshiya,
          pairIndex: drafts[i].pairIndex,
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

  /// Mezuzot only: the individual parchment this stretch belongs to.
  final int? mezuzaIndex;

  /// Tefillin only: which parshiya of which side of which pair.
  final String? tefillinType;
  final int? parshiya;
  final int? pairIndex;

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
    this.mezuzaIndex,
    this.tefillinType,
    this.parshiya,
    this.pairIndex,
  });
}
