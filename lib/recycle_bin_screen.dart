import 'package:flutter/material.dart';
import 'models.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

/// How long a deleted project stays listed here.
const Duration _binWindow = Duration(days: 30);

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<Project> _deletedProjects = [];
  bool _isLoading = true;
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _loadDeletedItems();
  }

  Future<void> _loadDeletedItems() async {
    setState(() => _isLoading = true);
    final allProjects = await _storage.loadProjects();
    // Deleted records are kept for ever — dropping a tombstone is how a
    // deletion gets undone by a device that was away. The bin shows the recent
    // ones; the rest stop being listed, which is all "the bin empties itself"
    // ever meant.
    final cutoff = DateTime.now().subtract(_binWindow);
    final deleted = allProjects
        .where((p) =>
            p.isDeleted && (p.deletedAt == null || p.deletedAt!.isAfter(cutoff)))
        .toList();
    deleted.sort((a, b) => (b.deletedAt ?? b.lastUpdated)
        .compareTo(a.deletedAt ?? a.lastUpdated));

    if (mounted) {
      setState(() {
        _deletedProjects = deleted;
        _isLoading = false;
      });
    }
  }

  Future<void> _restoreProject(Project project) async {
    final allProjects = await _storage.loadProjects();
    final index = allProjects.indexWhere((p) => p.id == project.id);
    if (index != -1) {
      allProjects[index] = project.copyWith(isDeleted: false);
      await _storage.saveProjects(allProjects);
      await _loadDeletedItems();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("הפרויקט '${project.name}' שוחזר בהצלחה")),
        );
      }
    }
  }

  Future<void> _deletePermanently(Project project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מחיקה לצמיתות"),
        content:
            const Text("האם אתה בטוח? לא ניתן יהיה לשחזר את הפרויקט לאחר מכן."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("ביטול")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: SoferTokens.of(context).danger),
            child: const Text("מחק"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final allProjects = await _storage.loadProjects();
      final index = allProjects.indexWhere((p) => p.id == project.id);
      if (index != -1) {
        // Backdating lastUpdated to force a purge used to lose the merge
        // against any device still holding a newer copy, which brought the
        // project back to life. copyWith stamps the deletion as the most
        // recent change instead, so it wins and propagates.
        allProjects[index] = project.copyWith(isDeleted: true);
        await _storage.saveProjects(allProjects);

        // Sessions belonging to the project were previously left behind,
        // referencing a project that no longer exists.
        final history = await _storage.loadHistory();
        final updatedHistory = history
            .map((s) => s.projectId == project.id && !s.isDeleted
                ? s.copyWith(isDeleted: true)
                : s)
            .toList();
        await _storage.saveHistory(updatedHistory);

          await _loadDeletedItems();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("סל מחזור")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deletedProjects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline, size: 64, color: SoferTokens.of(context).inkMuted),
                      SizedBox(height: 16),
                      Text("סל המחזור ריק",
                          style: TextStyle(fontSize: 18, color: SoferTokens.of(context).inkMuted)),
                      Text("פרויקטים שנמחקו ב-30 הימים האחרונים יופיעו כאן",
                          style: TextStyle(fontSize: 12, color: SoferTokens.of(context).inkMuted)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _deletedProjects.length,
                  itemBuilder: (context, index) {
                    final p = _deletedProjects[index];
                    final since = DateTime.now()
                        .difference(p.deletedAt ?? p.lastUpdated)
                        .inDays;
                    final daysLeft = _binWindow.inDays - since;

                    final t = SoferTokens.of(context);

                    // The countdown is the point of this screen, so in the
                    // ruled themes it is the figure and the name is the label.
                    if (t.isRules) {
                      return Container(
                        decoration: BoxDecoration(
                            border:
                                Border(bottom: BorderSide(color: t.rule))),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: TextStyle(
                                          fontFamily: t.numeralFamily,
                                          fontSize: 17,
                                          color: t.ink)),
                                  const SizedBox(height: 2),
                                  Text(
                                    daysLeft <= 0
                                        ? "יוסתר מהסל בקרוב"
                                        : "יוסתר מהסל בעוד $daysLeft ימים",
                                    style: TextStyle(
                                        fontFamily: t.labelFamily,
                                        fontSize: 12,
                                        color: daysLeft <= 3
                                            ? t.danger
                                            : t.inkMuted),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                                onPressed: () => _restoreProject(p),
                                child: const Text("שחזר")),
                            TextButton(
                              onPressed: () => _deletePermanently(p),
                              style: TextButton.styleFrom(
                                  foregroundColor: t.danger),
                              child: const Text("מחק"),
                            ),
                          ],
                        ),
                      );
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading:
                            Icon(Icons.history, color: SoferTokens.of(context).caution),
                        title: Text(p.name),
                        subtitle: Text("יוסתר מהסל בעוד $daysLeft ימים"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.restore_from_trash,
                                  color: SoferTokens.of(context).positive),
                              tooltip: "שחזר",
                              onPressed: () => _restoreProject(p),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_forever,
                                  color: SoferTokens.of(context).danger),
                              tooltip: "מחק לצמיתות",
                              onPressed: () => _deletePermanently(p),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
