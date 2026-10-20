import '../models.dart';

/// The records a figure involving time may be computed from.
///
/// The rule, and it is one rule: **a quantity counts valid output; a time ratio
/// counts every non-deleted timed record — including work later ruled invalid.**
///
/// Sums of output are quantities. Lines written, pages done, profit, progress,
/// a delivery date: every record belongs in those. Minutes per line and shekels
/// per hour are ratios, and a record entered without hours has no place in
/// either half of one. It contributes zero minutes while its lines still count,
/// so the writer comes out faster and better paid than anything measured says —
/// always in the flattering direction, and never visibly.
///
/// Seven screens each decided this for themselves and several got it wrong in
/// the same way: they summed time from measured records and then divided it by
/// all the output. One filter, used by all of them, is what stops that drifting
/// apart again.
class MeasuredWork {
  const MeasuredWork._();

  /// Whether this record can take part in a ratio involving time.
  ///
  /// Deletion, a duration of zero or less, or an unmarked record is refused: a
  /// session written before the midnight-crossing fix can hold a negative
  /// length, and subtracting it from an hour of real work would report less
  /// time than was spent.
  static bool countsForTime(WorkSession session) =>
      !session.isDeleted && session.timeRecorded && session.duration > Duration.zero;

  /// The subset of [sessions] a time ratio may use.
  static List<WorkSession> only(Iterable<WorkSession> sessions) =>
      sessions.where(countsForTime).toList();

  /// Time actually measured across [sessions].
  static Duration time(Iterable<WorkSession> sessions) {
    var total = Duration.zero;
    for (final s in sessions) {
      if (countsForTime(s)) total += s.duration;
    }
    return total;
  }

  /// Whether any of [sessions] carries no time, so a screen can say that the
  /// average it is showing rests on part of the work rather than all of it.
  static bool anyUntimed(Iterable<WorkSession> sessions) =>
      sessions.any((s) => !countsForTime(s));

  /// Time spent on physical work that was later ruled invalid. It remains a
  /// real cost of the commission even though it contributes no output.
  static Duration invalidTime(Iterable<WorkSession> sessions) => time(
        sessions.where((s) => !s.isDeleted && s.isInvalid),
      );

  /// Valid output eligible for a writing-speed ratio.
  static List<WorkSession> validOnly(Iterable<WorkSession> sessions) =>
      sessions.where((s) => !s.isDeleted && !s.isInvalid).toList();
}
