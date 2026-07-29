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
}
