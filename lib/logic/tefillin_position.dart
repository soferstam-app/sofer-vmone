import 'tefillin_units.dart';
import 'tefillin_state.dart';

/// Where a writer is in a tefillin commission, and where he might go next.
///
/// A sefer has one place to be and two numbers to say it — page and line — so
/// moving is a matter of typing them. Tefillin has eighty places in a ten-pair
/// order, and typing three numbers to say "the shema of the hand of pair four"
/// is worse than useless when the timer is running and the sofer is holding a
/// quill.
///
/// So nothing is typed. Almost everything a writer wants is one of a handful of
/// slots: the one he is on, the two or three he stopped part way through, the
/// ones held up for a correction, and the next few in writing order. **What is
/// finished is never offered** — it is the largest group by far and the one
/// nobody needs to reach in a hurry, and leaving it out is what keeps the list
/// short enough to read at a glance.
class TefillinPosition {
  final int pair;
  final TefillinSide side;
  final int parshiya;

  const TefillinPosition({
    required this.pair,
    required this.side,
    required this.parshiya,
  });

  String get parshiyaName => TefillinUnits.names[parshiya - 1];

  /// "זוג 4 · של יד" — everything except the parshiya, which is said larger.
  String get whereLabel => 'זוג $pair · ${TefillinUnits.sideName(side)}';

  /// Real ruled lines in this parshiya — 4 on a head, 7 on a hand.
  int get lineCount => TefillinUnits.linesIn(side);

  /// The next slot in writing order, with no regard for what is already
  /// written. Rolls through the four parshiyot, then head to hand, then on to
  /// the next pair.
  TefillinPosition get next {
    if (parshiya < 4) {
      return TefillinPosition(pair: pair, side: side, parshiya: parshiya + 1);
    }
    if (side == TefillinSide.head) {
      return TefillinPosition(pair: pair, side: TefillinSide.hand, parshiya: 1);
    }
    return TefillinPosition(
        pair: pair + 1, side: TefillinSide.head, parshiya: 1);
  }

  /// Sorts as the work is written: pair, then head before hand, then order.
  int get sortKey => (pair * 8) + (side.index * 4) + parshiya;

  /// This slot's place in the commission, counted from one.
  ///
  /// Smart mode stores where the writer is as two numbers, because a sefer has
  /// two. Tefillin has three — pair, side, parshiya — so the first two are
  /// folded into one running count and the ruled line stays the second. Slot 1
  /// is the קדש of the first head; slot 9 is the קדש of the second.
  ///
  /// Folding rather than adding a third stored number is what keeps a file
  /// written here readable by a build that knows nothing about pairs.
  int get slotIndex =>
      (pair - 1) * 8 + (side == TefillinSide.head ? 0 : 4) + parshiya;

  static TefillinPosition fromSlotIndex(int index) {
    final i = index < 1 ? 0 : index - 1;
    final within = i % 8;
    return TefillinPosition(
      pair: (i ~/ 8) + 1,
      side: within < 4 ? TefillinSide.head : TefillinSide.hand,
      parshiya: (within % 4) + 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TefillinPosition &&
      other.pair == pair &&
      other.side == side &&
      other.parshiya == parshiya;

  @override
  int get hashCode => sortKey;
}

/// The short list of places worth offering, and nothing else.
class TefillinPicks {
  /// Begun and left part-written. The reason the whole thing exists: a sofer
  /// stops on a parshiya because something went wrong, starts another, and has
  /// to be able to come back without hunting.
  final List<TefillinSlot> stopped;

  /// Held up until it can be corrected.
  final List<TefillinSlot> stuck;

  /// The next few unwritten slots, in order. One tap covers the ordinary case,
  /// which is a writer working straight through.
  final List<TefillinSlot> nextUp;

  const TefillinPicks({
    required this.stopped,
    required this.stuck,
    required this.nextUp,
  });

  bool get isEmpty => stopped.isEmpty && stuck.isEmpty && nextUp.isEmpty;

  /// Everything offered, in the order the sheet lists it.
  List<TefillinSlot> get all => [...stopped, ...stuck, ...nextUp];

  /// Reads the commission and picks what to offer.
  ///
  /// [current] is left out of every group — the writer is already there, and
  /// offering somebody the place they are standing is noise.
  static TefillinPicks from(
    Iterable<TefillinSlot> slots, {
    TefillinPosition? current,
    int nextCount = 3,
  }) {
    bool isCurrent(TefillinSlot s) =>
        current != null &&
        s.pair == current.pair &&
        s.side == current.side &&
        s.parshiya == current.parshiya;

    final ordered = slots.where((s) => !isCurrent(s)).toList()
      ..sort((a, b) => _key(a).compareTo(_key(b)));

    final stopped = <TefillinSlot>[];
    final stuck = <TefillinSlot>[];
    final nextUp = <TefillinSlot>[];

    for (final s in ordered) {
      switch (s.state) {
        case SlotState.partial:
          if (TefillinState.canWrite(s, slots)) stopped.add(s);
        case SlotState.stuck:
          if (TefillinState.canWrite(s, slots)) stuck.add(s);
        case SlotState.empty:
          if (nextUp.length < nextCount && TefillinState.canStart(s, slots)) {
            nextUp.add(s);
          }
        // Finished and rejected slots are never offered. One because there is
        // nothing to do there, the other because there is nothing to be done.
        case SlotState.done:
        case SlotState.voided:
          break;
      }
    }

    return TefillinPicks(stopped: stopped, stuck: stuck, nextUp: nextUp);
  }

  static int _key(TefillinSlot s) =>
      (s.pair * 8) + (s.side.index * 4) + s.parshiya;
}
