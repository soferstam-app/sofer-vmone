import '../models.dart';

/// Pure production calculations — how much was actually written.
///
/// These live outside the screens so the same numbers are produced everywhere.
/// Before this file the mezuza formula below was copied in five places across
/// two screens, which meant a change to it had to be remembered five times.
///
/// Nothing here touches Flutter, so every function is directly testable.
class ProductionCalculator {
  const ProductionCalculator._();

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
  static int mezuzaLinesInSession(WorkSession session) {
    if (session.endLine > 0) {
      final completed = session.amount > 0 ? session.amount - 1 : 0;
      return completed * linesPerMezuza + session.endLine;
    }
    return session.amount * linesPerMezuza;
  }

  /// Total lines written across mezuza sessions.
  static int mezuzaLinesTotal(Iterable<WorkSession> sessions) {
    var total = 0;
    for (final session in sessions) {
      total += mezuzaLinesInSession(session);
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
  static int seferLinesInSession(WorkSession session) =>
      session.endLine - session.startLine + 1;

  /// Total lines written across sefer sessions.
  static int seferLinesTotal(Iterable<WorkSession> sessions) {
    var total = 0;
    for (final session in sessions) {
      total += seferLinesInSession(session);
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
  static double seferPages(Iterable<WorkSession> sessions, Project project) {
    var pages = 0.0;
    for (final session in sessions) {
      pages += seferLinesInSession(session) /
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
    if (session.tefillinType == null && session.parshiya == null) {
      return session.amount * parshiyotPerSet;
    }
    if ((session.tefillinType == 'head' || session.tefillinType == 'hand') &&
        session.parshiya == null) {
      return session.amount * parshiyotPerUnit;
    }
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

  /// Parshiyot from a session, but only when the work is *complete*.
  ///
  /// Returns null for a partially written individual parshiya. Used for
  /// per-parshiya time averages, where a half-written parshiya would skew the
  /// result: its duration is real but the unit is not finished.
  ///
  /// Whole sets and whole head/hand units are always complete by definition.
  static int? completedParshiyotInSession(WorkSession session) {
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
}
