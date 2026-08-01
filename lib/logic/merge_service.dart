import '../models.dart';
import 'mergeable.dart';

/// What a merge did, so the user can be told rather than left guessing.
class MergeStats {
  final int added;
  final int updated;
  final int unchanged;

  const MergeStats({
    this.added = 0,
    this.updated = 0,
    this.unchanged = 0,
  });

  int get total => added + updated + unchanged;
  bool get changedAnything => added > 0 || updated > 0;
}

/// Result of merging a whole backup into the local data.
class MergeOutcome {
  final List<Project> projects;
  final List<WorkSession> history;
  final List<Expense> expenses;
  final MergeStats projectStats;
  final MergeStats historyStats;
  final MergeStats expenseStats;

  const MergeOutcome({
    required this.projects,
    required this.history,
    required this.expenses,
    required this.projectStats,
    required this.historyStats,
    required this.expenseStats,
  });

  bool get changedAnything =>
      projectStats.changedAnything ||
      historyStats.changedAnything ||
      expenseStats.changedAnything;
}

/// Combines two sets of records without losing either.
///
/// Extracted from SyncService so importing a backup file uses exactly the same
/// rules that Drive sync used — the logic is the part that matters, not where
/// the second copy came from.
///
/// A record present on only one side is kept. A record present on both is
/// resolved by [Mergeable.lastUpdated] for its payload, and by the later of
/// each tombstone register for whether it is deleted. **Nothing is ever dropped
/// just because it is absent from the other side** — which is what makes
/// importing a merge rather than a replacement.
class MergeService {
  const MergeService._();

  /// Merges [incoming] into [local] by id.
  static ({List<T> merged, MergeStats stats}) mergeById<T extends Mergeable<T>>(
    List<T> local,
    List<T> incoming,
  ) {
    final map = <String, T>{for (final item in local) item.id: item};

    var added = 0;
    var updated = 0;
    var unchanged = 0;

    for (final item in incoming) {
      final existing = map[item.id];
      if (existing == null) {
        map[item.id] = item;
        added++;
        continue;
      }

      // The payload comes from whichever side wrote last. The two tombstone
      // registers do not: each takes the later of the two sides on its own.
      //
      // That separation is the point. A device that edited a stale copy after
      // another device deleted the record used to win outright and bring the
      // record back from the dead — an edit is newer than a deletion, and
      // nothing distinguished the two. Now it wins the payload and the deletion
      // still stands, and only a restore made after the deletion can undo it.
      final deletedAt = laterOf(existing.deletedAt, item.deletedAt);
      final restoredAt = laterOf(existing.restoredAt, item.restoredAt);
      final tombstoneMoved =
          deletedAt != existing.deletedAt || restoredAt != existing.restoredAt;

      final incomingIsNewer = item.lastUpdated.isAfter(existing.lastUpdated);
      final winner = incomingIsNewer ? item : existing;

      map[item.id] =
          winner.withTombstone(deletedAt: deletedAt, restoredAt: restoredAt);

      if (incomingIsNewer || tombstoneMoved) {
        updated++;
      } else {
        unchanged++;
      }
    }

    return (
      merged: map.values.toList(),
      stats: MergeStats(added: added, updated: updated, unchanged: unchanged),
    );
  }

  /// Merges a complete backup into the local data.
  ///
  /// Deleted records are kept, for ever. Dropping a tombstone after a while
  /// looks tidy and is the second way a deleted record comes back: a device
  /// left in a drawer for longer than the retention window still holds its live
  /// copy, and once the tombstone is gone there is nothing left to say the
  /// record was ever deleted. A tombstone is a few hundred bytes and the only
  /// evidence that a deletion happened.
  static MergeOutcome mergeBackup({
    required List<Project> localProjects,
    required List<WorkSession> localHistory,
    required List<Expense> localExpenses,
    required List<Project> incomingProjects,
    required List<WorkSession> incomingHistory,
    required List<Expense> incomingExpenses,
  }) {
    final p = mergeById<Project>(localProjects, incomingProjects);
    final h = mergeById<WorkSession>(localHistory, incomingHistory);
    final x = mergeById<Expense>(localExpenses, incomingExpenses);

    return MergeOutcome(
      projects: p.merged,
      history: h.merged,
      expenses: x.merged,
      projectStats: p.stats,
      historyStats: h.stats,
      expenseStats: x.stats,
    );
  }
}
