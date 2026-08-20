import '../models.dart';
import 'tefillin_units.dart';

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
    final sessions = history
        .where((s) => s.projectId == project.id && !s.isDeleted)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // Lines written into each slot, and the day work on it began.
    final written = <String, int>{};
    final began = <String, DateTime>{};
    var highestPair = 0;

    void put(
        int pair, TefillinSide side, int parshiya, int lines, DateTime when) {
      final key = Project.slotKey(pair, _sideName(side), parshiya);
      final full = TefillinUnits.linesIn(side);
      final now = (written[key] ?? 0) + (lines <= 0 ? full : lines);
      written[key] = now > full ? full : now;
      began.putIfAbsent(key, () => when);
      if (pair > highestPair) highestPair = pair;
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
        put(pair, side, parshiya, lines, day);
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
          put(pair, side, p, 0, day);
        } else {
          put(fillPair, fillSide, fillParshiya, 0, day);
          advanceFill();
        }
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

          final state = switch (flag) {
            voidFlag => SlotState.voided,
            stuckFlag => SlotState.stuck,
            _ when lines >= TefillinUnits.linesIn(side) => SlotState.done,
            _ when lines > 0 => SlotState.partial,
            _ => SlotState.empty,
          };

          out.add(TefillinSlot(
            pair: pair,
            side: side,
            parshiya: parshiya,
            state: state,
            linesWritten: lines,
            startedOn: began[key],
          ));
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
