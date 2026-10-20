import '../models.dart';
import 'tefillin_text.dart';
import 'tefillin_state.dart';

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
    "והיה אם שמע",
  ];

  static String parshiyaName(int index) =>
      index >= 1 && index <= 4 ? parshiyotNames[index - 1] : "";

  /// Lines in a parshiya, which decides whether one is finished.
  static const int linesInHeadParshiya = 4;
  static const int linesInHandParshiya = 7;

  /// The eight slots: four parshiyot of the head, then four of the hand.
  static const int _slots = 8;

  static String describe(Iterable<WorkSession> sessions,
      {bool english = false}) {
    // How many of each parshiya were finished, and what was left part-written.
    final counts = List.filled(_slots, 0);
    final partials = <String>[];
    final rangeCovered = <String, Set<int>>{};
    final rangeSide = <String, String>{};
    final rangeParshiya = <String, int>{};
    final wordGroups = <String, List<WorkSession>>{};

    for (final s in sessions) {
      // Invalid writing remains part of the time denominator, but it is not
      // output and must not make a parshiya look complete in any description.
      if (s.isDeleted || s.isInvalid || !s.countsAsOutput) continue;
      final type = s.tefillinType;
      final parshiya = s.parshiya;
      if (TefillinWordRange.isWordRecord(s)) {
        if (TefillinWordRange.read(s) != null) {
          final key = '${s.pairIndex}:$type:$parshiya';
          wordGroups.putIfAbsent(key, () => []).add(s);
          rangeCovered.putIfAbsent(key, () => <int>{});
          rangeSide[key] = type!;
          rangeParshiya[key] = parshiya!;
        }
        continue;
      }

      // Every record with a physical address belongs to that one parshiya.
      // Older manual first stretches use startLine 0 and "up to line";
      // smart records and new manual continuations use exact ranges. Gather
      // both shapes here, otherwise a first stretch to line 3 followed by
      // lines 4–7 is described as a complete parshiya plus another partial.
      if (type != null && parshiya != null && s.pairIndex != null) {
        final maxLines =
            type == 'head' ? linesInHeadParshiya : linesInHandParshiya;
        final key = '${s.pairIndex}:$type:$parshiya';
        final from = s.startLine > 0 ? s.startLine : 1;
        final to = s.endLine <= 0 ? maxLines : s.endLine;
        final covered = rangeCovered.putIfAbsent(key, () => <int>{});
        for (var line = from.clamp(1, maxLines);
            line <= to.clamp(0, maxLines);
            line++) {
          covered.add(line);
        }
        rangeSide[key] = type;
        rangeParshiya[key] = parshiya;
        continue;
      }

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
          final part = english
              ? (type == 'head' ? 'Shel Rosh' : 'Shel Yad')
              : (type == 'head' ? "ראש" : "יד");
          partials.add(english
              ? "${parshiyaName(parshiya)} $part (to line ${s.endLine})"
              : "${parshiyaName(parshiya)} של $part (עד שורה ${s.endLine})");
        }
      }
    }

    for (final entry in rangeCovered.entries) {
      final type = rangeSide[entry.key]!;
      final parshiya = rangeParshiya[entry.key]!;
      final maxLines =
          type == 'head' ? linesInHeadParshiya : linesInHandParshiya;
      final words = wordGroups[entry.key];
      final position = words == null
          ? null
          : TefillinState.wordPosition(words,
              legacyFraction: entry.value.length / maxLines);
      if (words != null && position != null && position.fraction < 1 - 1e-9) {
        final word = TefillinText.of(parshiya).wordAt(position.boundary);
        partials.add(english
            ? '${parshiyaName(parshiya)} ${type == 'head' ? 'Shel Rosh' : 'Shel Yad'} (through word ${position.boundary}: $word)'
            : '${parshiyaName(parshiya)} של ${type == 'head' ? 'ראש' : 'יד'} (עד מילה ${position.boundary}: $word)');
      } else if ((position != null && position.fraction >= 1 - 1e-9) ||
          words == null && entry.value.length >= maxLines) {
        final base = type == 'head' ? 0 : 4;
        counts[base + parshiya - 1]++;
      } else {
        if (words != null) {
          partials.add(english
              ? '${parshiyaName(parshiya)} (word records need correction)'
              : '${parshiyaName(parshiya)} (רישומי המילים דורשים תיקון)');
          continue;
        }
        final part = english
            ? (type == 'head' ? 'Shel Rosh' : 'Shel Yad')
            : (type == 'head' ? 'ראש' : 'יד');
        final lastLine = entry.value.isEmpty
            ? 0
            : entry.value.reduce((a, b) => a > b ? a : b);
        partials.add(english
            ? '${parshiyaName(parshiya)} $part (to line $lastLine)'
            : '${parshiyaName(parshiya)} של $part (עד שורה $lastLine)');
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
      if (pairs > 0)
        english
            ? (pairs == 1 ? '1 Tefillin Set' : '$pairs Tefillin Sets')
            : (pairs == 1 ? "זוג תפילין אחד" : "$pairs זוגות תפילין"),
      if (headSets > 0)
        english ? '$headSets Tefillin Shel Rosh' : "$headSets תפילין של ראש",
      if (handSets > 0)
        english ? '$handSets Tefillin Shel Yad' : "$handSets תפילין של יד",
      for (var i = 0; i < _slots; i++)
        if (counts[i] > 0)
          _looseParshiyot(
              counts[i], parshiyaName((i % 4) + 1), i < 4 ? "ראש" : "יד",
              english: english),
      ...partials,
    ];

    if (parts.isEmpty) {
      return english
          ? 'No significant writing was recorded'
          : "לא נרשמה כתיבה משמעותית";
    }
    return parts.join(", ");
  }

  static String _looseParshiyot(int count, String name, String part,
          {bool english = false}) =>
      english
          ? (count == 1
              ? '$name Parashah ${part == 'ראש' ? 'Shel Rosh' : 'Shel Yad'}'
              : '$count $name Parashiyot ${part == 'ראש' ? 'Shel Rosh' : 'Shel Yad'}')
          : (count == 1
              ? "פרשיית $name של $part"
              : "$count פרשיות $name של $part");

  /// How many complete sets the slots in `[from, to)` can make.
  static int _smallest(List<int> counts, int from, int to) =>
      counts.sublist(from, to).reduce((a, b) => a < b ? a : b);

  static void _take(List<int> counts, int from, int to, int howMany) {
    for (var i = from; i < to; i++) {
      counts[i] -= howMany;
    }
  }
}
