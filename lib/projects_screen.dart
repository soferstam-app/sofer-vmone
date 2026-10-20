import 'dart:async';

import 'package:flutter/material.dart';
import 'logic/completion_estimator.dart';
import 'logic/money_input.dart';
import 'logic/hebrew_work_calendar.dart';
import 'logic/id_generator.dart';
import 'logic/megillah_format.dart';
import 'logic/tefillin_text.dart';
import 'models.dart';
import 'package:url_launcher/url_launcher.dart';
import 'storage_service.dart';
import 'expenses_screen.dart';
import 'recycle_bin_screen.dart';
import 'project_summary_screen.dart';
import 'hebrew_utils.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'widgets/confirm.dart';
import 'widgets/feedback.dart';
import 'logic/currency.dart';
import 'l10n/app_localizations.dart';
import 'version.dart';

class ProjectsScreen extends StatefulWidget {
  final List<Project> projects;
  final FutureOr<void> Function(List<Project>, List<WorkSession>)?
      onWorkCommitted;
  final FutureOr<void> Function(Project) onProjectAdded;
  final FutureOr<void> Function(Project) onProjectUpdated;
  final FutureOr<void> Function(Project) onProjectDeleted;

  /// Gives the owner a chance to block deletion while a session is active.
  final Future<bool> Function(Project)? onBeforeProjectDelete;
  final FutureOr<void> Function(List<WorkSession>)? onHistoryUpdated;
  final VoidCallback onResetAllData;

  const ProjectsScreen({
    super.key,
    required this.projects,
    this.onWorkCommitted,
    required this.onProjectAdded,
    required this.onProjectUpdated,
    required this.onProjectDeleted,
    this.onBeforeProjectDelete,
    this.onHistoryUpdated,
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

  Future<Project?> _openProjectDialog({Project? project}) async {
    // Needed to warn before changing page geometry that past work depends on.
    var hasRecordedWork = false;
    if (project != null) {
      final history = await _storage.loadHistory();
      hasRecordedWork =
          history.any((s) => s.projectId == project.id && !s.isDeleted);
    }
    if (!mounted) return null;

    Project? saved;
    await showDialog<void>(
      context: context,
      builder: (context) => ProjectDialog(
        existingProject: project,
        useGregorianDates: _useGregorianDates,
        hasRecordedWork: hasRecordedWork,
        onSave: (p) => saved = p,
      ),
    );
    if (saved != null) {
      try {
        if (project == null) {
          await widget.onProjectAdded(saved!);
        } else {
          await widget.onProjectUpdated(saved!);
        }
        if (mounted) setState(() {});
      } catch (error) {
        debugPrint('Project save callback failed: $error');
        if (mounted) {
          showAppError(
              context,
              context.l10n.pick(
                he: 'שמירת הפרויקט לא הושלמה',
                en: 'The project could not be saved',
              ));
          return null;
        }
      }
    }
    return saved;
  }

  /// Marks a project deleted, writes it, and tells the screens.
  ///
  /// The only way a project leaves this screen. Two paths used to reach here —
  /// a long press and a swipe — and only one of them saved anything.
  Future<void> _removeProject(Project p) async {
    final gone = p.copyWith(isDeleted: true);
    try {
      await widget.onProjectUpdated(gone);

      final all = await _storage.loadProjects();
      final at = all.indexWhere((e) => e.id == p.id);
      if (at != -1) {
        all[at] = gone;
        await _storage.saveProjects(all);
      }
      await widget.onProjectDeleted(p);
    } catch (error) {
      debugPrint('Project deletion failed: $error');
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
              he: 'מחיקת הפרויקט לא הושלמה',
              en: 'The project could not be deleted',
            ));
      }
    }
  }

  Future<bool> _confirmDeleteProject(Project p) async {
    final beforeDelete = widget.onBeforeProjectDelete;
    if (beforeDelete != null && !await beforeDelete(p)) return false;
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            Text(context.l10n.pick(he: "מחיקת פרויקט", en: "Delete project")),
        content: Text(context.l10n.pick(
          he: "האם אתה בטוח שברצונך למחוק את הפרויקט?",
          en: "Are you sure you want to delete this project?",
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: SoferTokens.of(ctx).danger),
            child: Text(context.l10n.pick(he: "מחק", en: "Delete")),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await _removeProject(p);
    return true;
  }

  void _deleteProject(Project p) {
    _confirmDeleteProject(p);
  }

  Future<void> _updateHistory(List<WorkSession> next) async {
    final snapshot = [...next];
    if (widget.onHistoryUpdated != null) {
      await widget.onHistoryUpdated!(snapshot);
    } else {
      await _storage.saveHistory(snapshot);
    }
    if (mounted) {
      setState(() => _history = snapshot.where((s) => !s.isDeleted).toList());
    }
  }

  Future<void> _openProjectCenter(Project project) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectSummaryScreen(
          projects: widget.projects,
          history: _history,
          onWorkCommitted: (nextProjects, nextHistory) async {
            await widget.onWorkCommitted?.call(nextProjects, nextHistory);
            if (mounted) {
              setState(() =>
                  _history = nextHistory.where((s) => !s.isDeleted).toList());
            }
          },
          initialProjectId: project.id,
          onEditProject: (current) => _openProjectDialog(project: current),
          onDeleteProject: _confirmDeleteProject,
          onProjectUpdated: (updated) async {
            await widget.onProjectUpdated(updated);
            final at = widget.projects.indexWhere((p) => p.id == updated.id);
            if (at != -1) widget.projects[at] = updated;
            if (mounted) setState(() {});
          },
          onHistoryUpdated: _updateHistory,
        ),
      ),
    );
    if (!mounted) return;
    final refreshed = await _storage.loadHistory();
    if (mounted) setState(() => _history = refreshed);
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.pick(he: "אודות", en: "About")),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.pick(
                he: 'שם האפליקציה: סופר ומונה',
                en: 'App: Sofer v’Mone',
              )),
              Text(context.l10n.pick(
                he: 'גרסה: $appVersion',
                en: 'Version: $appVersion',
              )),
              const SizedBox(height: 12),
              Text(context.l10n.pick(he: 'אתר האפליקציה:', en: 'Website:'),
                  style: TextStyle(fontWeight: FontWeight.bold)),
              InkWell(
                child: Text(
                  'https://soferstam-app.github.io/sofer-vmone/',
                  style: TextStyle(
                    color: SoferTokens.of(context).accent,
                    decoration: TextDecoration.underline,
                  ),
                ),
                onTap: () => launchUrl(
                    Uri.parse('https://soferstam-app.github.io/sofer-vmone/')),
              ),
              const SizedBox(height: 8),
              Text(context.l10n.pick(he: 'גיטהאב:', en: 'GitHub:'),
                  style: TextStyle(fontWeight: FontWeight.bold)),
              InkWell(
                child: Text(
                  'https://github.com/soferstam-app/sofer-vmone',
                  style: TextStyle(
                    color: SoferTokens.of(context).accent,
                    decoration: TextDecoration.underline,
                  ),
                ),
                onTap: () => launchUrl(
                    Uri.parse('https://github.com/soferstam-app/sofer-vmone')),
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n.pick(
                  he: 'עלויות בניית האפליקציה והתחזוקה שלה הן רבות. למי שמעוניין לתמוך בפיתוח האפליקציה ובפרויקטים עתידיים – אפשר לתרום דרך הקישור הבא. תודה!',
                  en: 'Building and maintaining the app takes substantial resources. If you would like to support its development and future projects, you can donate using the link below. Thank you!',
                ),
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              InkWell(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.coffee,
                        size: 20, color: SoferTokens.of(context).accent),
                    const SizedBox(width: 6),
                    Text(
                      'https://buymeacoffee.com/soferstam',
                      style: TextStyle(
                        color: SoferTokens.of(context).accent,
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
            child: Text(context.l10n.pick(he: "סגור", en: "Close")),
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
        title: Text(context.l10n.pick(
          he: "איפוס כל הנתונים",
          en: "Reset all data",
        )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.pick(
                he: "פעולה זו תמחק את כל הפרויקטים וההיסטוריה לצמיתות!\nכדי לאשר, הקלד את המילה 'מחיקה' למטה:",
                en: "This permanently deletes every project and all history!\nTo confirm, type DELETE below:",
              ),
              style: TextStyle(color: SoferTokens.of(ctx).danger),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              decoration: InputDecoration(
                hintText: context.l10n.pick(he: "מחיקה", en: "DELETE"),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              if (confirmCtrl.text ==
                  context.l10n.pick(he: "מחיקה", en: "DELETE")) {
                widget.onResetAllData();
                Navigator.pop(ctx);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: SoferTokens.of(ctx).danger),
            child: Text(context.l10n.pick(he: "אפס הכל", en: "Reset all")),
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
        title: Text(context.l10n.pick(
          he: "ניהול פרויקטים",
          en: "Projects",
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: context.l10n.pick(he: "הוצאות", en: "Expenses"),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ExpensesScreen(projects: widget.projects)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_delete),
            tooltip: context.l10n.pick(he: "סל מחזור", en: "Recycle bin"),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecycleBinScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showAboutDialog,
            tooltip: context.l10n.pick(he: "אודות", en: "About"),
          ),
          PopupMenuButton<String>(
            tooltip: context.l10n.pick(he: "פעולות נוספות", en: "More actions"),
            onSelected: (value) {
              if (value == 'reset') _confirmResetAll();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'reset',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_forever,
                      color: SoferTokens.of(context).danger),
                  title: Text(context.l10n.pick(
                    he: "איפוס כל הנתונים",
                    en: "Reset all data",
                  )),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.projects.isEmpty
                ? Center(
                    child: Text(context.l10n.pick(
                    he: "אין פרויקטים. לחץ על + כדי להוסיף.",
                    en: "No projects yet. Tap + to add one.",
                  )))
                : ListView.builder(
                    itemCount: widget.projects.length,
                    itemBuilder: (context, index) {
                      final p = widget.projects[index];
                      if (SoferTokens.of(context).isRules) {
                        return _ruledProjectRow(p);
                      }
                      return Dismissible(
                        key: Key(p.id),
                        direction: DismissDirection.startToEnd,
                        background: Container(
                          color: SoferTokens.of(context).danger,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          final beforeDelete = widget.onBeforeProjectDelete;
                          if (beforeDelete != null && !await beforeDelete(p)) {
                            return false;
                          }
                          if (!mounted) return false;
                          if (!context.mounted) return false;
                          return await showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(context.l10n.pick(
                                he: "מחיקת פרויקט",
                                en: "Delete project",
                              )),
                              content: Text(
                                context.l10n.pick(
                                  he: "האם אתה בטוח שברצונך למחוק את הפרויקט?",
                                  en: "Are you sure you want to delete this project?",
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(context.l10n.cancel),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: SoferTokens.of(ctx).danger,
                                  ),
                                  child: Text(context.l10n.pick(
                                    he: "מחק",
                                    en: "Delete",
                                  )),
                                ),
                              ],
                            ),
                          );
                        },
                        // The same act, through the same door. This used to call
                        // onProjectDeleted alone, which removes the project from
                        // the list in memory and nothing else: no tombstone, no
                        // save. It looked deleted until the app was next opened,
                        // and then it was back. Long-press has always written the
                        // tombstone; a swipe is not a different kind of deletion.
                        onDismissed: (direction) => _removeProject(p),
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
                                            color:
                                                SoferTokens.of(context).accent),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            line,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: SoferTokens.of(context)
                                                  .accent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            leading: Icon(_getIconForType(p.type)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openProjectCenter(p),
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

  /// A commission as an entry in a ledger rather than as a card.
  ///
  /// No leading icon and no trailing edit button: the name is set in the serif
  /// and carries the tap, the size and the estimate sit under it as one quiet
  /// line each, and a hairline does the work a card outline was doing. The
  /// progress is a segment against a rule, not a filled pill.
  Widget _ruledProjectRow(Project p) {
    final t = SoferTokens.of(context);
    final estimate = CompletionEstimator.estimate(
      project: p,
      history: _history,
      rules: _rules,
    );
    final shownProgress = estimate == null
        ? 0.0
        : MegillahFormat.displayedProgress(p, estimate.progress);

    return InkWell(
      onTap: () => _openProjectCenter(p),
      onLongPress: () => _deleteProject(p),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 19,
                        color: t.ink),
                  ),
                ),
                if (estimate != null)
                  Text(
                    "${(shownProgress * 100).toStringAsFixed(0)}%",
                    style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 19,
                        color: t.accent),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _getProjectSubtitle(p),
              style: TextStyle(
                  fontFamily: t.labelFamily, fontSize: 12, color: t.inkMuted),
            ),
            if (estimate != null) ...[
              const SizedBox(height: 9),
              SoferProgress(shownProgress),
              const SizedBox(height: 6),
              Text(
                context.l10n.pick(
                  he: "צפי סיום ${formatDisplayDate(estimate.plan.completionDate, _useGregorianDates)} · ${estimate.remainingUnits.toStringAsFixed(0)} נותרו",
                  en: "Estimated completion ${formatDisplayDate(estimate.plan.completionDate, _useGregorianDates, english: true)} · ${estimate.remainingUnits.toStringAsFixed(0)} remaining",
                ),
                style: TextStyle(
                    fontFamily: t.labelFamily, fontSize: 12, color: t.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getProjectSubtitle(Project p) {
    if (p.type == ProjectType.sefer) {
      return context.l10n.pick(
        he: "ספר תורה (${p.totalPages} עמודים)",
        en: "Sefer Torah (${p.totalPages} pages)",
      );
    }
    if (p.type == ProjectType.tefillin) {
      return p.targetUnits == null
          ? context.l10n.pick(
              he: "תפילין (כתיבה פתוחה)",
              en: "Tefillin (open-ended writing)",
            )
          : context.l10n.pick(
              he: "תפילין – ${p.targetUnits} זוגות",
              en: "Tefillin — ${p.targetUnits} sets",
            );
    }
    if (p.type == ProjectType.megillah) {
      final format = MegillahFormat.normalize(p.megillahFormat);
      return context.l10n.pick(
        he: "מגילה (${MegillahFormat.displayLines(format)} שורות · ${p.totalPages} עמודים)",
        en: "Megillah (${MegillahFormat.displayLines(format)} lines · ${p.totalPages} pages)",
      );
    }
    return p.targetUnits == null
        ? context.l10n.pick(
            he: "מזוזה (22 שורות)",
            en: "Mezuzah (22 lines)",
          )
        : context.l10n.pick(
            he: "מזוזות – ${p.targetUnits} בהזמנה",
            en: "Mezuzot — ${p.targetUnits} ordered",
          );
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
    return context.l10n.pick(
      he: "${(MegillahFormat.displayedProgress(p, e.progress) * 100).toStringAsFixed(0)}% · צפי סיום ${formatDisplayDate(e.plan.completionDate, _useGregorianDates)}",
      en: "${(MegillahFormat.displayedProgress(p, e.progress) * 100).toStringAsFixed(0)}% · estimated completion ${formatDisplayDate(e.plan.completionDate, _useGregorianDates, english: true)}",
    );
  }

  IconData _getIconForType(ProjectType type) {
    switch (type) {
      case ProjectType.sefer:
        return Icons.book;
      case ProjectType.tefillin:
        return Icons.crop_square;
      case ProjectType.mezuza:
        return Icons.article;
      case ProjectType.megillah:
        return Icons.auto_stories;
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
  String _megillahFormat = MegillahFormat.lines11;
  bool _tefillinWords = false;
  StamScript _tefillinScript = StamScript.beitYosef;

  /// What a new commission is priced in. An existing one keeps its own.
  Currency _currency = Currency.ils;

  @override
  void initState() {
    super.initState();
    final p = widget.existingProject;
    _type = p?.type ?? ProjectType.sefer;
    if (p != null) {
      _tefillinWords = TefillinPreferences.usesWords(p);
      _tefillinScript = TefillinPreferences.script(p);
    }
    StorageService().getCurrency().then((c) {
      if (mounted) setState(() => _currency = c);
    });
    _targetCompletionDate = p?.targetCompletionDate;
    _dailyGoalInLines = p?.dailyGoalInLines ?? false;
    _megillahFormat = MegillahFormat.normalize(p?.megillahFormat);

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
        widget.existingProject == null
            ? context.l10n.pick(he: "פרויקט חדש", en: "New project")
            : context.l10n.pick(he: "עריכת פרויקט", en: "Edit project"),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: context.l10n.pick(
                    he: "שם הפרויקט",
                    en: "Project name",
                  ),
                ),
                validator: (v) => v!.isEmpty
                    ? context.l10n.pick(
                        he: "חובה להזין שם",
                        en: "Enter a name",
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<ProjectType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: context.l10n.pick(
                    he: "סוג פרויקט",
                    en: "Project type",
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: ProjectType.sefer,
                    child: Text(context.l10n.pick(
                      he: "ספר תורה",
                      en: "Sefer Torah",
                    )),
                  ),
                  DropdownMenuItem(
                    value: ProjectType.mezuza,
                    child: Text(context.l10n.pick(
                      he: "מזוזה",
                      en: "Mezuzah",
                    )),
                  ),
                  DropdownMenuItem(
                    value: ProjectType.tefillin,
                    child: Text(context.l10n.pick(
                      he: "תפילין",
                      en: "Tefillin",
                    )),
                  ),
                  DropdownMenuItem(
                    value: ProjectType.megillah,
                    child: Text(context.l10n.pick(
                      he: "מגילה",
                      en: "Megillah",
                    )),
                  ),
                ],
                onChanged: widget.existingProject == null
                    ? (val) => setState(() => _type = val!)
                    : null,
              ),
              const SizedBox(height: 10),
              _buildDynamicFields(),
              if (_type == ProjectType.tefillin) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.pick(
                      he: 'הזנה לפי המילה האחרונה',
                      en: 'Record the last completed word')),
                  value: _tefillinWords,
                  onChanged: (v) => setState(() => _tefillinWords = v),
                ),
                DropdownButtonFormField<StamScript>(
                  initialValue: _tefillinScript,
                  decoration: InputDecoration(
                      labelText: context.l10n.pick(
                          he: 'כתב לפרשיות תפילין', en: 'Tefillin script')),
                  items: [
                    for (final s in StamScript.values)
                      DropdownMenuItem(value: s, child: Text(s.label))
                  ],
                  onChanged: (v) => setState(() => _tefillinScript = v!),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: context.l10n.pick(
                    he: "אימייל הלקוח (לשליחת עדכון)",
                    en: "Client email (for progress updates)",
                  ),
                  hintText: "client@example.com",
                ),
              ),
              if (_type.isPaged) ...[
                const SizedBox(height: 10),
                ListTile(
                  title: Text(
                    _targetCompletionDate == null
                        ? context.l10n.pick(
                            he: "תאריך יעד לסיום (אופציונלי)",
                            en: "Completion target date (optional)",
                          )
                        : context.l10n.pick(
                            he: "תאריך יעד: ${formatDisplayDate(_targetCompletionDate!, widget.useGregorianDates)}",
                            en: "Target date: ${formatDisplayDate(_targetCompletionDate!, widget.useGregorianDates, english: true)}",
                          ),
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
          child: Text(context.l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(context.l10n.pick(he: "שמור", en: "Save")),
        ),
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
                  decoration: InputDecoration(
                    labelText: context.l10n.pick(
                      he: 'סה"כ עמודים',
                      en: 'Total pages',
                    ),
                  ),
                  validator: (v) => _validatePositiveInt(
                    v,
                    context.l10n.pick(he: 'סה"כ עמודים', en: 'total pages'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _linesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.pick(
                      he: 'שורות לעמוד',
                      en: 'Lines per page',
                    ),
                  ),
                  validator: (v) => _validatePositiveInt(
                    v,
                    context.l10n.pick(he: 'שורות לעמוד', en: 'lines per page'),
                  ),
                ),
              ),
            ],
          ),
        ] else if (_type == ProjectType.megillah) ...[
          DropdownButtonFormField<String>(
            initialValue: _megillahFormat,
            decoration: InputDecoration(
              labelText: context.l10n.pick(
                he: 'מספר שורות במגילה',
                en: 'Megillah layout',
              ),
            ),
            items: [
              for (final format in MegillahFormat.values)
                DropdownMenuItem(
                  value: format,
                  child: Text(context.l10n.pick(
                    he: '${MegillahFormat.displayLines(format)} שורות · ${MegillahFormat.totalPages(format)} עמודים',
                    en: '${MegillahFormat.displayLines(format)} lines · ${MegillahFormat.totalPages(format)} pages',
                  )),
                ),
            ],
            onChanged: (value) => setState(() {
              _megillahFormat = MegillahFormat.normalize(value);
            }),
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
                  ? context.l10n.pick(
                      he: 'כמה מזוזות בהזמנה',
                      en: 'Number of Mezuzot ordered',
                    )
                  : context.l10n.pick(
                      he: 'כמה זוגות בהזמנה',
                      en: 'Number of Tefillin sets ordered',
                    ),
              helperText: context.l10n.pick(
                he: 'משמש לחישוב ההתקדמות וצפי הסיום',
                en: 'Used to calculate progress and estimated completion',
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = int.tryParse(v.trim());
              return (n == null || n <= 0)
                  ? context.l10n.pick(
                      he: 'יש להזין מספר חיובי',
                      en: 'Enter a positive number',
                    )
                  : null;
            },
          ),
        const SizedBox(height: 10),
        Text(
          _getPriceLabel(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: SoferTokens.of(context).inkMuted,
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
                decoration: InputDecoration(
                  labelText: context.l10n.pick(he: "מחיר", en: "Price"),
                ),
                validator: (v) => _validateMoney(
                  v,
                  context.l10n.pick(he: "מחיר", en: "price"),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _expensesCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.l10n.pick(he: "הוצאות", en: "Expenses"),
                ),
                validator: (v) => _validateMoney(
                  v,
                  context.l10n.pick(he: "הוצאות", en: "expenses"),
                  allowEmpty: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _getTargetLabel(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: SoferTokens.of(context).inkMuted,
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
                      ? context.l10n.pick(
                          he: "פרשיות ליום",
                          en: "Parashiyot per day",
                        )
                      : (_dailyGoalInLines
                          ? context.l10n.pick(
                              he: "יעד יומי (שורות)",
                              en: "Daily target (lines)",
                            )
                          : context.l10n.pick(
                              he: "יעד יומי (עמודים)",
                              en: "Daily target (pages)",
                            )),
                ),
                // No cap. Eight was the number of parshiyot in a pair, from
                // when a commission could only be one — meaningless against an
                // order of ten pairs, and it refused a perfectly ordinary goal.
                validator: (v) => null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _monthlyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.pick(
                    he: "יעד חודשי (יחידות)",
                    en: "Monthly target (units)",
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_type.isPaged) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(context.l10n.pick(
                he: "יעד יומי בשורות (במקום עמודים):",
                en: "Set the daily target in lines instead of pages:",
              )),
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
      return allowEmpty
          ? null
          : context.l10n.pick(
              he: "יש להזין $label",
              en: "Enter $label",
            );
    }
    // The same reader the save uses. They used to differ, and the difference
    // was a commission priced at zero — see [MoneyInput].
    final parsed = MoneyInput.parse(text);
    if (parsed == null) {
      return context.l10n.pick(
        he: "$label חייב להיות מספר",
        en: "$label must be a number",
      );
    }
    if (parsed < 0) {
      return context.l10n.pick(
        he: "$label לא יכול להיות שלילי",
        en: "$label cannot be negative",
      );
    }
    return null;
  }

  String? _validatePositiveInt(String? value, String label) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return context.l10n.pick(he: "יש להזין $label", en: "Enter $label");
    }
    final parsed = int.tryParse(text);
    if (parsed == null) {
      return context.l10n.pick(
        he: "$label חייב להיות מספר שלם",
        en: "$label must be a whole number",
      );
    }
    // Zero used to be accepted here and then broke line validation and the
    // daily goal downstream.
    if (parsed <= 0) {
      return context.l10n.pick(
        he: "$label חייב להיות גדול מאפס",
        en: "$label must be greater than zero",
      );
    }
    return null;
  }

  String _getPriceLabel() {
    if (_type == ProjectType.sefer) {
      return context.l10n.pick(he: "כספים (לעמוד)", en: "Finances (per page)");
    }
    if (_type == ProjectType.tefillin) {
      return context.l10n.pick(he: "כספים (לזוג)", en: "Finances (per set)");
    }
    if (_type == ProjectType.megillah) {
      return context.l10n.pick(
        he: "כספים (לכל הפרויקט)",
        en: "Finances (whole project)",
      );
    }
    return context.l10n
        .pick(he: "כספים (למזוזה)", en: "Finances (per Mezuzah)");
  }

  String _getTargetLabel() {
    if (_type.isPaged) {
      return context.l10n.pick(he: "יעדים (עמודים)", en: "Targets (pages)");
    }
    if (_type == ProjectType.tefillin) {
      return context.l10n.pick(he: "יעדים", en: "Targets");
    }
    return context.l10n.pick(he: "יעדים (מזוזות)", en: "Targets (Mezuzot)");
  }

  /// Page geometry feeds both production and profit, so changing it on a
  /// project with recorded work shifts how that work is counted. Sessions
  /// recorded from now on carry their own snapshot; older ones do not.
  Future<bool> _confirmGeometryChange() async {
    final existing = widget.existingProject;
    if (existing == null || !widget.hasRecordedWork) return true;
    if (!existing.type.isPaged) return true;

    final newLines = existing.type == ProjectType.megillah
        ? MegillahFormat.storedLinesPerPage(_megillahFormat)
        : int.tryParse(_linesCtrl.text);
    final newPages = existing.type == ProjectType.megillah
        ? MegillahFormat.totalPages(_megillahFormat)
        : int.tryParse(_pagesCtrl.text);
    final linesChanged =
        newLines != null && newLines != (existing.linesPerPage ?? newLines);
    final pagesChanged =
        newPages != null && newPages != (existing.totalPages ?? newPages);
    if (!linesChanged && !pagesChanged) return true;

    return confirmAction(
      context,
      title: context.l10n.pick(
        he: existing.type == ProjectType.megillah
            ? "שינוי מבנה המגילה"
            : "שינוי הגדרות הספר",
        en: existing.type == ProjectType.megillah
            ? "Change Megillah layout"
            : "Change Sefer Torah settings",
      ),
      message: linesChanged
          ? context.l10n.pick(
              he: "שינית את מספר השורות לעמוד מ-${existing.linesPerPage} ל-$newLines.\n\nרשומות שנכתבו מכאן ואילך יחושבו לפי הערך החדש. רשומות ישנות שנשמרו לפני עדכון זה עשויות להיות מחושבות מחדש – מה שישנה את ההספק והרווח המוצגים עבורן.\n\nלהמשיך?",
              en: "You changed the lines per page from ${existing.linesPerPage} to $newLines.\n\nNew records will use this value. Older records may be recalculated, changing their displayed output and profit.\n\nContinue?",
            )
          : context.l10n.pick(
              he: "שינית את מספר העמודים בספר מ-${existing.totalPages} ל-$newPages.\n\nשינוי זה משפיע על אחוזי ההתקדמות ועל צפי הסיום.\n\nלהמשיך?",
              en: "You changed the page count from ${existing.totalPages} to $newPages.\n\nThis affects progress and the estimated completion date.\n\nContinue?",
            ),
      confirmLabel: context.l10n.pick(he: "המשך", en: "Continue"),
    );
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      if (!await _confirmGeometryChange()) return;
      if (!mounted) return;
      final email = _clientEmailCtrl.text.trim();
      final totalPages = _type == ProjectType.megillah
          ? MegillahFormat.totalPages(_megillahFormat)
          : (_type == ProjectType.sefer ? int.tryParse(_pagesCtrl.text) : null);
      final linesPerPage = _type == ProjectType.megillah
          ? MegillahFormat.storedLinesPerPage(_megillahFormat)
          : (_type == ProjectType.sefer ? int.tryParse(_linesCtrl.text) : null);
      final targetUnits = _type.isPaged ? null : int.tryParse(_unitsCtrl.text);
      final existing = widget.existingProject;
      // Editing is a replacement of an immutable value, not a new
      // commission. Start from the existing value so fields not shown in this
      // form (plans, tefillin flags and future extension fields) survive.
      final p = existing == null
          ? Project(
              id: IdGenerator.generate(),
              name: _nameCtrl.text,
              type: _type,
              price: MoneyInput.parse(_priceCtrl.text) ?? 0,
              expenses: MoneyInput.parse(_expensesCtrl.text) ?? 0,
              currency: _currency,
              targetDaily: int.tryParse(_dailyCtrl.text) ?? 0,
              targetMonthly: int.tryParse(_monthlyCtrl.text) ?? 0,
              dailyGoalInLines: _type.isPaged ? _dailyGoalInLines : false,
              totalPages: totalPages,
              linesPerPage: linesPerPage,
              megillahFormat:
                  _type == ProjectType.megillah ? _megillahFormat : null,
              targetUnits: targetUnits,
              clientEmail: email.isEmpty ? null : email,
              targetCompletionDate: _targetCompletionDate,
            )
          : existing.copyWith(
              name: _nameCtrl.text,
              price: MoneyInput.parse(_priceCtrl.text) ?? 0,
              expenses: MoneyInput.parse(_expensesCtrl.text) ?? 0,
              // An existing commission keeps what it was agreed in. Only a
              // new one takes the setting — changing the setting must not
              // restate a price.
              targetDaily: int.tryParse(_dailyCtrl.text) ?? 0,
              targetMonthly: int.tryParse(_monthlyCtrl.text) ?? 0,
              dailyGoalInLines: _type.isPaged ? _dailyGoalInLines : false,
              totalPages: totalPages,
              linesPerPage: linesPerPage,
              megillahFormat:
                  _type == ProjectType.megillah ? _megillahFormat : null,
              targetUnits: targetUnits,
              clientEmail: email.isEmpty ? null : email,
              targetCompletionDate: _targetCompletionDate,
            );
      widget.onSave(_type == ProjectType.tefillin
          ? TefillinPreferences.update(p,
              words: _tefillinWords, script: _tefillinScript)
          : p);
      Navigator.pop(context);
    }
  }
}
