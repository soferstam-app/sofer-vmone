import '../models.dart';

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
/// The rule is last-write-wins per record, keyed on id: a record present on
/// only one side is kept, and one present on both is resolved by lastUpdated.
/// **Nothing is ever dropped just because it is absent from the other side** —
/// which is what makes importing a merge rather than a replacement.
class MergeService {
  const MergeService._();

  /// Merges [incoming] into [local] by id.
  static ({List<T> merged, MergeStats stats}) mergeById<T>(
    List<T> local,
    List<T> incoming,
    String Function(T) getId,
    DateTime Function(T) getLastUpdated,
  ) {
    final map = <String, T>{};
    for (final item in local) {
      map[getId(item)] = item;
    }

    var added = 0;
    var updated = 0;
    var unchanged = 0;

    for (final item in incoming) {
      final id = getId(item);
      final existing = map[id];
      if (existing == null) {
        map[id] = item;
        added++;
      } else if (getLastUpdated(item).isAfter(getLastUpdated(existing))) {
        map[id] = item;
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

  /// Drops records deleted more than [retention] ago.
  ///
  /// Soft-deleted records must survive a while so the deletion can propagate to
  /// other devices; past that window they are only dead weight.
  static List<T> purgeOldDeleted<T>(
    List<T> items,
    bool Function(T) isDeleted,
    DateTime Function(T) getLastUpdated, {
    Duration retention = const Duration(days: 30),
  }) {
    final cutoff = DateTime.now().subtract(retention);
    return items.where((item) {
      if (isDeleted(item)) return getLastUpdated(item).isAfter(cutoff);
      return true;
    }).toList();
  }

  /// Merges a complete backup into the local data.
  static MergeOutcome mergeBackup({
    required List<Project> localProjects,
    required List<WorkSession> localHistory,
    required List<Expense> localExpenses,
    required List<Project> incomingProjects,
    required List<WorkSession> incomingHistory,
    required List<Expense> incomingExpenses,
  }) {
    final p = mergeById<Project>(
        localProjects, incomingProjects, (e) => e.id, (e) => e.lastUpdated);
    final h = mergeById<WorkSession>(
        localHistory, incomingHistory, (e) => e.id, (e) => e.lastUpdated);
    final x = mergeById<Expense>(
        localExpenses, incomingExpenses, (e) => e.id, (e) => e.lastUpdated);

    return MergeOutcome(
      projects:
          purgeOldDeleted(p.merged, (e) => e.isDeleted, (e) => e.lastUpdated),
      history:
          purgeOldDeleted(h.merged, (e) => e.isDeleted, (e) => e.lastUpdated),
      expenses:
          purgeOldDeleted(x.merged, (e) => e.isDeleted, (e) => e.lastUpdated),
      projectStats: p.stats,
      historyStats: h.stats,
      expenseStats: x.stats,
    );
  }
}
