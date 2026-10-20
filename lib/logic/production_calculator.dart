import '../models.dart';
import 'megillah_format.dart';
import 'tefillin_units.dart';
import 'tefillin_text.dart';
import 'tefillin_state.dart';

/// The measured, fully completed work that can form a time-per-parshiya ratio.
class TefillinAverageStats {
  final int parshiyot;
  final Duration duration;

  const TefillinAverageStats({
    required this.parshiyot,
    required this.duration,
  });
}

/// Pure production calculations — how much was actually written.
///
/// These live outside the screens so the same numbers are produced everywhere.
/// Before this file the mezuza formula below was copied in five places across
/// two screens, which meant a change to it had to be remembered five times.
///
/// Nothing here touches Flutter, so every function is directly testable.
class ProductionCalculator {
  const ProductionCalculator._();

  /// Relative difficulty of one physical writing line when comparing the
  /// four kinds of work. A mezuzah line is worth 1.1 Sefer lines and a
  /// tefillin line 1.3; Sefer Torah and Megillah lines are the reference 1.0.
  /// These are production/value weights, not a change to the stored line
  /// counts or to the progress shown for a project.
  static const double mezuzaLineWeight = 1.1;
  static const double tefillinLineWeight = 1.3;

  /// A Megillah's pricing axis is deliberately fixed at ten standard Sefer
  /// pages, even when its physical layout has 418 or 448 lines.
  static const int megillahPricingPages = 10;
  static const int megillahPricingLines =
      megillahPricingPages * defaultLinesPerPage;

  static double lineWeight(ProjectType type) => switch (type) {
        ProjectType.sefer || ProjectType.megillah => 1.0,
        ProjectType.mezuza => mezuzaLineWeight,
        ProjectType.tefillin => tefillinLineWeight,
      };

  /// Standard line count of a single mezuza.
  static const int linesPerMezuza = 22;

  /// Lines written in one mezuza session.
  ///
  /// A session records [WorkSession.amount] whole mezuzot, and optionally an
  /// [WorkSession.endLine] marking how far into the last one the writer got:
  ///
  /// * `amount: 3, endLine: 0`  → three complete mezuzot (66 lines)
  /// * `amount: 3, endLine: 10` → two complete plus 10 lines (54 lines)
  /// * `amount: 1, endLine: 10` → 10 lines into the first mezuza
  static int mezuzaLinesInSession(WorkSession session,
      {bool includeInvalid = false}) {
    if (session.isDeleted ||
        !session.countsAsOutput ||
        (!includeInvalid && session.isInvalid)) {
      return 0;
    }
    if (session.endLine > 0) {
      final completed = session.amount > 0 ? session.amount - 1 : 0;
      return completed * linesPerMezuza + session.endLine;
    }
    return session.amount * linesPerMezuza;
  }

  /// Total lines written across mezuza sessions.
  static int mezuzaLinesTotal(Iterable<WorkSession> sessions,
      {bool includeInvalid = false}) {
    var total = 0;
    for (final session in sessions) {
      total += mezuzaLinesInSession(session, includeInvalid: includeInvalid);
    }
    return total;
  }

  /// Total expressed in mezuzot, including a fractional last one.
  static double mezuzotTotal(Iterable<WorkSession> sessions) =>
      mezuzaLinesTotal(sessions) / linesPerMezuza;

  // --- Sefer Torah ---

  /// Default page geometry, used when a project leaves it unset.
  static const int defaultLinesPerPage = 42;
  static const int defaultTotalPages = 245;

  /// Lines written in one sefer session.
  ///
  /// The range is inclusive on both ends: writing line 5 through line 5 is one
  /// line, not zero.
  static int seferLinesInSession(WorkSession session,
          {bool includeInvalid = false}) =>
      session.isDeleted ||
              !session.countsAsOutput ||
              (!includeInvalid && session.isInvalid)
          ? 0
          : session.endLine - session.startLine + 1;

  /// Total lines written across sefer sessions.
  static int seferLinesTotal(Iterable<WorkSession> sessions,
      {bool includeInvalid = false}) {
    var total = 0;
    for (final session in sessions) {
      total += seferLinesInSession(session, includeInvalid: includeInvalid);
    }
    return total;
  }

  /// Lines per page for a project, falling back to the default and guarding
  /// against a stored zero, which would otherwise divide by zero.
  static int linesPerPageOf(Project project) {
    final value = project.linesPerPage ?? defaultLinesPerPage;
    return value <= 0 ? defaultLinesPerPage : value;
  }

  /// Lines per page that applied when [session] was recorded.
  ///
  /// Prefers the value snapshotted on the session, so changing the project
  /// setting later does not rewrite what past work was worth. Sessions
  /// recorded before the snapshot existed fall back to the project setting,
  /// which is the old behaviour.
  static int linesPerPageForSession(Project project, WorkSession session) {
    final snapshot = session.linesPerPageAtEntry;
    if (snapshot != null && snapshot > 0) return snapshot;
    return linesPerPageOf(project);
  }

  /// Written lines expressed as a (fractional) number of pages.
  ///
  /// Each session is converted using the page size that applied to it, so a
  /// project whose geometry changed mid-way still totals correctly.
  static double seferPages(Iterable<WorkSession> sessions, Project project,
      {bool includeInvalid = false}) {
    var pages = 0.0;
    for (final session in sessions) {
      pages += seferLinesInSession(session, includeInvalid: includeInvalid) /
          linesPerPageForSession(project, session);
    }
    return pages;
  }

  // --- Tefillin ---

  /// A full set is head + hand, four parshiyot each.
  static const int parshiyotPerSet = 8;
  static const int parshiyotPerUnit = 4;

  /// Line counts of a single parshiya, which differ between head and hand.
  static const int linesPerHeadParshiya = 4;
  static const int linesPerHandParshiya = 7;

  /// Parshiyot represented by one tefillin session.
  ///
  /// The session shape encodes what was written:
  /// * no type and no parshiya → whole sets, 8 parshiyot each
  /// * a type but no parshiya  → whole head or hand units, 4 parshiyot each
  /// * both set               → individual parshiyot, counted as-is
  static int parshiyotInSession(WorkSession session) {
    if (session.isDeleted || session.isInvalid || !session.countsAsOutput) {
      return 0;
    }
    if (TefillinWordRange.isWordRecord(session)) {
      final w = TefillinWordRange.read(session);
      return w != null &&
              w.baselineFraction == 0 &&
              w.until == w.text.words.length
          ? 1
          : 0;
    }
    if (session.tefillinType == null && session.parshiya == null) {
      return session.amount * parshiyotPerSet;
    }
    if ((session.tefillinType == 'head' || session.tefillinType == 'hand') &&
        session.parshiya == null) {
      return session.amount * parshiyotPerUnit;
    }
    // A resumed smart-mode stretch is the rest of a parshiya already counted
    // by its first stretch. It deliberately carries amount 0 for 0.4.0 too.
    return session.amount;
  }

  /// Total parshiyot across tefillin sessions.
  static int parshiyotTotal(Iterable<WorkSession> sessions) {
    var total = 0;
    for (final session in sessions) {
      total += parshiyotInSession(session);
    }
    return total;
  }

  /// Physical ruled lines attempted in a tefillin session. Invalid work may
  /// be included for time-per-line; deleted records never return.
  static int tefillinPhysicalLinesInSession(WorkSession session,
      {bool includeInvalid = false}) {
    if (session.isDeleted ||
        !session.countsAsOutput ||
        (!includeInvalid && session.isInvalid)) {
      return 0;
    }
    final type = session.tefillinType;
    final parshiya = session.parshiya;
    if (type != null && parshiya != null) {
      final ruled =
          type == 'head' ? linesPerHeadParshiya : linesPerHandParshiya;
      final explicitRange = session.startLine > 0;
      final lines = session.endLine <= 0
          ? ruled
          : explicitRange
              ? session.endLine - session.startLine + 1
              : session.endLine;
      final records =
          explicitRange ? 1 : (session.amount <= 0 ? 0 : session.amount);
      return records * lines.clamp(0, ruled);
    }
    if (type == 'head' || type == 'hand') {
      final perParshiya =
          type == 'head' ? linesPerHeadParshiya : linesPerHandParshiya;
      return (session.amount <= 0 ? 0 : session.amount) *
          parshiyotPerUnit *
          perParshiya;
    }
    return (session.amount <= 0 ? 0 : session.amount) *
        (linesPerHeadParshiya + linesPerHandParshiya) *
        parshiyotPerUnit;
  }

  static int tefillinPhysicalLinesTotal(Iterable<WorkSession> sessions,
      {bool includeInvalid = false}) {
    var total = 0;
    for (final session in sessions) {
      total += tefillinPhysicalLinesInSession(session,
          includeInvalid: includeInvalid);
    }
    return total;
  }

  /// Parshiyot from a session, but only when the work is *complete*.
  ///
  /// Returns null for a partially written individual parshiya. Used for
  /// per-parshiya time averages, where a half-written parshiya would skew the
  /// result: its duration is real but the unit is not finished.
  ///
  /// Whole sets and whole head/hand units are always complete by definition.
  static int? completedParshiyotInSession(WorkSession session) {
    if (TefillinWordRange.isWordRecord(session)) {
      final words = TefillinWordRange.read(session);
      if (session.isDeleted ||
          session.isInvalid ||
          !session.countsAsOutput ||
          words == null) {
        return null;
      }
      return words.from == 0 && words.until == words.text.words.length
          ? 1
          : null;
    }
    if (session.isDeleted || session.isInvalid || !session.countsAsOutput) {
      return null;
    }
    if (session.tefillinType == null && session.parshiya == null) {
      return session.amount * parshiyotPerSet;
    }
    if ((session.tefillinType == 'head' || session.tefillinType == 'hand') &&
        session.parshiya == null) {
      return session.amount * parshiyotPerUnit;
    }
    if (session.tefillinType != null && session.parshiya != null) {
      final maxLines = session.tefillinType == 'head'
          ? linesPerHeadParshiya
          : linesPerHandParshiya;
      // endLine 0 means no partial line was recorded, i.e. finished.
      if (session.endLine == 0 || session.endLine >= maxLines) {
        return session.amount;
      }
      return null;
    }
    return null;
  }

  /// Completed parshiyot and the measured time that produced exactly them.
  ///
  /// A smart parshiya may span several sittings. Its first record carries the
  /// count and its resumed record carries zero for backward compatibility, so
  /// no record by itself contains both the full duration and a completed unit.
  /// Grouping by pair, side and parshiya reconstructs the physical unit and
  /// counts it only when the measured records cover every ruled line.
  static TefillinAverageStats tefillinAverageStats(
      Iterable<WorkSession> sessions) {
    final measured = sessions
        .where((s) =>
            !s.isDeleted &&
            !s.isInvalid &&
            s.timeRecorded &&
            s.duration > Duration.zero)
        .toList();
    var count = 0;
    var duration = Duration.zero;
    final identified = <String, List<WorkSession>>{};

    for (final session in measured) {
      final isIndividual =
          session.tefillinType != null && session.parshiya != null;
      if (isIndividual && session.pairIndex != null) {
        final key = '${session.pairIndex}|${session.tefillinType}|'
            '${session.parshiya}';
        identified.putIfAbsent(key, () => []).add(session);
        continue;
      }

      // Whole pairs/units and legacy unidentifiable parshiyot cannot be joined
      // to another record safely, so retain their per-record meaning.
      final completed = completedParshiyotInSession(session);
      if (completed != null && completed > 0) {
        count += completed;
        duration += session.duration;
      }
    }

    for (final group in identified.values) {
      final first = group.first;
      final maxLines = first.tefillinType == 'head'
          ? linesPerHeadParshiya
          : linesPerHandParshiya;
      final covered = List<bool>.filled(maxLines, false);

      for (final session in group) {
        if (!session.countsAsOutput ||
            TefillinWordRange.isWordRecord(session)) {
          continue;
        }
        final from = session.startLine > 0 ? session.startLine : 1;
        final to = session.endLine <= 0 ? maxLines : session.endLine;
        for (var line = from.clamp(1, maxLines);
            line <= to.clamp(0, maxLines);
            line++) {
          covered[line - 1] = true;
        }
      }

      final wordSessions = group.where(TefillinWordRange.isWordRecord).toList();
      final wordPosition = TefillinState.wordPosition(wordSessions,
          legacyFraction: covered.where((v) => v).length / maxLines);
      if (wordSessions.isNotEmpty
          ? wordPosition != null && wordPosition.fraction >= 1 - 1e-9
          : covered.every((line) => line)) {
        count++;
        for (final session in group) {
          duration += session.duration;
        }
      }
    }

    return TefillinAverageStats(parshiyot: count, duration: duration);
  }

  /// Sefer torah lines produced by one tefillin session.
  ///
  /// The unit every comparison is made in. Counting parshiyot instead treated
  /// all eight as equal, so a sitting spent on שמע — seven sefer lines — scored
  /// the same as one spent on והיה אם שמע, which is seventeen. A writer could
  /// not see which of his work paid.
  ///
  /// Works on any subset of the history, because a session names its own
  /// parshiya and a parshiya's size does not depend on which pair it belongs
  /// to.
  static double tefillinSeferLines(WorkSession session,
      {bool includeInvalid = false}) {
    if (session.isDeleted ||
        !session.countsAsOutput ||
        (!includeInvalid && session.isInvalid)) {
      return 0;
    }
    final count = session.amount <= 0 ? 0 : session.amount;
    if (TefillinWordRange.isWordRecord(session)) {
      final words = TefillinWordRange.read(session);
      return words == null
          ? 0
          : words.fractionAdded * TefillinUnits.seferLines[words.parshiya - 1];
    }
    final type = session.tefillinType;
    final parshiya = session.parshiya;

    if (type != null && parshiya != null && parshiya >= 1 && parshiya <= 4) {
      final side = type == 'head' ? TefillinSide.head : TefillinSide.hand;
      final ruled = TefillinUnits.linesIn(side);
      // New smart records are exact ranges, including continuation records
      // whose amount is deliberately zero so an older build does not count a
      // resumed parshiya twice. Legacy/manual records have startLine zero and
      // keep the old "last line reached" meaning.
      final explicitRange = session.startLine > 0;
      final lines = session.endLine <= 0
          ? ruled
          : explicitRange
              ? session.endLine - session.startLine + 1
              : session.endLine;
      final records = explicitRange ? 1 : count;
      final fraction = lines.clamp(0, ruled) / ruled;
      return records * TefillinUnits.seferLines[parshiya - 1] * fraction;
    }

    if (count == 0) return 0;

    // A whole head or hand is a set; anything else recorded is a whole pair.
    if (type == 'head' || type == 'hand') {
      return count * TefillinUnits.seferLinesPerSet.toDouble();
    }
    return count * TefillinUnits.seferLinesPerPair.toDouble();
  }

  static double tefillinSeferLinesTotal(Iterable<WorkSession> sessions,
      {bool includeInvalid = false}) {
    var total = 0.0;
    for (final session in sessions) {
      total += tefillinSeferLines(session, includeInvalid: includeInvalid);
    }
    return total;
  }

  /// Comparable output in weighted Sefer-line units. This is used only for
  /// cross-type pace and value comparisons; the ordinary project unit and the
  /// physical line display remain unchanged.
  static double comparableLinesInSession(Project project, WorkSession session,
      {bool includeInvalid = false}) {
    final raw = switch (project.type) {
      ProjectType.sefer ||
      ProjectType.megillah =>
        seferLinesInSession(session, includeInvalid: includeInvalid).toDouble(),
      ProjectType.mezuza =>
        mezuzaLinesInSession(session, includeInvalid: includeInvalid)
            .toDouble(),
      ProjectType.tefillin =>
        tefillinSeferLines(session, includeInvalid: includeInvalid),
    };
    return raw * lineWeight(project.type);
  }

  static double comparableLinesTotal(
      Project project, Iterable<WorkSession> sessions,
      {bool includeInvalid = false}) {
    var total = 0.0;
    for (final session in sessions) {
      total += comparableLinesInSession(project, session,
          includeInvalid: includeInvalid);
    }
    return total;
  }

  /// Weighted Sefer-line count of one quote unit. A Megillah quote unit is the
  /// whole commission, whose geometry is selected explicitly; a Sefer quote
  /// unit is one page.
  static double comparableLinesPerUnit(
    ProjectType type, {
    String? megillahFormat,
    int? seferLinesPerPage,
    int? megillahPages,
    int? megillahLinesPerPage,
  }) {
    switch (type) {
      case ProjectType.sefer:
        return (seferLinesPerPage ?? defaultLinesPerPage).toDouble();
      case ProjectType.mezuza:
        return linesPerMezuza * mezuzaLineWeight;
      case ProjectType.tefillin:
        return TefillinUnits.seferLinesPerPair * tefillinLineWeight;
      case ProjectType.megillah:
        final pages = megillahPages ??
            (megillahFormat == null
                ? MegillahFormat.totalPages(MegillahFormat.lines11)
                : MegillahFormat.totalPages(megillahFormat));
        final lines = megillahLinesPerPage ??
            (megillahFormat == null
                ? MegillahFormat.storedLinesPerPage(MegillahFormat.lines11)
                : MegillahFormat.storedLinesPerPage(megillahFormat));
        return pages * lines * lineWeight(type);
    }
  }

  /// Weighted lines used only for the money axis. Writing time never calls
  /// this for a Megillah: its time axis is the physical line count above.
  static double pricingComparableLinesPerUnit(
    ProjectType type, {
    int? seferLinesPerPage,
  }) {
    switch (type) {
      case ProjectType.sefer:
        return (seferLinesPerPage ?? defaultLinesPerPage).toDouble();
      case ProjectType.mezuza:
        return linesPerMezuza * mezuzaLineWeight;
      case ProjectType.tefillin:
        return TefillinUnits.seferLinesPerPair * tefillinLineWeight;
      case ProjectType.megillah:
        return megillahPricingLines.toDouble();
    }
  }

  /// Work of any kind, measured in sefer torah lines.
  ///
  /// What makes an hour on tefillin comparable to an hour on a sefer. Before
  /// this the monthly average was labelled "ספר/מזוזה" and simply left tefillin
  /// out, because the only tefillin figure available was a count of parshiyot
  /// and there was nothing to compare it to.
  static double seferEquivalentLines(
      Project project, Iterable<WorkSession> sessions) {
    return comparableLinesTotal(project, sessions);
  }

  /// Physical units completed for progress and planning. This deliberately
  /// differs from billing for Megillah: it is priced as one whole commission
  /// but planned page by page.
  static double projectUnits(Project project, Iterable<WorkSession> sessions) {
    return switch (project.type) {
      ProjectType.sefer ||
      ProjectType.megillah =>
        seferPages(sessions, project),
      ProjectType.mezuza => mezuzaLinesTotal(sessions) / linesPerMezuza,
      ProjectType.tefillin =>
        tefillinSeferLinesTotal(sessions) / TefillinUnits.seferLinesPerPair,
    };
  }
}
