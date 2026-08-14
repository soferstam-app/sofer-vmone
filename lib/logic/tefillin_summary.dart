import '../models.dart';

/// Says in words what a stretch of tefillin work came to.
///
/// Tefillin are recorded at whatever grain the writer works at: a whole pair,
/// a head or a hand on its own, a single parshiya, or a parshiya left
/// part-written. Saying that back as a list of what was entered would be
/// useless — "קדש של ראש, והיה כי יביאך של ראש, שמע של ראש…" — so the loose
/// parts are gathered back up into the largest wholes they make: pairs first,
/// then heads and hands, and only what is left over is named as parshiyot.
///
/// This is the app's one piece of arithmetic that is purely about the craft,
/// and it lived in a summary screen where nothing could reach it. It is pure
/// now, and the gathering is what the tests are about.
class TefillinSummary {
  const TefillinSummary._();

  /// The four parshiyot, in order. Index 1–4; anything else is not one.
  static const List<String> parshiyotNames = [
    "קדש",
    "והיה כי יביאך",
    "שמע",
    "והיה אם שמוע",
  ];

  static String parshiyaName(int index) =>
      index >= 1 && index <= 4 ? parshiyotNames[index - 1] : "";

  /// Lines in a parshiya, which decides whether one is finished.
  static const int linesInHeadParshiya = 4;
  static const int linesInHandParshiya = 7;

  /// The eight slots: four parshiyot of the head, then four of the hand.
  static const int _slots = 8;

  static String describe(Iterable<WorkSession> sessions) {
    // How many of each parshiya were finished, and what was left part-written.
    final counts = List.filled(_slots, 0);
    final partials = <String>[];

    for (final s in sessions) {
      final type = s.tefillinType;
      final parshiya = s.parshiya;

      if (type == null && parshiya == null) {
        // A whole pair: every slot advances.
        for (var i = 0; i < _slots; i++) {
          counts[i] += s.amount;
        }
      } else if (type == 'head' && parshiya == null) {
        for (var i = 0; i < 4; i++) {
          counts[i] += s.amount;
        }
      } else if (type == 'hand' && parshiya == null) {
        for (var i = 4; i < _slots; i++) {
          counts[i] += s.amount;
        }
      } else if (type != null && parshiya != null) {
        final maxLines =
            type == 'head' ? linesInHeadParshiya : linesInHandParshiya;
        if (s.endLine == 0 || s.endLine >= maxLines) {
          final base = type == 'head' ? 0 : 4;
          counts[base + parshiya - 1] += s.amount;
        } else {
          final part = type == 'head' ? "ראש" : "יד";
          partials
              .add("${parshiyaName(parshiya)} של $part (עד שורה ${s.endLine})");
        }
      }
    }

    // Gather the loose parshiyot back into wholes, largest first: a pair is
    // eight, a head or a hand is four, and only the remainder is named singly.
    final pairs = _smallest(counts, 0, _slots);
    _take(counts, 0, _slots, pairs);

    final headSets = _smallest(counts, 0, 4);
    _take(counts, 0, 4, headSets);

    final handSets = _smallest(counts, 4, _slots);
    _take(counts, 4, _slots, handSets);

    final parts = <String>[
      if (pairs > 0) pairs == 1 ? "זוג תפילין אחד" : "$pairs זוגות תפילין",
      if (headSets > 0) "$headSets תפילין של ראש",
      if (handSets > 0) "$handSets תפילין של יד",
      for (var i = 0; i < _slots; i++)
        if (counts[i] > 0)
          _looseParshiyot(counts[i], parshiyaName((i % 4) + 1),
              i < 4 ? "ראש" : "יד"),
      ...partials,
    ];

    if (parts.isEmpty) return "לא נרשמה כתיבה משמעותית";
    return parts.join(", ");
  }

  static String _looseParshiyot(int count, String name, String part) =>
      count == 1
          ? "פרשיית $name של $part"
          : "$count פרשיות $name של $part";

  /// How many complete sets the slots in `[from, to)` can make.
  static int _smallest(List<int> counts, int from, int to) =>
      counts.sublist(from, to).reduce((a, b) => a < b ? a : b);

  static void _take(List<int> counts, int from, int to, int howMany) {
    for (var i = from; i < to; i++) {
      counts[i] -= howMany;
    }
  }
}
