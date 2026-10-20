import '../models.dart';
import 'tefillin_units.dart';
import 'tefillin_text.dart';

class TefillinPlacement {
  final int pair;
  final TefillinSide side;
  final int parshiya;
  final int lines;
  final bool isWords;
  final DateTime startedOn;

  const TefillinPlacement({
    required this.pair,
    required this.side,
    required this.parshiya,
    required this.lines,
    this.isWords = false,
    required this.startedOn,
  });

  String get key => Project.slotKey(
      pair, side == TefillinSide.head ? 'head' : 'hand', parshiya);
}

/// Reads a tefillin commission out of the records it is made of.
///
/// Everything the board and the position sheet draw comes from here, and
/// nothing here is stored: how far each parshiya got is derived from the
/// sessions every time. The only facts that cannot be derived — a parshiya
/// stopped on for a correction, and one written off — come from
/// [Project.tefillinFlags].
///
/// Sessions recorded before pairs existed carry no [WorkSession.pairIndex].
/// Those are laid into the commission in writing order, which is precisely
/// what an older build was showing when it counted them, so nothing a writer
/// already has moves or disappears.
class TefillinState {
  const TefillinState._();

  static const String stuckFlag = 'stuck';
  static const String voidFlag = 'void';

  static String _sideName(TefillinSide side) =>
      side == TefillinSide.head ? 'head' : 'hand';

  /// Whether an untouched slot may be started without invalidating its set.
  /// The four parshiyot of each head or hand are written in order; work may
  /// move freely between sets, but never past an unfinished predecessor inside
  /// the same four.
  static bool canStart(
    TefillinSlot slot,
    Iterable<TefillinSlot> all,
  ) {
    if (slot.state != SlotState.empty) return true;
    if (slot.parshiya == 1) return true;
    for (final previous in all) {
      if (previous.pair == slot.pair &&
          previous.side == slot.side &&
          previous.parshiya == slot.parshiya - 1) {
        return previous.state == SlotState.done;
      }
    }
    return false;
  }

  /// Whether writing may continue in this slot right now.
  ///
  /// Unlike [canStart], this also rejects an already-finished or rejected
  /// slot, and it applies the predecessor rule to a slot that was partially
  /// written in an older build. Existing invalid history is not permission to
  /// add more invalid history.
  static bool canWrite(
    TefillinSlot slot,
    Iterable<TefillinSlot> all,
  ) {
    if (slot.state == SlotState.done || slot.state == SlotState.voided) {
      return false;
    }
    if (slot.parshiya == 1) return true;
    for (final previous in all) {
      if (previous.pair == slot.pair &&
          previous.side == slot.side &&
          previous.parshiya == slot.parshiya - 1) {
        return previous.state == SlotState.done;
      }
    }
    return false;
  }

  /// Unfinished work in an existing set, including the next Parashah after
  /// a completed one. Starting an unrelated pair stays an explicit choice.
  static List<TefillinSlot> continuations(
    Project project,
    Iterable<WorkSession> history,
  ) {
    final all = slots(project, history);
    return all.where((slot) {
      if (!canWrite(slot, all)) return false;
      if (slot.state == SlotState.partial) return true;
      if (slot.state != SlotState.empty) return false;
      return all.any((previous) =>
          previous.pair == slot.pair &&
          previous.state == SlotState.done &&
          (slot.parshiya > 1
              ? previous.side == slot.side &&
                  previous.parshiya == slot.parshiya - 1
              : slot.side == TefillinSide.hand &&
                  previous.side == TefillinSide.head &&
                  previous.parshiya == 4));
    }).toList();
  }

  /// Repairs a stored position left on completed work without jumping to
  /// another pair's progress or bypassing an invalidated Parashah.
  static ({int page, int line}) positionAfterCompleted({
    required Project project,
    required Iterable<WorkSession> history,
    required int page,
    required int line,
  }) {
    final byIndex = {
      for (final slot in slots(project, history))
        (slot.pair - 1) * 8 +
            (slot.side == TefillinSide.head ? 0 : 4) +
            slot.parshiya: slot,
    };
    var next = page;
    while (byIndex[next]?.state == SlotState.done) {
      next++;
    }
    return (
      page: next,
      line: next == page
          ? line
          : (byIndex[next]?.state == SlotState.partial ||
                      byIndex[next]?.state == SlotState.stuck) &&
                  byIndex[next]!.linesWritten <
                      TefillinUnits.linesIn(byIndex[next]!.side)
              ? byIndex[next]!.linesWritten + 1
              : 1,
    );
  }

  /// Soft-deletes one parshiya and everything after it in the same set.
  ///
  /// New 0.5.0 records always name their pair, side and parshiya, so the
  /// cascade is exact and remains recoverable through the recycle bin.
  static List<WorkSession> removeFrom({
    required Iterable<WorkSession> history,
    required String projectId,
    required int pair,
    required TefillinSide side,
    required int parshiya,
  }) {
    final sideName = _sideName(side);
    return [
      for (final session in history)
        if (!session.isDeleted &&
            session.projectId == projectId &&
            session.pairIndex == pair &&
            session.tefillinType == sideName &&
            (session.parshiya ?? 0) >= parshiya)
          session.copyWith(isDeleted: true)
        else
          session,
    ];
  }

  /// Every slot of [project], in writing order.
  ///
  /// The commission runs to its ordered size, or — when it has no target, or
  /// when more has been written than was ordered — to one pair past the last
  /// one worked on, so there is always somewhere to write next.
  static List<TefillinSlot> slots(
    Project project,
    Iterable<WorkSession> history,
  ) {
    final laidOut = placements(project, history);
    final written = <String, int>{};
    final began = <String, DateTime>{};
    final wordPieces = <String, List<WorkSession>>{};
    for (final s in history) {
      if (s.projectId != project.id ||
          s.isDeleted ||
          s.isInvalid ||
          !s.countsAsOutput ||
          !TefillinWordRange.isWordRecord(s)) {
        continue;
      }
      final range = TefillinWordRange.read(s);
      if (range == null) continue;
      final key = Project.slotKey(s.pairIndex!, s.tefillinType!, s.parshiya!);
      wordPieces.putIfAbsent(key, () => []).add(s);
    }
    var highestPair = 0;
    for (final pieces in laidOut.values) {
      for (final piece in pieces) {
        final full = TefillinUnits.linesIn(piece.side);
        written[piece.key] =
            ((written[piece.key] ?? 0) + piece.lines).clamp(0, full);
        began.putIfAbsent(piece.key, () => piece.startedOn);
        if (piece.pair > highestPair) highestPair = piece.pair;
      }
    }
    // Invalid work contributes no written lines, but its physical slot must
    // stay on the board so the writer can clear or remove the invalid mark.
    for (final key in project.tefillinFlags.keys) {
      final flaggedPair = int.tryParse(key.split(':').first);
      if (flaggedPair != null && flaggedPair > highestPair) {
        highestPair = flaggedPair;
      }
    }

    final ordered =
        project.type == ProjectType.tefillin ? (project.targetUnits ?? 0) : 0;
    final pairs = ordered > highestPair ? ordered : highestPair + 1;

    final out = <TefillinSlot>[];
    for (var pair = 1; pair <= pairs; pair++) {
      for (final side in TefillinSide.values) {
        for (var parshiya = 1; parshiya <= 4; parshiya++) {
          final key = Project.slotKey(pair, _sideName(side), parshiya);
          final lines = written[key] ?? 0;
          final flag = project.tefillinFlags[key];
          final words = wordPieces[key];
          final wordProgress = words == null
              ? null
              : wordPosition(words,
                  legacyFraction: lines / TefillinUnits.linesIn(side));
          final fraction =
              wordProgress?.fraction ?? lines / TefillinUnits.linesIn(side);

          final state = switch (flag) {
            voidFlag => SlotState.voided,
            stuckFlag => SlotState.stuck,
            _ when fraction >= 1 - 1e-9 => SlotState.done,
            _ when fraction > 0 => SlotState.partial,
            _ => SlotState.empty,
          };

          out.add(TefillinSlot(
            pair: pair,
            side: side,
            parshiya: parshiya,
            state: state,
            linesWritten: lines,
            wordBoundary: wordProgress?.boundary,
            wordFraction: wordProgress?.fraction,
            startedOn: began[key],
          ));
        }
      }
    }
    return out;
  }

  /// Only a contiguous covered prefix is a continuation. Deleting an early
  /// stretch leaves later ranges visible in history without jumping its gap.
  static ({int boundary, double fraction})? wordPosition(
      Iterable<WorkSession> sessions,
      {double legacyFraction = 0}) {
    final ranges = sessions
        .map(TefillinWordRange.read)
        .whereType<TefillinWordRange>()
        .toList();
    if (ranges.isEmpty) return null;
    final first = ranges.first;
    if ((first.baselineFraction - legacyFraction).abs() > 1e-9 ||
        ranges.any((r) =>
            r.baselineWord != first.baselineWord ||
            (r.baselineFraction - first.baselineFraction).abs() > 1e-9)) {
      return null;
    }
    var boundary = first.baselineWord;
    var changed = true;
    while (changed) {
      changed = false;
      for (final r in ranges) {
        if (r.from <= boundary && r.until > boundary) {
          boundary = r.until;
          changed = true;
        }
      }
    }
    final t = first.text;
    final fraction = legacyFraction +
        (1 - legacyFraction) *
            (t.letterBoundaries[boundary] -
                t.letterBoundaries[first.baselineWord]) /
            (t.letters - t.letterBoundaries[first.baselineWord]);
    return (boundary: boundary, fraction: fraction.clamp(0, 1).toDouble());
  }

  /// The forward position implied by the records already on the commission.
  ///
  /// Unlike the picker, this deliberately follows the furthest physical slot
  /// touched. A stopped earlier parshiya remains available for correction, but
  /// it must not pull the main writing position backwards after later work was
  /// entered manually.
  static ({int page, int line}) nextWritingPosition(
    Project project,
    Iterable<WorkSession> history,
  ) {
    final touched = slots(project, history)
        .where((slot) => slot.state != SlotState.empty)
        .toList();
    if (touched.isEmpty) return (page: 1, line: 1);
    int slotIndex(TefillinSlot slot) =>
        (slot.pair - 1) * 8 +
        (slot.side == TefillinSide.head ? 0 : 4) +
        slot.parshiya;
    touched.sort((a, b) => slotIndex(a).compareTo(slotIndex(b)));
    final last = touched.last;
    if (last.state == SlotState.partial || last.state == SlotState.stuck) {
      final line = last.linesWritten + 1;
      if (line <= TefillinUnits.linesIn(last.side)) {
        return (page: slotIndex(last), line: line);
      }
    }
    final nextPair = last.side == TefillinSide.hand && last.parshiya == 4
        ? last.pair + 1
        : last.pair;
    final nextSide = last.side == TefillinSide.head && last.parshiya == 4
        ? TefillinSide.hand
        : last.side;
    final nextParshiya = last.parshiya == 4 ? 1 : last.parshiya + 1;
    return (
      page: (nextPair - 1) * 8 +
          (nextSide == TefillinSide.head ? 0 : 4) +
          nextParshiya,
      line: 1,
    );
  }

  /// Maps every compatible record, including pre-pair legacy records, to the
  /// physical Parashiyot it represents. Correction code uses the same layout
  /// as the board, so tapping a legacy cell can never edit a different cell.
  static Map<String, List<TefillinPlacement>> placements(
    Project project,
    Iterable<WorkSession> history,
  ) {
    final sessions = history
        .where((s) =>
            s.projectId == project.id &&
            !s.isDeleted &&
            !s.isInvalid &&
            s.countsAsOutput)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final out = <String, List<TefillinPlacement>>{};
    final written = <String, int>{};

    void put(WorkSession session, int pair, TefillinSide side, int parshiya,
        int lines, DateTime when) {
      final key = Project.slotKey(pair, _sideName(side), parshiya);
      final full = TefillinUnits.linesIn(side);
      final now = (written[key] ?? 0) + (lines <= 0 ? full : lines);
      written[key] = now > full ? full : now;
      out.putIfAbsent(session.id, () => []).add(TefillinPlacement(
            pair: pair,
            side: side,
            parshiya: parshiya,
            lines: lines <= 0 ? full : lines,
            startedOn: when,
          ));
    }

    // Where unassigned work lands: the next free slot in writing order.
    var fillPair = 1;
    var fillSide = TefillinSide.head;
    var fillParshiya = 1;

    void advanceFill() {
      if (fillParshiya < 4) {
        fillParshiya++;
      } else if (fillSide == TefillinSide.head) {
        fillSide = TefillinSide.hand;
        fillParshiya = 1;
      } else {
        fillSide = TefillinSide.head;
        fillParshiya = 1;
        fillPair++;
      }
    }

    for (final s in sessions) {
      final day = s.workingDateAtEntry ?? s.startTime;
      if (TefillinWordRange.isWordRecord(s)) {
        if (TefillinWordRange.read(s) != null) {
          final side =
              s.tefillinType == 'head' ? TefillinSide.head : TefillinSide.hand;
          final key =
              Project.slotKey(s.pairIndex!, s.tefillinType!, s.parshiya!);
          out.putIfAbsent(s.id, () => []).add(TefillinPlacement(
              pair: s.pairIndex!,
              side: side,
              parshiya: s.parshiya!,
              lines: 0,
              isWords: true,
              startedOn: day));
          // Occupied for placement of legacy records lacking a pair address.
          written.putIfAbsent(key, () => 0);
        }
        continue;
      }
      final type = s.tefillinType;
      final parshiya = s.parshiya;
      final count = s.amount <= 0 ? 1 : s.amount;

      if (type != null && parshiya != null && parshiya >= 1 && parshiya <= 4) {
        final side = type == 'head' ? TefillinSide.head : TefillinSide.hand;
        // A stated pair is taken as stated. Without one the parshiya still has
        // a name, so it goes to the first pair whose matching slot is free.
        final stated = s.pairIndex;
        var pair = stated != null && stated >= 1 ? stated : 1;
        if (stated == null || stated < 1) {
          while (written
              .containsKey(Project.slotKey(pair, _sideName(side), parshiya))) {
            pair++;
          }
        }
        final ruled = TefillinUnits.linesIn(side);
        final lines = s.endLine <= 0
            ? ruled
            : s.startLine > 0
                ? s.endLine - s.startLine + 1
                : s.endLine;
        put(s, pair, side, parshiya, lines, day);
        continue;
      }

      // Whole pairs, or whole heads and hands: no parshiya was named, so the
      // work fills forward from wherever the filling has got to.
      final int slotsEach = (type == 'head' || type == 'hand') ? 4 : 8;
      for (var i = 0; i < count * slotsEach; i++) {
        if (type == 'head' || type == 'hand') {
          final side = type == 'head' ? TefillinSide.head : TefillinSide.hand;
          final p = (i % 4) + 1;
          // A stated pair takes every set the session records; without one they
          // run forward from wherever the filling has reached.
          final stated = s.pairIndex;
          final pair = stated != null && stated >= 1
              ? stated + (i ~/ 4)
              : fillPair + (i ~/ 4);
          put(s, pair, side, p, 0, day);
        } else {
          put(s, fillPair, fillSide, fillParshiya, 0, day);
          advanceFill();
        }
      }
    }
    return out;
  }

  /// Sefer torah lines written across a tefillin commission.
  ///
  /// This is the figure every cross-type comparison uses, and the reason the
  /// old count was wrong: it treated eight parshiyot as eight equal things
  /// when קדש is sixteen sefer lines and שמע is seven.
  static double seferLines(Project project, Iterable<WorkSession> history) {
    var total = 0.0;
    for (final slot in slots(project, history)) {
      total += slot.seferLinesWritten;
    }
    return total;
  }
}
