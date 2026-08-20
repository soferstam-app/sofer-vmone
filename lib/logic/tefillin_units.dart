/// The sizes of tefillin work, in the one unit that can be compared to
/// everything else the app measures.
///
/// A tefillin line is not a sefer torah line. There is a fixed number of lines
/// in each parshiya, so the writing stretches sideways to fill them, and how
/// far it stretches depends on how much text the parshiya holds. A sofer who
/// writes one line of קדש has not done the same work as one who writes one line
/// of שמע, and neither has done a line of a sefer.
///
/// So a parshiya is measured here in *sefer torah lines* — what the same text
/// would occupy on a standard page. That is the number every cross-type
/// calculation uses: rate per hour, time per line, comparing one commission
/// against another.
///
/// Lines rather than a percentage of the set, because lines already carry the
/// half-lines. A parshiya ends where it ends, and so does a page of a sefer;
/// counting in whole lines and rounding to a percentage afterwards throws that
/// away.
enum TefillinSide { head, hand }

class TefillinUnits {
  const TefillinUnits._();

  /// The four, in the order they must be written. The order is not a
  /// convention — a set written out of it is invalid — which is what lets the
  /// board always name a single next parshiya.
  static const List<String> names = [
    'קדש',
    'והיה כי יביאך',
    'שמע',
    'והיה אם שמע',
  ];

  /// The same four where a cell is too narrow for the whole name.
  static const List<String> shortNames = [
    'קדש',
    'כי יביאך',
    'שמע',
    'אם שמע',
  ];

  /// One parshiya, measured in sefer torah lines.
  static const List<int> seferLines = [16, 12, 7, 17];

  /// A set is four parshiyot — either the head or the hand.
  static const int seferLinesPerSet = 52;

  /// A pair is two sets, head and hand. At 42 lines to the page this is a
  /// little under two and a half pages, which is why a pair cannot be a
  /// commission of its own.
  static const int seferLinesPerPair = 104;

  /// Actual lines ruled on the klaf, which is what the writer types when he
  /// stops part way. Nothing is compared in these.
  static const int linesPerHeadParshiya = 4;
  static const int linesPerHandParshiya = 7;

  static int linesIn(TefillinSide side) =>
      side == TefillinSide.head ? linesPerHeadParshiya : linesPerHandParshiya;

  /// How much of one set a parshiya is, 1-based. Derived from the lines rather
  /// than stored, so the two can never come to disagree.
  static double shareOfSet(int parshiya) =>
      seferLines[parshiya - 1] / seferLinesPerSet;

  static String sideName(TefillinSide side) =>
      side == TefillinSide.head ? 'של ראש' : 'של יד';
}

/// Where one parshiya of one set of one pair has got to.
enum SlotState {
  /// Not begun.
  empty,

  /// Begun and left part-written, [TefillinSlot.linesWritten] lines in.
  partial,

  done,

  /// Stopped on, waiting to be corrected. The writer moves to another set
  /// rather than sitting on it, which is the whole reason the board exists.
  stuck,

  /// Rejected. The slot is spent and its pair needs another.
  voided,
}

/// One cell of the board.
class TefillinSlot {
  /// 1-based, like everything the writer counts.
  final int pair;
  final TefillinSide side;

  /// 1–4, in writing order.
  final int parshiya;

  final SlotState state;

  /// Real ruled lines written, for [SlotState.partial] only.
  final int linesWritten;

  /// The day writing of this parshiya began — the earliest session recorded
  /// against the slot.
  ///
  /// A pair number is a label with nothing behind it: "pair four" tells a sofer
  /// nothing about which job it was. The day he started it does. Null on a slot
  /// never begun, and on anything recorded before the sessions carried a pair.
  final DateTime? startedOn;

  const TefillinSlot({
    required this.pair,
    required this.side,
    required this.parshiya,
    this.state = SlotState.empty,
    this.linesWritten = 0,
    this.startedOn,
  });

  /// How much of this parshiya is written, 0–1.
  double get fraction => switch (state) {
        SlotState.done => 1,
        SlotState.partial => (linesWritten / TefillinUnits.linesIn(side))
            .clamp(0.0, 1.0)
            .toDouble(),
        _ => 0,
      };

  /// Sefer torah lines this slot has produced.
  double get seferLinesWritten =>
      TefillinUnits.seferLines[parshiya - 1] * fraction;
}
