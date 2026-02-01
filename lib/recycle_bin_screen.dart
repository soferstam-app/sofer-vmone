import 'package:flutter/material.dart';
import 'models.dart';
import 'storage_service.dart';
import 'sync_service.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

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
    final deleted = allProjects.where((p) => p.isDeleted).toList();
    deleted.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

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
      await SyncService.instance.syncData();
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("מחק"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final allProjects = await _storage.loadProjects();
      final index = allProjects.indexWhere((p) => p.id == project.id);
      if (index != -1) {
        final oldDate = DateTime.now().subtract(const Duration(days: 365));
        final forcedOldProject = Project(
          id: project.id,
          name: project.name,
          type: project.type,
          price: project.price,
          expenses: project.expenses,
          targetDaily: project.targetDaily,
          targetMonthly: project.targetMonthly,
          totalPages: project.totalPages,
          linesPerPage: project.linesPerPage,
          isDeleted: true,
          lastUpdated: oldDate,
        );

        allProjects[index] = forcedOldProject;
        await _storage.saveProjects(allProjects);
        await SyncService.instance.syncData();

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
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("סל המחזור ריק",
                          style: TextStyle(fontSize: 18, color: Colors.grey)),
                      Text("פרויקטים שנמחקו ב-30 הימים האחרונים יופיעו כאן",
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _deletedProjects.length,
                  itemBuilder: (context, index) {
                    final p = _deletedProjects[index];
                    final daysDeleted =
                        DateTime.now().difference(p.lastUpdated).inDays;
                    final daysLeft = 30 - daysDeleted;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading:
                            const Icon(Icons.history, color: Colors.orange),
                        title: Text(p.name),
                        subtitle: Text("יימחק לצמיתות בעוד $daysLeft ימים"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.restore_from_trash,
                                  color: Colors.green),
                              tooltip: "שחזר",
                              onPressed: () => _restoreProject(p),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever,
                                  color: Colors.red),
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
