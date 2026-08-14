import '../models.dart';
import 'currency.dart';

/// What is out for proofreading, what is waiting, and what it has cost.
///
/// The screen asks three questions and this answers all of them from one pass:
/// what has to be acted on, what is sitting with someone else, and what the
/// stage has cost so far. Kept out of the widget so the arithmetic can be
/// checked without one.
class ProofreadBoard {
  /// Live records, newest first within each stage.
  final List<Proofread> records;

  /// What proofreading has cost, per currency — a batch may have been paid for
  /// in something other than the commission's own currency, and adding those
  /// together would give a number that is not a total of anything.
  final MoneyTotal spent;

  const ProofreadBoard._({required this.records, required this.spent});

  static ProofreadBoard of(Iterable<Proofread> all, {String? projectId}) {
    final live = all
        .where((r) =>
            !r.isDeleted && (projectId == null || r.projectId == projectId))
        .toList();

    // Within a stage, the most recently touched first: what a writer looked at
    // last is what he is most likely looking for.
    live.sort((a, b) {
      final byStage = a.stage.index.compareTo(b.stage.index);
      return byStage != 0 ? byStage : b.lastUpdated.compareTo(a.lastUpdated);
    });

    final spent = MoneyTotal();
    for (final r in live) {
      if (r.cost > 0) spent.addAmount(r.cost, r.currency);
    }

    return ProofreadBoard._(records: live, spent: spent);
  }

  Iterable<Proofread> at(ProofreadStage stage) =>
      records.where((r) => r.stage == stage);

  /// Everything not yet finished.
  Iterable<Proofread> get open => records.where((r) => r.stage.isOpen);

  /// Waiting on the sofer: not sent yet, or back and not yet corrected.
  ///
  /// The distinction that makes the screen worth opening — "with the magiah" is
  /// somebody else's turn, and these two are his.
  Iterable<Proofread> get mine => records.where((r) =>
      r.stage == ProofreadStage.waiting || r.stage == ProofreadStage.returned);

  /// Out longer than [days] and not back. Not an error — proofreading takes as
  /// long as it takes — but the thing a writer wants to see without counting.
  Iterable<Proofread> overdue({int days = 21, DateTime? now}) =>
      at(ProofreadStage.sent).where((r) {
        final out = r.turnaround(now: now);
        return out != null && out.inDays > days;
      });

  /// How many corrections came back per batch, where anyone wrote it down.
  ///
  /// Null when nothing has been recorded: an average over no observations is
  /// not zero, and reporting it as zero would say this writer never errs.
  double? get averageFindings {
    final counted = records.map((r) => r.findings).whereType<int>().toList();
    if (counted.isEmpty) return null;
    return counted.reduce((a, b) => a + b) / counted.length;
  }
}
