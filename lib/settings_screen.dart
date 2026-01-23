import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'storage_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  final List<Project> projects;
  final Function(Project) onProjectAdded;
  final Function(Project) onProjectUpdated;
  final Function(Project) onProjectDeleted;
  final VoidCallback onResetAllData;

  const SettingsScreen({
    super.key,
    required this.projects,
    required this.onProjectAdded,
    required this.onProjectUpdated,
    required this.onProjectDeleted,
    required this.onResetAllData,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // פתיחת דיאלוג ליצירה או עריכה
  void _openProjectDialog({Project? project}) {
    showDialog(
      context: context,
      builder: (context) => ProjectDialog(
        existingProject: project,
        onSave: (p) {
          // שימוש ב-setState כדי לרענן את המסך מיד לאחר השמירה
          setState(() {
            if (project == null) {
              widget.onProjectAdded(p);
            } else {
              widget.onProjectUpdated(p);
            }
          });
        },
      ),
    );
  }

  // פונקציית מחיקה עם ריענון מיידי
  void _deleteProject(Project p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מחיקת פרויקט"),
        content: const Text("האם אתה בטוח שברצונך למחוק את הפרויקט?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ביטול"),
          ),
          ElevatedButton(
            onPressed: () {
              // שימוש ב-setState כדי להעלים את הפרויקט מהרשימה מיד
              setState(() {
                widget.onProjectDeleted(p);
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("מחק"),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("אודות"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('שם האפליקציה: סת"ם סופר'),
            const Text('גרסה: 0.2.0'),
            const SizedBox(height: 10),
            const Text('גיטהאב:'),
            InkWell(
              child: const Text(
                'https://github.com/soferstam-app/stam-sofer',
                style: TextStyle(
                    color: Colors.blue, decoration: TextDecoration.underline),
              ),
              onTap: () => launchUrl(
                  Uri.parse('https://github.com/soferstam-app/stam-sofer')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("סגור"),
          ),
        ],
      ),
    );
  }

  // דיאלוג איפוס כללי מאובטח
  void _confirmResetAll() {
    final TextEditingController confirmCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("איפוס כל הנתונים"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "פעולה זו תמחק את כל הפרויקטים וההיסטוריה לצמיתות!\n"
              "כדי לאשר, הקלד את המילה 'מחיקה' למטה:",
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              decoration: const InputDecoration(hintText: "מחיקה"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("ביטול"),
          ),
          ElevatedButton(
            onPressed: () {
              if (confirmCtrl.text == "מחיקה") {
                widget.onResetAllData();
                Navigator.pop(ctx); // סגירת הדיאלוג
                Navigator.pop(context); // חזרה למסך הבית
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("אפס הכל"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ניהול פרויקטים"),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
            tooltip: "אודות",
          ),
        ],
      ),
      body: widget.projects.isEmpty
          ? const Center(child: Text("אין פרויקטים. לחץ על + כדי להוסיף."))
          : ListView.builder(
              // מוסיפים 1 עבור כפתור האיפוס בסוף
              itemCount: widget.projects.length + 1,
              itemBuilder: (context, index) {
                if (index == widget.projects.length) {
                  // כפתור איפוס בתחתית הרשימה
                  return Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: OutlinedButton.icon(
                      onPressed: _confirmResetAll,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text("איפוס כל הנתונים (זהירות!)"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  );
                }

                final p = widget.projects[index];
                return Dismissible(
                  key: Key(p.id),
                  direction: DismissDirection.startToEnd,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("מחיקת פרויקט"),
                        content: const Text(
                          "האם אתה בטוח שברצונך למחוק את הפרויקט?",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text("ביטול"),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text("מחק"),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (direction) {
                    setState(() {
                      widget.onProjectDeleted(p);
                    });
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: ListTile(
                      title: Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(_getProjectSubtitle(p)),
                      leading: Icon(_getIconForType(p.type)),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _openProjectDialog(project: p),
                      ),
                      onLongPress: () => _deleteProject(p),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openProjectDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _getProjectSubtitle(Project p) {
    if (p.type == ProjectType.sefer) return "ספר תורה (${p.totalPages} עמודים)";
    if (p.type == ProjectType.tefillin) return "תפילין (ראש + יד)";
    return "מזוזה (22 שורות)";
  }

  IconData _getIconForType(ProjectType type) {
    switch (type) {
      case ProjectType.sefer:
        return Icons.book;
      case ProjectType.tefillin:
        return Icons.crop_square;
      case ProjectType.mezuza:
        return Icons.article;
    }
  }
}

// --- טופס עריכה/יצירה (חלון קופץ) ---
class ProjectDialog extends StatefulWidget {
  final Project? existingProject;
  final Function(Project) onSave;

  const ProjectDialog({super.key, this.existingProject, required this.onSave});

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _expensesCtrl;
  late TextEditingController _dailyCtrl;
  late TextEditingController _monthlyCtrl;
  late TextEditingController _pagesCtrl;
  late TextEditingController _linesCtrl;

  ProjectType _type = ProjectType.sefer;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProject;
    _type = p?.type ?? ProjectType.sefer;

    _nameCtrl = TextEditingController(text: p?.name ?? "");
    _priceCtrl = TextEditingController(text: p?.price.toString() ?? "");
    _expensesCtrl = TextEditingController(text: p?.expenses.toString() ?? "");
    _dailyCtrl = TextEditingController(text: p?.targetDaily.toString() ?? "");
    _monthlyCtrl = TextEditingController(
      text: p?.targetMonthly.toString() ?? "",
    );
    _pagesCtrl = TextEditingController(
      text: p?.totalPages?.toString() ?? "245",
    );
    _linesCtrl = TextEditingController(
      text: p?.linesPerPage?.toString() ?? "42",
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _expensesCtrl.dispose();
    _dailyCtrl.dispose();
    _monthlyCtrl.dispose();
    _pagesCtrl.dispose();
    _linesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existingProject == null ? "פרויקט חדש" : "עריכת פרויקט",
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: "שם הפרויקט"),
                validator: (v) => v!.isEmpty ? "חובה להזין שם" : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<ProjectType>(
                value: _type,
                decoration: const InputDecoration(labelText: "סוג פרויקט"),
                items: const [
                  DropdownMenuItem(
                    value: ProjectType.sefer,
                    child: Text("ספר תורה"),
                  ),
                  DropdownMenuItem(
                    value: ProjectType.mezuza,
                    child: Text("מזוזה"),
                  ),
                  DropdownMenuItem(
                    value: ProjectType.tefillin,
                    child: Text("תפילין (סט שלם)"),
                  ),
                ],
                onChanged: widget.existingProject == null
                    ? (val) => setState(() => _type = val!)
                    : null, // לא ניתן לשנות סוג בעריכה
              ),
              const SizedBox(height: 10),
              _buildDynamicFields(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ביטול"),
        ),
        ElevatedButton(onPressed: _submit, child: const Text("שמור")),
      ],
    );
  }

  Widget _buildDynamicFields() {
    return Column(
      children: [
        // שדות ייחודיים לספר
        if (_type == ProjectType.sefer) ...[
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _pagesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'סה"כ עמודים'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _linesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'שורות לעמוד'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),

        // כותרת משתנה לפי הסוג
        Text(
          _getPriceLabel(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: "מחיר"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _expensesCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: "הוצאות"),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
        Text(
          _getTargetLabel(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _dailyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _type == ProjectType.tefillin
                      ? "פרשיות ליום (עד 8)"
                      : "יעד יומי",
                ),
                validator: (v) {
                  // ולידציה לתפילין - מקסימום 8 פרשיות
                  if (_type == ProjectType.tefillin &&
                      (int.tryParse(v ?? "0") ?? 0) > 8) {
                    return "מקסימום 8";
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _monthlyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "יעד חודשי (יחידות)",
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _getPriceLabel() {
    if (_type == ProjectType.sefer) return "כספים (לעמוד)";
    if (_type == ProjectType.tefillin) return "כספים (ליחידה: ראש+יד)";
    return "כספים (למזוזה)";
  }

  String _getTargetLabel() {
    if (_type == ProjectType.sefer) return "יעדים (עמודים)";
    if (_type == ProjectType.tefillin) return "יעדים";
    return "יעדים (מזוזות)";
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final p = Project(
        id: widget.existingProject?.id ?? DateTime.now().toString(),
        name: _nameCtrl.text,
        type: _type,
        price: double.tryParse(_priceCtrl.text) ?? 0,
        expenses: double.tryParse(_expensesCtrl.text) ?? 0,
        targetDaily: int.tryParse(_dailyCtrl.text) ?? 0,
        targetMonthly: int.tryParse(_monthlyCtrl.text) ?? 0,
        totalPages:
            _type == ProjectType.sefer ? int.tryParse(_pagesCtrl.text) : null,
        linesPerPage:
            _type == ProjectType.sefer ? int.tryParse(_linesCtrl.text) : null,
      );
      widget.onSave(p);
      Navigator.pop(context);
    }
  }
}
