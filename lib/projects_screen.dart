import 'package:flutter/material.dart';
import 'logic/completion_estimator.dart';
import 'logic/hebrew_work_calendar.dart';
import 'logic/id_generator.dart';
import 'models.dart';
import 'package:url_launcher/url_launcher.dart';
import 'storage_service.dart';
import 'expenses_screen.dart';
import 'recycle_bin_screen.dart';
import 'hebrew_utils.dart';

class ProjectsScreen extends StatefulWidget {
  final List<Project> projects;
  final Function(Project) onProjectAdded;
  final Function(Project) onProjectUpdated;
  final Function(Project) onProjectDeleted;
  final VoidCallback onResetAllData;

  const ProjectsScreen({
    super.key,
    required this.projects,
    required this.onProjectAdded,
    required this.onProjectUpdated,
    required this.onProjectDeleted,
    required this.onResetAllData,
  });

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool _useGregorianDates = false;
  final StorageService _storage = StorageService();

  /// Loaded so each card can carry its own delivery date — the question a
  /// sofer opens this screen to answer.
  List<WorkSession> _history = const [];
  WorkCalendarRules _rules = WorkCalendarRules.standard;

  @override
  void initState() {
    super.initState();
    _storage.getUseGregorianDates().then((v) {
      if (mounted) setState(() => _useGregorianDates = v);
    });
    _storage.getWorkCalendarRules().then((v) {
      if (mounted) setState(() => _rules = v);
    });
    _storage.loadHistory().then((v) {
      if (mounted) setState(() => _history = v);
    });
  }

  Future<void> _openProjectDialog({Project? project}) async {
    // Needed to warn before changing page geometry that past work depends on.
    var hasRecordedWork = false;
    if (project != null) {
      final history = await _storage.loadHistory();
      hasRecordedWork = history
          .any((s) => s.projectId == project.id && !s.isDeleted);
    }
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => ProjectDialog(
        existingProject: project,
        useGregorianDates: _useGregorianDates,
        hasRecordedWork: hasRecordedWork,
        onSave: (p) {
          if (mounted) {
            setState(() {
              if (project == null) {
                widget.onProjectAdded(p);
              } else {
                widget.onProjectUpdated(p);
              }
            });
          }
        },
      ),
    );
  }

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
            onPressed: () async {
              final updatedProject = p.copyWith(isDeleted: true);
              widget.onProjectUpdated(updatedProject);

              final storage = StorageService();
              final allProjects = await storage.loadProjects();
              final index = allProjects.indexWhere((e) => e.id == p.id);
              if (index != -1) {
                allProjects[index] = updatedProject;
                await storage.saveProjects(allProjects);
              }

              widget.onProjectDeleted(p);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              Navigator.pop(context);
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
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('שם האפליקציה: סופר ומונה'),
              const Text('גרסה: 0.3.0'),
              const SizedBox(height: 12),
              const Text('אתר האפליקציה:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              InkWell(
                child: const Text(
                  'https://soferstam-app.github.io/sofer-vmone/',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
                onTap: () => launchUrl(
                    Uri.parse('https://soferstam-app.github.io/sofer-vmone/')),
              ),
              const SizedBox(height: 8),
              const Text('גיטהאב:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              InkWell(
                child: const Text(
                  'https://github.com/soferstam-app/sofer-vmone',
                  style: TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
                onTap: () => launchUrl(
                    Uri.parse('https://github.com/soferstam-app/sofer-vmone')),
              ),
              const SizedBox(height: 16),
              const Text(
                'עלויות בניית האפליקציה והתחזוקה שלה הן רבות. למי שמעוניין לתמוך בפיתוח האפליקציה ובפרויקטים עתידיים – אפשר לתרום דרך הקישור הבא. תודה!',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              InkWell(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.coffee, size: 20, color: Colors.brown.shade700),
                    const SizedBox(width: 6),
                    const Text(
                      'https://buymeacoffee.com/soferstam',
                      style: TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
                onTap: () =>
                    launchUrl(Uri.parse('https://buymeacoffee.com/soferstam')),
              ),
            ],
          ),
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

  Future<void> _confirmResetAll() async {
    final TextEditingController confirmCtrl = TextEditingController();
    await showDialog(
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
                Navigator.pop(ctx);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("אפס הכל"),
          ),
        ],
      ),
    );
    confirmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ניהול פרויקטים"),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: "הוצאות",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ExpensesScreen(projects: widget.projects)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_delete),
            tooltip: "סל מחזור",
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecycleBinScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
            tooltip: "אודות",
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.projects.isEmpty
                ? const Center(
                    child: Text("אין פרויקטים. לחץ על + כדי להוסיף."))
                : ListView.builder(
                    itemCount: widget.projects.length + 1,
                    itemBuilder: (context, index) {
                      if (index == widget.projects.length) {
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
                          if (mounted) {
                            setState(() {
                              widget.onProjectDeleted(p);
                            });
                          }
                        },
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: ListTile(
                            isThreeLine: _estimateLine(p) != null,
                            title: Text(
                              p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_getProjectSubtitle(p)),
                                if (_estimateLine(p) case final line?)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        Icon(Icons.event_available,
                                            size: 14,
                                            color: Colors.deepPurple.shade300),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            line,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.deepPurple.shade400,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openProjectDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _getProjectSubtitle(Project p) {
    if (p.type == ProjectType.sefer) return "ספר תורה (${p.totalPages} עמודים)";
    if (p.type == ProjectType.tefillin) {
      return p.targetUnits == null
          ? "תפילין (ראש + יד)"
          : "תפילין – ${p.targetUnits} סטים";
    }
    return p.targetUnits == null
        ? "מזוזה (22 שורות)"
        : "מזוזות – ${p.targetUnits} בהזמנה";
  }

  /// Progress and delivery date in one line, or null when the project has
  /// nothing to estimate from — an unstated size or no measured pace.
  String? _estimateLine(Project p) {
    final e = CompletionEstimator.estimate(
      project: p,
      history: _history,
      rules: _rules,
    );
    if (e == null) return null;
    return "${(e.progress * 100).toStringAsFixed(0)}% · "
        "צפי סיום ${formatDisplayDate(e.plan.completionDate, _useGregorianDates)}";
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

class ProjectDialog extends StatefulWidget {
  final Project? existingProject;
  final bool useGregorianDates;

  /// Whether the project already has work recorded against it. Changing page
  /// geometry then affects how past sessions are counted, so it is confirmed.
  final bool hasRecordedWork;
  final Function(Project) onSave;

  const ProjectDialog({
    super.key,
    this.existingProject,
    this.useGregorianDates = false,
    this.hasRecordedWork = false,
    required this.onSave,
  });

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

  /// Order size for mezuzot and tefillin — a sefer states its size in pages.
  late TextEditingController _unitsCtrl;
  late TextEditingController _clientEmailCtrl;

  ProjectType _type = ProjectType.sefer;
  DateTime? _targetCompletionDate;
  bool _dailyGoalInLines = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProject;
    _type = p?.type ?? ProjectType.sefer;
    _targetCompletionDate = p?.targetCompletionDate;
    _dailyGoalInLines = p?.dailyGoalInLines ?? false;

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
    _unitsCtrl = TextEditingController(text: p?.targetUnits?.toString() ?? "");
    _clientEmailCtrl = TextEditingController(text: p?.clientEmail ?? "");
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
    _unitsCtrl.dispose();
    _clientEmailCtrl.dispose();
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
                initialValue: _type,
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
                    : null,
              ),
              const SizedBox(height: 10),
              _buildDynamicFields(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "אימייל הלקוח (לשליחת עדכון)",
                  hintText: "client@example.com",
                ),
              ),
              if (_type == ProjectType.sefer) ...[
                const SizedBox(height: 10),
                ListTile(
                  title: Text(
                    _targetCompletionDate == null
                        ? "תאריך יעד לסיום (אופציונלי)"
                        : "תאריך יעד: ${formatDisplayDate(_targetCompletionDate!, widget.useGregorianDates)}",
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_targetCompletionDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () =>
                              setState(() => _targetCompletionDate = null),
                        ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _targetCompletionDate ??
                                DateTime.now().add(const Duration(days: 365)),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime(DateTime.now().year + 10, 12, 31),
                          );
                          if (d != null) {
                            setState(() => _targetCompletionDate = d);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
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
        if (_type == ProjectType.sefer) ...[
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _pagesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'סה"כ עמודים'),
                  validator: (v) => _validatePositiveInt(v, 'סה"כ עמודים'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _linesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'שורות לעמוד'),
                  validator: (v) => _validatePositiveInt(v, 'שורות לעמוד'),
                ),
              ),
            ],
          ),
        ] else
          // The size of the order. Without it there is nothing to measure
          // progress against, and no completion date can be worked out — hence
          // the hint rather than a silent empty field.
          TextFormField(
            controller: _unitsCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _type == ProjectType.mezuza
                  ? 'כמה מזוזות בהזמנה'
                  : 'כמה סטים בהזמנה',
              helperText: 'משמש לחישוב ההתקדמות וצפי הסיום',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = int.tryParse(v.trim());
              return (n == null || n <= 0) ? 'יש להזין מספר חיובי' : null;
            },
          ),
        const SizedBox(height: 10),
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
                validator: (v) => _validateMoney(v, "מחיר"),
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
                validator: (v) => _validateMoney(v, "הוצאות", allowEmpty: true),
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
                      : (_dailyGoalInLines
                          ? "יעד יומי (שורות)"
                          : "יעד יומי (עמודים)"),
                ),
                validator: (v) {
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
        if (_type == ProjectType.sefer) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Text("יעד יומי בשורות (במקום עמודים):"),
              const SizedBox(width: 8),
              Switch(
                value: _dailyGoalInLines,
                onChanged: (v) => setState(() => _dailyGoalInLines = v),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Rejects text that would silently become 0.
  ///
  /// The form used to fall back to `tryParse(...) ?? 0`, so a typo in the
  /// price produced a project that reported zero earnings forever, with
  /// nothing on screen explaining why.
  String? _validateMoney(String? value, String label,
      {bool allowEmpty = false}) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return allowEmpty ? null : "יש להזין $label";
    }
    final parsed = double.tryParse(text.replaceAll(',', '.'));
    if (parsed == null) return "$label חייב להיות מספר";
    if (parsed < 0) return "$label לא יכול להיות שלילי";
    return null;
  }

  String? _validatePositiveInt(String? value, String label) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return "יש להזין $label";
    final parsed = int.tryParse(text);
    if (parsed == null) return "$label חייב להיות מספר שלם";
    // Zero used to be accepted here and then broke line validation and the
    // daily goal downstream.
    if (parsed <= 0) return "$label חייב להיות גדול מאפס";
    return null;
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

  /// Page geometry feeds both production and profit, so changing it on a
  /// project with recorded work shifts how that work is counted. Sessions
  /// recorded from now on carry their own snapshot; older ones do not.
  Future<bool> _confirmGeometryChange() async {
    final existing = widget.existingProject;
    if (existing == null || !widget.hasRecordedWork) return true;
    if (existing.type != ProjectType.sefer) return true;

    final newLines = int.tryParse(_linesCtrl.text);
    final newPages = int.tryParse(_pagesCtrl.text);
    final linesChanged =
        newLines != null && newLines != (existing.linesPerPage ?? newLines);
    final pagesChanged =
        newPages != null && newPages != (existing.totalPages ?? newPages);
    if (!linesChanged && !pagesChanged) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("שינוי הגדרות הספר"),
        content: Text(
          linesChanged
              ? "שינית את מספר השורות לעמוד מ-${existing.linesPerPage} ל-$newLines.\n\n"
                  "רשומות שנכתבו מכאן ואילך יחושבו לפי הערך החדש. רשומות ישנות שנשמרו לפני עדכון זה עשויות להיות מחושבות מחדש – מה שישנה את ההספק והרווח המוצגים עבורן.\n\n"
                  "להמשיך?"
              : "שינית את מספר העמודים בספר מ-${existing.totalPages} ל-$newPages.\n\n"
                  "שינוי זה משפיע על אחוזי ההתקדמות ועל צפי הסיום.\n\nלהמשיך?",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("ביטול")),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("המשך")),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      if (!await _confirmGeometryChange()) return;
      if (!mounted) return;
      final email = _clientEmailCtrl.text.trim();
      final p = Project(
        id: widget.existingProject?.id ?? IdGenerator.generate(),
        name: _nameCtrl.text,
        type: _type,
        price: double.tryParse(_priceCtrl.text) ?? 0,
        expenses: double.tryParse(_expensesCtrl.text) ?? 0,
        targetDaily: int.tryParse(_dailyCtrl.text) ?? 0,
        targetMonthly: int.tryParse(_monthlyCtrl.text) ?? 0,
        dailyGoalInLines:
            _type == ProjectType.sefer ? _dailyGoalInLines : false,
        totalPages:
            _type == ProjectType.sefer ? int.tryParse(_pagesCtrl.text) : null,
        linesPerPage:
            _type == ProjectType.sefer ? int.tryParse(_linesCtrl.text) : null,
        targetUnits:
            _type == ProjectType.sefer ? null : int.tryParse(_unitsCtrl.text),
        clientEmail: email.isEmpty ? null : email,
        targetCompletionDate: _targetCompletionDate,
      );
      widget.onSave(p);
      Navigator.pop(context);
    }
  }
}
