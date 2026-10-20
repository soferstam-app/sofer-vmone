import 'dart:async';

import 'package:flutter/material.dart';
import 'logic/measured_work.dart';
import 'logic/megillah_format.dart';
import 'logic/completion_estimator.dart';
import 'logic/expense_logic.dart';
import 'logic/hebrew_work_calendar.dart';
import 'logic/production_calculator.dart';
import 'logic/profit_calculator.dart';
import 'models.dart';
import 'hebrew_utils.dart';
import 'project/commission_timeline.dart';
import 'project/scroll_map.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'widgets/confirm.dart';
import 'widgets/feedback.dart';
import 'format.dart';
import 'logic/client_update.dart';
import 'logic/tefillin_state.dart';
import 'logic/tefillin_units.dart';
import 'project/rhythm_panel.dart';
import 'project/tefillin_board.dart';
import 'project/project_writing_tab.dart';
import 'logic/hebrew_clock.dart';
import 'logic/payment_ledger.dart';
import 'logic/proofread_board.dart';
import 'logic/work_correction.dart';
import 'project/payment_sheet.dart';
import 'project/client_update_sheet.dart';
import 'l10n/app_localizations.dart';

class ProjectSummaryScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;
  final FutureOr<void> Function(List<Project>, List<WorkSession>)?
      onWorkCommitted;
  final String? initialProjectId;
  final Future<Project?> Function(Project project)? onEditProject;
  final Future<bool> Function(Project project)? onDeleteProject;
  final FutureOr<void> Function(Project)? onProjectUpdated;
  final FutureOr<void> Function(List<WorkSession>)? onHistoryUpdated;

  const ProjectSummaryScreen({
    super.key,
    required this.projects,
    required this.history,
    this.initialProjectId,
    this.onWorkCommitted,
    this.onEditProject,
    this.onDeleteProject,
    this.onProjectUpdated,
    this.onHistoryUpdated,
  });

  @override
  State<ProjectSummaryScreen> createState() => _ProjectSummaryScreenState();
}

class _ProjectSummaryScreenState extends State<ProjectSummaryScreen> {
  late List<Project> _projects;
  late List<WorkSession> _history;
  bool _workSaving = false;
  Project? _selectedProject;
  WorkCalendarRules _rules = WorkCalendarRules.standard;
  bool _useGregorianDates = false;

  /// Needed so the rhythm panel files a sitting under the same working day the
  /// rest of the app does — otherwise late-night work lands on the wrong
  /// weekday and the "strongest day" is quietly one day out.
  DayStart _dayStart = DayStart.midnight;
  String _soferName = '';

  /// Expenses charged directly to projects, loaded once so the summary can show
  /// what a project actually cost.
  List<Expense> _expenses = [];

  /// Proofreading batches, so the screen can say what is still out. The one
  /// stage of the job somebody else is holding.
  List<Proofread> _proofreads = const [];

  /// Payments received, so the screen can answer "how much of this have I
  /// actually been paid" beside the price it already shows.
  List<Payment> _payments = const [];
  final StorageService _storage = StorageService();

  /// Whether the tefillin board is laid out a row per pair, or transposed so
  /// that every קדש sits under every other.
  BoardGrouping _boardGrouping = BoardGrouping.byPair;

  /// Flags from the last committed snapshot, keyed like [Project.tefillinFlags].
  Map<String, String>? _flagsOverride;
  _ProjectSection _section = _ProjectSection.overview;

  Map<String, String> _flagsFor(Project project) =>
      _flagsOverride ?? project.tefillinFlags;

  /// The commission drawn as the thing it is, and the one place its
  /// exceptional states can be set.
  Widget _tefillinBoard(
    Project project,
    List<WorkSession> sessions, {
    BoardGrouping? grouping,
    ValueChanged<BoardGrouping>? onGroupingChanged,
    Future<void> Function(TefillinSlot)? onSlotTap,
  }) {
    final withFlags = project.copyWith(tefillinFlags: _flagsFor(project));
    return TefillinBoard(
      projectName: project.name,
      slots: TefillinState.slots(withFlags, sessions),
      pairsOrdered: project.targetUnits,
      dailyTarget: context.l10n.pick(
          he: '${project.targetDaily} פרשיות',
          en: '${project.targetDaily} Parashiyot'),
      grouping: grouping ?? _boardGrouping,
      onGroupingChanged:
          onGroupingChanged ?? (g) => setState(() => _boardGrouping = g),
      onSlotTap: (slot) =>
          (onSlotTap ?? (slot) => _slotActions(project, slot))(slot),
      onHelp: () => showDialog<void>(
        context: context,
        builder: (_) => const TefillinShareHelp(),
      ),
    );
  }

  /// What can be said about a slot that the sessions cannot say themselves.
  Future<void> _slotActions(Project project, TefillinSlot slot) async {
    final t = SoferTokens.of(context);
    final name = TefillinUnits.names[slot.parshiya - 1];
    final where = context.l10n.pick(
      he: 'זוג ${slot.pair} · ${TefillinUnits.sideName(slot.side)} · $name',
      en: 'Set ${slot.pair} · ${slot.side == TefillinSide.head ? 'Shel Rosh' : 'Shel Yad'} · $name',
    );

    final action = await showModalBottomSheet<_TefillinSlotAction>(
      context: context,
      backgroundColor: t.paper,
      builder: (ctx) => Directionality(
        textDirection: context.l10n.textDirection,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(where,
                      style: TextStyle(
                          fontFamily: t.numeralFamily,
                          fontSize: 16,
                          color: t.ink)),
                ),
              ),
              if (slot.state != SlotState.stuck)
                ListTile(
                  leading: Icon(Icons.build_outlined, color: t.caution),
                  title: Text(context.l10n.pick(
                      he: 'מסמן: ממתין לתיקון',
                      en: 'Mark: Awaiting Correction')),
                  onTap: () =>
                      Navigator.pop(ctx, _TefillinSlotAction.markStuck),
                ),
              if (slot.state != SlotState.voided)
                ListTile(
                  leading: Icon(Icons.block, color: t.danger),
                  title: Text(
                      context.l10n.pick(he: 'מסמן: נפסל', en: 'Mark: Invalid')),
                  onTap: () =>
                      Navigator.pop(ctx, _TefillinSlotAction.markVoided),
                ),
              if (slot.state == SlotState.stuck ||
                  slot.state == SlotState.voided)
                ListTile(
                  leading: Icon(Icons.undo, color: t.accent),
                  title: Text(
                      context.l10n.pick(he: 'ביטול הסימון', en: 'Clear mark')),
                  onTap: () => Navigator.pop(ctx, _TefillinSlotAction.clear),
                ),
              if (slot.state == SlotState.voided)
                ListTile(
                  leading: Icon(Icons.restart_alt, color: t.danger),
                  title: Text(context.l10n.pick(
                      he: 'הסר את הפרשייה והתחל מחדש',
                      en: 'Remove the Parashah and start again')),
                  subtitle: Text(context.l10n.pick(
                      he: 'גם הפרשיות שאחריה באותו סט יוסרו',
                      en: 'Later Parashiyot in this set will also be removed')),
                  onTap: () => Navigator.pop(ctx, _TefillinSlotAction.remove),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    switch (action) {
      case _TefillinSlotAction.markStuck:
        await _setFlag(project, slot, TefillinState.stuckFlag);
      case _TefillinSlotAction.markVoided:
        await _setFlag(project, slot, TefillinState.voidFlag);
      case _TefillinSlotAction.clear:
        await _setFlag(project, slot, null);
      case _TefillinSlotAction.remove:
        await _removeTefillinFrom(project, slot);
      case null:
        return;
    }
  }

  /// Marks a slot held for correction or written off, or clears the mark.
  ///
  /// Writes the whole project list back rather than the one commission,
  /// because that is the only shape the store takes.
  Future<void> _setFlag(
      Project project, TefillinSlot slot, String? flag) async {
    final key = Project.slotKey(slot.pair,
        slot.side == TefillinSide.head ? 'head' : 'hand', slot.parshiya);
    final next = {...project.tefillinFlags};
    if (flag == null) {
      next.remove(key);
    } else {
      next[key] = flag;
    }

    var nextHistory = _history;
    if (flag == TefillinState.voidFlag) {
      final correction = WorkCorrection.markTefillinInvalid(
        history: _history,
        project: project,
        pair: slot.pair,
        side: slot.side,
        parshiya: slot.parshiya,
      );
      nextHistory = correction.history;
    } else if (flag == null) {
      final side = slot.side == TefillinSide.head ? 'head' : 'hand';
      final slotIds = _history
          .where((session) =>
              !session.isDeleted &&
              session.projectId == project.id &&
              session.pairIndex == slot.pair &&
              session.tefillinType == side &&
              session.parshiya == slot.parshiya)
          .map((session) => session.id)
          .toSet();
      if (slotIds.isNotEmpty) {
        nextHistory =
            WorkCorrection.markInvalid(_history, slotIds, invalid: false)
                .history;
      }
    }

    await _commitWork(project.copyWith(tefillinFlags: next), nextHistory);
  }

  /// Removes a rejected parshiya and every later parshiya in the same four.
  /// Keeping later work would leave an invalid set that appears valid on the
  /// board, so the cascade is part of the operation rather than a second
  /// question the writer can miss.
  Future<void> _removeTefillinFrom(Project project, TefillinSlot slot) async {
    final name = TefillinUnits.names[slot.parshiya - 1];
    final confirmed = await confirmAction(
      context,
      title: context.l10n
          .pick(he: 'להסיר את פרשיית $name?', en: 'Remove Parashah $name?'),
      message: context.l10n.pick(
          he: 'הפרשייה וכל הפרשיות שאחריה באותו סט יועברו לסל המחזור. לאחר מכן יהיה אפשר להתחיל את $name מחדש.',
          en: 'This Parashah and all later Parashiyot in the same set will move to the Recycle Bin. You can then start $name again.'),
      cancelLabel: context.l10n.cancel,
      confirmLabel:
          context.l10n.pick(he: 'הסר והתחל מחדש', en: 'Remove and start again'),
      danger: true,
    );
    if (!confirmed || !mounted) return;

    final side = slot.side == TefillinSide.head ? 'head' : 'hand';
    final nextFlags = {...project.tefillinFlags};
    for (var p = slot.parshiya; p <= 4; p++) {
      nextFlags.remove(Project.slotKey(slot.pair, side, p));
    }

    final correction = WorkCorrection.deleteTefillinFrom(
      history: _history,
      project: project,
      pair: slot.pair,
      side: slot.side,
      parshiya: slot.parshiya,
    );
    final nextHistory = correction.history;
    if (!await _commitWork(
        project.copyWith(tefillinFlags: nextFlags), nextHistory)) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(context.l10n.pick(
              he: 'פרשיית $name הוסרה ואפשר להתחיל אותה מחדש',
              en: 'Parashah $name was removed and can now be started again'))),
    );
  }

  @override
  void initState() {
    super.initState();
    _projects = [...widget.projects];
    _history = [...widget.history];
    if (_projects.isNotEmpty) {
      _selectedProject = _projects.firstWhere(
        (project) => project.id == widget.initialProjectId,
        orElse: () => _projects.first,
      );
    }
    _storage.getWorkCalendarRules().then((v) {
      if (mounted) setState(() => _rules = v);
    });
    _storage.getUseGregorianDates().then((v) {
      if (mounted) setState(() => _useGregorianDates = v);
    });
    _storage.getDayStart().then((v) {
      if (mounted) setState(() => _dayStart = v);
    });
    _storage.getSoferName().then((v) {
      if (mounted) setState(() => _soferName = v);
    });
    _storage.loadExpenses().then((v) {
      if (mounted) setState(() => _expenses = v);
    });
    _storage.loadProofreads().then((v) {
      if (mounted) setState(() => _proofreads = v);
    });
    _storage.loadPayments().then((v) {
      if (mounted) setState(() => _payments = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedProject;
    return Scaffold(
      appBar: AppBar(
        title: Text(selected?.name ??
            context.l10n.pick(he: "מרכז הפרויקט", en: "Project center")),
        actions: [
          if (selected != null)
            PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'edit') await _editProject(selected);
                if (action == 'delete') {
                  final deleted =
                      await widget.onDeleteProject?.call(selected) ?? false;
                  if (!mounted || !deleted) return;
                  Navigator.pop(this.context);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(context.l10n.pick(
                        he: 'עריכת פרטי הפרויקט', en: 'Edit project details')),
                  ),
                ),
                if (widget.onDeleteProject != null)
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline,
                          color: SoferTokens.of(context).danger),
                      title: Text(context.l10n
                          .pick(he: 'מחיקת הפרויקט', en: 'Delete project')),
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (_projects.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: DropdownButtonFormField<Project>(
                initialValue: _selectedProject,
                decoration: InputDecoration(
                  labelText:
                      context.l10n.pick(he: "בחר פרויקט", en: "Select project"),
                  border: const OutlineInputBorder(),
                ),
                items: _projects.map((p) {
                  return DropdownMenuItem(value: p, child: Text(p.name));
                }).toList(),
                onChanged: (val) => setState(() {
                  _selectedProject = val;
                  _flagsOverride = val?.tefillinFlags;
                }),
              ),
            ),
          if (selected != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: SegmentedButton<_ProjectSection>(
                segments: [
                  ButtonSegment(
                    value: _ProjectSection.overview,
                    icon: const Icon(Icons.insights_outlined),
                    label: Text(context.l10n.pick(he: 'סקירה', en: 'Overview')),
                  ),
                  ButtonSegment(
                    value: _ProjectSection.writing,
                    icon: const Icon(Icons.history_edu_outlined),
                    label: Text(context.l10n.pick(he: 'הכתיבה', en: 'Writing')),
                  ),
                  ButtonSegment(
                    value: _ProjectSection.details,
                    icon: const Icon(Icons.tune_outlined),
                    label: Text(context.l10n.pick(he: 'פרטים', en: 'Details')),
                  ),
                ],
                selected: {_section},
                onSelectionChanged: (value) =>
                    setState(() => _section = value.first),
              ),
            ),
            Expanded(
              child: switch (_section) {
                _ProjectSection.overview => _buildProjectContent(selected),
                _ProjectSection.writing => ProjectWritingTab(
                    project: selected,
                    projects: _projects,
                    history: _history,
                    dayStart: _dayStart,
                    useGregorianDates: _useGregorianDates,
                    onHistoryUpdated: _historyUpdated,
                    tefillinBoard: selected.type == ProjectType.tefillin
                        ? _tefillinBoard(
                            selected,
                            _history
                                .where((session) =>
                                    session.projectId == selected.id &&
                                    !session.isDeleted &&
                                    !session.isInvalid)
                                .toList(),
                          )
                        : null,
                  ),
                _ProjectSection.details => _details(selected),
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editProject(Project project) async {
    final updated = await widget.onEditProject?.call(project);
    if (updated == null || !mounted) return;
    setState(() {
      _projects = [for (final p in _projects) p.id == updated.id ? updated : p];
      _selectedProject = updated;
      _flagsOverride = updated.tefillinFlags;
    });
  }

  Future<bool> _commitWork(
      Project updated, List<WorkSession> nextHistory) async {
    if (_workSaving) return false;
    _workSaving = true;
    try {
      final storedProjects = await _storage.loadProjects();
      final nextProjects = [
        for (final p in storedProjects) p.id == updated.id ? updated : p
      ];
      await _storage.saveWorkSnapshot(
          projects: nextProjects, history: nextHistory);
      _projects = [for (final p in _projects) p.id == updated.id ? updated : p];
      _history = [...nextHistory];
      if (mounted) {
        setState(() {
          _selectedProject = updated;
          _flagsOverride = updated.tefillinFlags;
        });
      }
      try {
        await widget.onWorkCommitted?.call(nextProjects, nextHistory);
      } catch (error) {
        debugPrint('Project refresh after commit failed: $error');
      }
      return true;
    } catch (error) {
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'השינוי לא נשמר. אפשר לנסות שוב: $error',
                en: 'The change could not be saved. Try again: $error'));
      }
      return false;
    } finally {
      _workSaving = false;
    }
  }

  Future<void> _historyUpdated(List<WorkSession> next) async {
    if (widget.onHistoryUpdated != null) {
      await widget.onHistoryUpdated!(next);
    } else {
      await _storage.saveHistory(next);
    }
    if (mounted) setState(() => _history = [...next]);
  }

  Widget _details(Project project) {
    final t = SoferTokens.of(context);
    String typeName() => switch (project.type) {
          ProjectType.sefer =>
            context.l10n.pick(he: 'ספר תורה', en: 'Sefer Torah'),
          ProjectType.megillah =>
            context.l10n.pick(he: 'מגילה', en: 'Megillah'),
          ProjectType.mezuza => context.l10n.pick(he: 'מזוזות', en: 'Mezuzot'),
          ProjectType.tefillin =>
            context.l10n.pick(he: 'תפילין', en: 'Tefillin'),
        };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: SoferSectionTitle(context.l10n
                  .pick(he: 'פרטי ההזמנה', en: 'Commission details')),
            ),
            FilledButton.tonalIcon(
              onPressed: widget.onEditProject == null
                  ? null
                  : () => _editProject(project),
              icon: const Icon(Icons.edit_outlined),
              label: Text(context.l10n.pick(he: 'עריכה', en: 'Edit')),
            ),
          ],
        ),
        Card(
          child: Column(
            children: [
              _detailRow(context.l10n.pick(he: 'שם', en: 'Name'), project.name),
              _detailRow(context.l10n.pick(he: 'סוג', en: 'Type'), typeName()),
              if (project.clientEmail case final email? when email.isNotEmpty)
                _detailRow(context.l10n.pick(he: 'לקוח', en: 'Client'), email),
              _detailRow(context.l10n.pick(he: 'מחיר', en: 'Price'),
                  formatMoney(project.price, project.currency)),
              _detailRow(context.l10n.pick(he: 'יעד יומי', en: 'Daily target'),
                  '${project.targetDaily}'),
              _detailRow(
                  context.l10n.pick(he: 'יעד חודשי', en: 'Monthly target'),
                  '${project.targetMonthly}'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SoferSectionTitle(
            context.l10n.pick(he: 'מבנה העבודה', en: 'Work structure')),
        Card(
          child: Column(
            children: [
              if (project.type.isPaged) ...[
                _detailRow(
                    context.l10n.pick(he: 'עמודים בספר', en: 'Sefer pages'),
                    '${project.totalPages ?? ProductionCalculator.defaultTotalPages}'),
                _detailRow(
                    context.l10n.pick(he: 'שורות לעמוד', en: 'Lines per page'),
                    '${ProductionCalculator.linesPerPageOf(project)}'),
              ] else
                _detailRow(
                    project.type == ProjectType.mezuza
                        ? context.l10n
                            .pick(he: 'מזוזות בהזמנה', en: 'Ordered Mezuzot')
                        : context.l10n
                            .pick(he: 'זוגות בהזמנה', en: 'Ordered sets'),
                    '${project.targetUnits ?? '—'}'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Text(
                  context.l10n.pick(
                    he: 'שינוי המבנה עשוי להשפיע על חישובי התקדמות. לפני שמירה יוצג פירוט ההשפעה.',
                    en: 'Structural changes may affect progress calculations. Their impact is shown before saving.',
                  ),
                  style: TextStyle(color: t.inkMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) => ListTile(
        dense: true,
        title: Text(label),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(value, textAlign: TextAlign.end),
        ),
      );

  /// What proofreading on this commission is waiting on, in a line.
  ///
  /// Null when there is nothing recorded — an empty row saying "nothing" is
  /// noise on a screen that is already dense. Whose turn it is comes first,
  /// because that is the only part that asks for an action.
  String? _proofreadLine(Project project) {
    final board = ProofreadBoard.of(_proofreads, projectId: project.id);
    if (board.records.isEmpty) return null;

    final mine = board.mine.length;
    final out = board.at(ProofreadStage.sent).length;
    if (mine == 0 && out == 0) {
      return context.l10n.pick(he: 'הכול הושלם', en: 'Everything is complete');
    }

    return [
      if (mine > 0)
        context.l10n.pick(
            he: '$mine ממתינות לך', en: '$mine awaiting your corrections'),
      if (out > 0)
        context.l10n
            .pick(he: '$out אצל המגיה', en: '$out with the proofreader'),
    ].join(' · ');
  }

  /// What has come in on this commission, and the way in to record more.
  ///
  /// A tappable row rather than a figure, because the answer and the action
  /// belong together: a writer who sees that eight thousand is outstanding is
  /// often looking at it because he has just been paid some of it.
  Widget _paymentRow(Project project) {
    final ledger = PaymentLedger.of(
      project: project,
      allPayments: _payments,
      history: _history,
    );
    final outstanding = ledger.outstanding;
    final value = ledger.isEmpty
        ? context.l10n.pick(he: "לא נרשמו תשלומים", en: "No payments recorded")
        : [
            context.l10n.pick(
                he: "התקבל ${ledger.received.format(project.currency)}",
                en: "Received ${ledger.received.format(project.currency)}"),
            if (outstanding != null && outstanding.amount > 0)
              context.l10n.pick(
                  he: "נותר ${outstanding.format()}",
                  en: "${outstanding.format()} outstanding"),
            if (outstanding != null && outstanding.amount == 0)
              context.l10n.pick(he: "שולם במלואו", en: "Paid in full"),
            if (outstanding == null)
              context.l10n.pick(
                  he: 'היתרה אינה מחושבת — תשלומים בכמה מטבעות',
                  en: 'Outstanding unavailable — multiple currencies'),
          ].join(' · ');

    return InkWell(
      onTap: () async {
        final changed = await showPaymentSheet(
          context: context,
          project: project,
          history: _history,
          useGregorianDates: _useGregorianDates,
        );
        if (!changed || !mounted) return;
        final fresh = await _storage.loadPayments();
        if (mounted) setState(() => _payments = fresh);
      },
      child: SoferTokens.of(context).isRules
          ? SoferStatRow(
              context.l10n.pick(he: 'תשלומים', en: 'Payments'), value)
          : _statRow(context.l10n.pick(he: "תשלומים:", en: "Payments:"), value),
    );
  }

  Widget _buildProjectContent(Project project) {
    final sessions = _history
        .where((s) => s.projectId == project.id && !s.isDeleted)
        .toList();
    final sessionsForStats = sessions.where((s) => !s.backlogOnly).toList();
    final validOutputSessions =
        sessionsForStats.where((s) => !s.isInvalid).toList();
    final invalidTime = MeasuredWork.invalidTime(
        sessions.where((session) => !session.backlogOnly));

    // Anything divided by time is measured only from work that carried time.
    //
    // A record entered without hours has startTime == endTime, so its duration
    // is zero while its lines still count. Summed over everything, minutes per
    // line came out too low and shekels per hour too high — both flattering,
    // both invisible from the screen, and both further off the more such
    // records a writer keeps. Totals, profit and progress still count every
    // record: those are quantities, not rates.
    // MeasuredWork rather than timeRecorded alone. A record can claim to carry
    // time and hold a negative duration -- from an old backup, or a file edited
    // by hand -- and summing those raw took an honest hour down to half of one.
    final sessionsWithTime = MeasuredWork.only(sessionsForStats);
    final someWorkUntimed = sessionsWithTime.length != sessionsForStats.length;
    String totalWrittenStr = "";
    double totalProfit = 0;
    String avgTimeStr = "";

    final Duration totalTime = MeasuredWork.time(sessionsWithTime);
    final comparableLinesForStats = project.type == ProjectType.tefillin
        ? ProductionCalculator.tefillinSeferLinesTotal(sessionsWithTime,
            includeInvalid: true)
        : ProductionCalculator.comparableLinesTotal(project, sessionsWithTime,
            includeInvalid: true);

    int totalLinesWritten = 0;
    if (project.type.isPaged) {
      totalLinesWritten =
          ProductionCalculator.seferLinesTotal(validOutputSessions);

      final int linesPerPage = ProductionCalculator.linesPerPageOf(project);

      totalWrittenStr = context.l10n.pick(
          he: "${totalLinesWritten ~/ linesPerPage} עמודים ו-${totalLinesWritten % linesPerPage} שורות",
          en: "${totalLinesWritten ~/ linesPerPage} pages and ${totalLinesWritten % linesPerPage} lines");

      // The lines on the other side of the ratio, from the same records the
      // time came from — otherwise it divides lines that carried no time by
      // time that produced no lines.
      totalProfit = ProfitCalculator.profit(project, validOutputSessions);

      if (comparableLinesForStats > 0 && totalTime.inSeconds > 0) {
        double avg = minutesWithSeconds(totalTime) / comparableLinesForStats;
        avgTimeStr = context.l10n.pick(
            he: "${avg.toStringAsFixed(2)} דקות לשורה",
            en: "${avg.toStringAsFixed(2)} minutes per line");
      }
    } else if (project.type == ProjectType.mezuza) {
      final int totalMezuzotLines =
          ProductionCalculator.mezuzaLinesTotal(validOutputSessions);
      double mezuzot = totalMezuzotLines / ProductionCalculator.linesPerMezuza;
      totalWrittenStr = context.l10n.pick(
          he: "${mezuzot.toStringAsFixed(1)} מזוזות",
          en: "${mezuzot.toStringAsFixed(1)} Mezuzot");
      totalProfit = ProfitCalculator.profit(project, validOutputSessions);

      if (comparableLinesForStats > 0 && totalTime.inSeconds > 0) {
        double avg = minutesWithSeconds(totalTime) / comparableLinesForStats;
        avgTimeStr = context.l10n.pick(
            he: "${avg.toStringAsFixed(2)} דקות לשורה",
            en: "${avg.toStringAsFixed(2)} minutes per line");
      }
    } else {
      final totalParshiyot =
          ProductionCalculator.parshiyotTotal(validOutputSessions);
      final physicalLines =
          ProductionCalculator.tefillinPhysicalLinesTotal(validOutputSessions);
      final comparableLines =
          ProductionCalculator.tefillinSeferLinesTotal(validOutputSessions);
      final comparableText = comparableLines % 1 == 0
          ? comparableLines.toInt().toString()
          : comparableLines.toStringAsFixed(1);
      totalWrittenStr = context.l10n.pick(
        he: "$physicalLines ($comparableText) שורות · $totalParshiyot פרשיות",
        en: "$physicalLines ($comparableText) lines · $totalParshiyot Parashiyot",
      );
      totalProfit = ProfitCalculator.profit(project, validOutputSessions);

      if (comparableLinesForStats > 0 && totalTime.inSeconds > 0) {
        final avg = minutesWithSeconds(totalTime) / comparableLinesForStats;
        avgTimeStr = context.l10n.pick(
          he: "${avg.toStringAsFixed(2)} דקות לשורה",
          en: "${avg.toStringAsFixed(2)} minutes per line",
        );
      }
    }

    // Backlog sessions are excluded from both sides of this ratio: they carry
    // no earnings and their time is a placeholder.
    // Profit per hour is a rate, so both sides come from the timed records.
    final hourlyRate =
        ProfitCalculator.profitPerHour(project, sessionsWithTime, totalTime);
    // Only the costs actually in the commission's own currency count towards
    // its net. Anything bought in another is real, but subtracting it here
    // would be arithmetic across two units.
    // Proofreading is folded in with the receipts rather than shown apart. It
    // is a cost of this commission and the annual report has always charged it
    // as one, but the project's own net left it out -- so the writer saw a net
    // that had not moved, concluded the app had missed the bill, and recorded
    // it a second time as an expense. Then it *was* counted twice, in the
    // report handed to his accountant.
    final proofreadCost = _proofreads
        .where((r) =>
            !r.isDeleted &&
            r.projectId == project.id &&
            r.cost > 0 &&
            r.currency == project.currency)
        .fold<double>(0, (sum, r) => sum + r.cost);

    final projectExpenses = (ExpenseLogic.totalForProject(project.id, _expenses)
                .single(project.currency)
                ?.amount ??
            0.0) +
        proofreadCost;

    // One estimator for every project type. A sefer states its size in pages,
    // mezuzot and tefillin in units; both arrive here as billable units, so the
    // delivery date is produced the same way for all three.
    final estimate = CompletionEstimator.estimate(
      project: project,
      history: _history,
      rules: _rules,
    );

    final String estimatedEndStr = estimate == null
        ? ""
        : formatDisplayDate(estimate.plan.completionDate, _useGregorianDates,
            english: context.l10n.isEnglish);

    String targetPaceStr = "";
    if (project.targetCompletionDate != null && estimate != null) {
      final needed = CompletionEstimator.paceRequiredFor(
        remainingUnits: estimate.remainingUnits,
        deadline: project.targetCompletionDate!,
        rules: _rules,
        overrides: project.planOverrides,
      );
      if (needed != null) {
        targetPaceStr = project.type.isPaged
            ? context.l10n.pick(
                he:
                    "${(needed * ProductionCalculator.linesPerPageOf(project)).toStringAsFixed(1)} שורות ליום עבודה",
                en:
                    "${(needed * ProductionCalculator.linesPerPageOf(project)).toStringAsFixed(1)} lines per workday")
            : context.l10n.pick(
                he: "${needed.toStringAsFixed(1)} ${_unitPlural(project.type)} ליום עבודה",
                en: "${needed.toStringAsFixed(1)} ${_unitPlural(project.type)} per workday");
      }
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          if (project.clientEmail != null && project.clientEmail!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final body = ClientUpdate.compose(
                      project: project,
                      totalWritten: totalWrittenStr,
                      estimatedEnd: estimatedEndStr,
                      linesWritten: totalLinesWritten,
                      soferName: _soferName,
                      today: DateTime.now(),
                      formatDate: (d) => formatDisplayDate(
                          d, _useGregorianDates,
                          english: context.l10n.isEnglish),
                      english: context.l10n.isEnglish,
                    );
                    if (!mounted) return;
                    // Shown before it is sent. Going straight to a mailto link
                    // failed in two ways nobody could tell from the app being
                    // broken — see showClientUpdate.
                    await showClientUpdate(
                      context: context,
                      body: body,
                      subject: context.l10n.pick(
                          he: 'עדכון התקדמות – ${project.name}',
                          en: 'Progress update – ${project.name}'),
                      to: project.clientEmail,
                    );
                  },
                  icon: const Icon(Icons.email),
                  label: Text(context.l10n
                      .pick(he: "שלח עדכון ללקוח", en: "Send client update")),
                ),
              ),
            ),
          if (SoferTokens.of(context).isRules)
            _ruledLedger(
              project: project,
              totalWrittenStr: totalWrittenStr,
              totalProfit: totalProfit,
              projectExpenses: projectExpenses,
              hourlyRate: hourlyRate,
              avgTimeStr: avgTimeStr,
              someWorkUntimed: someWorkUntimed,
              invalidTime: invalidTime,
              estimate: estimate,
              targetPaceStr: targetPaceStr,
            )
          else ...[
            Card(
              margin: const EdgeInsets.all(16),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _statRow(
                        context.l10n
                            .pick(he: "סך הכל נכתב:", en: "Total written:"),
                        totalWrittenStr),
                    if (_proofreadLine(project) != null)
                      _statRow(
                          context.l10n.pick(he: "הגהה:", en: "Proofreading:"),
                          _proofreadLine(project)!),
                    _paymentRow(project),
                    _statRow(
                        context.l10n
                            .pick(he: "סך הכל רווח:", en: "Total profit:"),
                        formatMoneyExact(totalProfit, project.currency)),
                    if (projectExpenses > 0) ...[
                      _statRow(
                          context.l10n.pick(
                              he: "הוצאות משויכות:", en: "Allocated expenses:"),
                          formatMoneyExact(projectExpenses, project.currency)),
                      _statRow(
                          context.l10n.pick(
                              he: "נטו (לאחר הוצאות):",
                              en: "Net (after expenses):"),
                          formatMoneyExact(
                              totalProfit - projectExpenses, project.currency)),
                    ],
                    if (hourlyRate != null)
                      _statRow(
                          context.l10n
                              .pick(he: "שכר לשעה:", en: "Hourly earnings:"),
                          context.l10n.pick(
                              he: "${formatMoney(hourlyRate, project.currency)} לשעה",
                              en: "${formatMoney(hourlyRate, project.currency)} per hour")),
                    if (avgTimeStr.isNotEmpty)
                      _statRow(context.l10n.pick(he: "ממוצע:", en: "Average:"),
                          avgTimeStr),
                    if (invalidTime > Duration.zero)
                      _statRow(
                        context.l10n.pick(
                            he: "זמן על עבודה שנפסלה:",
                            en: "Time on invalid work:"),
                        formatSpan(invalidTime,
                            english: context.l10n.isEnglish),
                      ),
                    if (someWorkUntimed)
                      _statRow(
                          "",
                          context.l10n.pick(
                              he: "הממוצע מחושב רק מרשומות שנמדד בהן זמן",
                              en: "The average uses only records with measured time")),
                  ],
                ),
              ),
            ),
            if (estimate != null)
              _completionCard(project, estimate, targetPaceStr)
            else if (project.plannedUnits == null)
              _missingSizeCard(project),
          ],
          RhythmPanel(
            project: project,
            sessions: sessionsForStats,
            dayStart: _dayStart,
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              flex: 2,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  /// The commission written as a ledger page rather than as a stack of cards.
  ///
  /// Two columns once there is room: the money and output on one side as ruled
  /// rows, the delivery date on the other set large, with the reasoning under
  /// it. On a phone the two stack. Nothing is boxed, and the only colour is the
  /// accent on the hourly rate and the date.
  Widget _ruledLedger({
    required Project project,
    required String totalWrittenStr,
    required double totalProfit,
    required double projectExpenses,
    required double? hourlyRate,
    required String avgTimeStr,
    required bool someWorkUntimed,
    required Duration invalidTime,
    required CompletionEstimate? estimate,
    required String targetPaceStr,
  }) {
    final t = SoferTokens.of(context);

    final net = totalProfit - projectExpenses;
    final started = _firstSessionDate(project);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SoferRule(strong: true),

        if (estimate == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Text(
              project.plannedUnits == null
                  ? context.l10n.pick(
                      he:
                          "כדי לחשב צפי סיום צריך להזין את ${_sizeQuestion(project)}",
                      en:
                          "Enter ${_sizeQuestion(project)} to calculate an estimated completion date")
                  : context.l10n
                      .pick(he: "העבודה הושלמה", en: "The project is complete"),
              style: TextStyle(
                  fontFamily: t.numeralFamily,
                  fontSize: 21,
                  height: 1.4,
                  color: project.plannedUnits == null ? t.caution : t.inkMuted),
            ),
          )
        else ...[
          // The run from the day it began to the day it lands, with the agreed
          // deadline on the same line — so whether it will be met is read off
          // the line rather than worked out from two dates.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
            child: Builder(builder: (context) {
              final run = TimelineRun.of(
                started: started,
                estimatedEnd: estimate.plan.completionDate,
                target: project.targetCompletionDate,
              );
              return CommissionTimeline(
                elapsed: run.elapsed,
                marks: run.marks(
                  estimatedEnd: estimate.plan.completionDate,
                  target: project.targetCompletionDate,
                  formatDate: (d) => formatDisplayDate(d, _useGregorianDates,
                      english: context.l10n.isEnglish),
                  english: context.l10n.isEnglish,
                ),
              );
            }),
          ),
          // How much is written is a different question from how much of the run
          // has gone by, and it gets its own row rather than being drawn on the
          // same line in the same colour.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                        "${(MegillahFormat.displayedProgress(project, estimate.progress) * 100).toStringAsFixed(0)}%",
                        style: TextStyle(
                            fontFamily: t.numeralFamily,
                            fontSize: 27,
                            height: 1,
                            color: t.accent)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                          context.l10n.pick(
                              he: "מהעבודה נכתבו",
                              en: "of the project written"),
                          style: TextStyle(
                              fontFamily: t.labelFamily,
                              fontSize: 13,
                              color: t.inkMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                SoferProgress(MegillahFormat.displayedProgress(
                    project, estimate.progress)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Text.rich(
              TextSpan(children: [
                if (deadlineVerdict(
                        target: project.targetCompletionDate,
                        estimatedEnd: estimate.plan.completionDate,
                        english: context.l10n.isEnglish)
                    case final verdict?)
                  TextSpan(
                    text: "${verdict.text}. ",
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 15,
                        height: 1.8,
                        color: verdict.late ? t.danger : t.accent),
                  ),
                TextSpan(
                  text: _deliverySentence(project, estimate, targetPaceStr),
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 15,
                      height: 1.8,
                      color: t.inkMuted),
                ),
              ]),
            ),
          ),
        ],

        const SoferRule(),

        // Two columns: the work on one side, the money on the other.
        LayoutBuilder(builder: (context, box) {
          final work = Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoferSectionTitle(
                    context.l10n.pick(he: "העבודה", en: "The work"),
                    padding: EdgeInsets.zero),
                const SizedBox(height: 6),
                SoferStatRow(context.l10n.pick(he: "נכתב", en: "Written"),
                    totalWrittenStr),
                if (estimate != null)
                  SoferStatRow(context.l10n.pick(he: "נותרו", en: "Remaining"),
                      "${estimate.remainingUnits.toStringAsFixed(0)} ${_unitPlural(project.type)}"),
                if (avgTimeStr.isNotEmpty)
                  SoferStatRow(
                      context.l10n.pick(he: "ממוצע", en: "Average"), avgTimeStr,
                      last: !someWorkUntimed && invalidTime == Duration.zero),
                if (someWorkUntimed)
                  SoferStatRow(
                      "",
                      context.l10n.pick(
                          he: "רק מרשומות שנמדד בהן זמן",
                          en: "Only records with measured time"),
                      last: true),
                if (invalidTime > Duration.zero)
                  SoferStatRow(
                    context.l10n.pick(
                        he: "זמן על עבודה שנפסלה", en: "Time on invalid work"),
                    formatSpan(invalidTime, english: context.l10n.isEnglish),
                    last: invalidTime == Duration.zero,
                  ),
              ],
            ),
          );

          final money = Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoferSectionTitle(context.l10n.pick(he: "הכסף", en: "Money"),
                    padding: EdgeInsets.zero),
                const SizedBox(height: 6),
                _paymentRow(project),
                if (projectExpenses > 0) ...[
                  SoferStatRow(context.l10n.pick(he: "רווח", en: "Profit"),
                      formatMoney(totalProfit, project.currency)),
                  SoferStatRow(
                      context.l10n
                          .pick(he: "הוצאות משויכות", en: "Allocated expenses"),
                      formatMoney(projectExpenses, project.currency)),
                ],
                SoferStatRow(
                    projectExpenses > 0
                        ? context.l10n.pick(he: "נטו", en: "Net")
                        : context.l10n.pick(he: "רווח", en: "Profit"),
                    formatMoney(net, project.currency)),
                SoferStatRow(
                    context.l10n.pick(he: "לשעה", en: "Per hour"),
                    hourlyRate == null
                        ? "—"
                        : formatMoney(hourlyRate, project.currency),
                    emphasise: hourlyRate != null,
                    last: true),
              ],
            ),
          );

          if (box.maxWidth <= 620) {
            return Column(children: [work, const SoferRule(), money]);
          }
          // IntrinsicHeight so the rule between the columns runs the height of
          // the taller one. Without it the row took the scroll view's unbounded
          // height, which in a release build pushed everything below it —
          // including the map — an infinite distance down the page.
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: work),
                Container(width: 1, color: t.rule),
                Expanded(child: money),
              ],
            ),
          );
        }),

        const SoferRule(strong: true),

        // A row of its own, the full width of the page. As a small outlined
        // button at the end of a line of text the map was not found at all —
        // and the line of text beside it only repeated what the sentence above
        // already says.
        InkWell(
          onTap: () => _openMap(project),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Row(
              children: [
                Icon(Icons.grid_view, size: 20, color: t.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          context.l10n
                              .pick(he: "מפת העבודה", en: "Project map"),
                          style: TextStyle(
                              fontFamily: t.numeralFamily,
                              fontSize: 17,
                              color: t.ink)),
                      const SizedBox(height: 2),
                      Text(_mapSubtitle(project),
                          style: TextStyle(
                              fontFamily: t.labelFamily,
                              fontSize: 12,
                              color: t.inkMuted)),
                    ],
                  ),
                ),
                Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                    color: t.inkFaint),
              ],
            ),
          ),
        ),
        const SoferRule(strong: true),
      ],
    );
  }

  /// What the map is a map of, in the unit the commission is counted in.
  String _mapSubtitle(Project project) => switch (project.type) {
        ProjectType.sefer => context.l10n.pick(
            he: "כל עמוד בספר, ומה נכתב בו",
            en: "Every page in the Sefer and what has been written"),
        ProjectType.megillah => context.l10n.pick(
            he: "כל עמוד במגילה, ומה נכתב בו",
            en: "Every page in the Megillah and what has been written"),
        ProjectType.mezuza => context.l10n.pick(
            he: "כל מזוזה בהזמנה, ומה כבר נכתב",
            en: "Every Mezuzah in the order and what has been written"),
        ProjectType.tefillin => context.l10n.pick(
            he: "כל זוג בהזמנה, ומה כבר נכתב",
            en: "Every set in the order and what has been written"),
      };

  /// The day the first session on this commission was recorded, or null when
  /// nothing has been.
  DateTime? _firstSessionDate(Project project) {
    DateTime? first;
    for (final s in _history) {
      if (s.projectId != project.id || s.isDeleted || s.backlogOnly) continue;
      if (first == null || s.startTime.isBefore(first)) first = s.startTime;
    }
    return first;
  }

  /// Opens the map of the whole commission, in whatever unit it is counted in.
  void _openMap(Project project) {
    // Sefer Torah's editable, page-by-page map lives in the unified writing
    // section. Keep the overview entry point connected to that same map.
    if (project.type.isPaged) {
      setState(() => _section = _ProjectSection.writing);
      return;
    }

    final sessions = _history
        .where((s) => s.projectId == project.id && !s.isDeleted && !s.isInvalid)
        .toList();

    // Tefillin has a map of its own. Filling counted units from the first
    // said only how much was done, never which parshiya of which pair — and
    // for tefillin that is the whole question.
    if (project.type == ProjectType.tefillin) {
      var grouping = _boardGrouping;
      Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: SoferTokens.of(context).paper,
          appBar: AppBar(
            backgroundColor: SoferTokens.of(context).paper,
            foregroundColor: SoferTokens.of(context).ink,
            elevation: 0,
            title: Text(context.l10n.pick(he: "מפת העבודה", en: "Project map")),
          ),
          body: StatefulBuilder(
            builder: (mapContext, setMapState) => _tefillinBoard(
              project,
              _history
                  .where((s) =>
                      s.projectId == project.id && !s.isDeleted && !s.isInvalid)
                  .toList(),
              grouping: grouping,
              onGroupingChanged: (next) => setMapState(() {
                grouping = next;
                _boardGrouping = next;
              }),
              onSlotTap: (slot) async {
                await _slotActions(project, slot);
                if (mapContext.mounted) setMapState(() {});
              },
            ),
          ),
        ),
      ));
      return;
    }

    // Mezuzot are counted, not paginated: the map is how many of the order are
    // finished, filled from the first.
    final done = ProductionCalculator.projectUnits(project, sessions);
    final total = (project.targetUnits ?? done.ceil()).clamp(1, 1 << 20);
    showScrollMap(
      context,
      title: context.l10n.pick(he: "מפת המזוזות", en: "Mezuzot map"),
      total: total,
      fill: {
        for (var i = 1; i <= total; i++) i: (done - (i - 1)).clamp(0.0, 1.0),
      },
      unitSingular: context.l10n.pick(he: "מזוזה", en: "Mezuzah"),
      unitPlural: context.l10n.pick(he: "מזוזות", en: "Mezuzot"),
      hebrewNumerals: false,
    );
  }

  /// The delivery estimate written out, including what it rests on and what the
  /// calendar takes away.
  String _deliverySentence(
      Project project, CompletionEstimate estimate, String targetPaceStr) {
    final unit = _unitPlural(project.type);
    final parts = <String>[
      estimate.paceMeasured
          ? context.l10n.pick(
              he:
                  "בקצב שנמדד — ${estimate.unitsPerWorkDay.toStringAsFixed(2)} $unit ליום עבודה",
              en:
                  "At the measured pace — ${estimate.unitsPerWorkDay.toStringAsFixed(2)} $unit per workday")
          : context.l10n.pick(
              he: "לפי היעד היומי שהגדרת, כי אין עוד מספיק עבודה מתועדת",
              en: "Based on your daily target, because there is not enough recorded work yet"),
      context.l10n.pick(
          he: "נותרו ${estimate.plan.calendarDays} ימים, מהם ${estimate.workDaysLeft.toStringAsFixed(1)} ימי עבודה",
          en: "${estimate.plan.calendarDays} calendar days remain, including ${estimate.workDaysLeft.toStringAsFixed(1)} workdays"),
    ];
    if (estimate.plan.skippedTotal > 0) {
      parts.add(context.l10n.pick(
          he: "${estimate.plan.skippedTotal} ימים בדרך אינם ימי עבודה (${formatSkippedDays(estimate.plan, maxReasons: 2)})",
          en: "${estimate.plan.skippedTotal} days along the way are not workdays (${formatSkippedDays(estimate.plan, maxReasons: 2, english: true)})"));
    }
    if (targetPaceStr.isNotEmpty) {
      parts.add(context.l10n.pick(
          he: "כדי לעמוד בתאריך היעד צריך $targetPaceStr",
          en: "To meet the target date you need $targetPaceStr"));
    }
    return "${parts.join('. ')}.";
  }

  /// What is missing when a commission has no stated size.
  String _sizeQuestion(Project project) => switch (project.type) {
        ProjectType.sefer => context.l10n.pick(
            he: "מספר העמודים בספר", en: "the number of pages in the Sefer"),
        ProjectType.megillah => context.l10n.pick(
            he: "מספר העמודים במגילה",
            en: "the number of pages in the Megillah"),
        ProjectType.mezuza => context.l10n.pick(
            he: "כמה מזוזות בהזמנה", en: "the number of Mezuzot in the order"),
        ProjectType.tefillin => context.l10n.pick(
            he: "כמה זוגות בהזמנה", en: "the number of sets in the order"),
      };

  String _unitPlural(ProjectType type) => switch (type) {
        ProjectType.sefer => context.l10n.pick(he: 'עמודים', en: 'pages'),
        ProjectType.megillah => context.l10n.pick(he: 'עמודים', en: 'pages'),
        ProjectType.mezuza => context.l10n.pick(he: 'מזוזות', en: 'Mezuzot'),
        ProjectType.tefillin => context.l10n.pick(he: 'זוגות', en: 'sets'),
      };

  /// The delivery date, and what it rests on.
  ///
  /// A date on its own invites either blind trust or dismissal, so the card
  /// also shows the pace it was derived from, whether that pace was measured or
  /// assumed, and how many days were lost to the calendar on the way.
  Widget _completionCard(
    Project project,
    CompletionEstimate estimate,
    String targetPaceStr,
  ) {
    final plan = estimate.plan;
    final unit = _unitPlural(project.type);
    final shownProgress =
        MegillahFormat.displayedProgress(project, estimate.progress);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_available,
                    color: SoferTokens.of(context).accent),
                const SizedBox(width: 8),
                Text(
                    context.l10n
                        .pick(he: "צפי סיום", en: "Estimated completion"),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              formatDisplayDateWithWeekday(
                  plan.completionDate, _useGregorianDates,
                  english: context.l10n.isEnglish),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: SoferTokens.of(context).accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.pick(
                  he: "בעוד ${plan.calendarDays} ימים · ${estimate.workDaysLeft.toStringAsFixed(1)} ימי עבודה",
                  en: "In ${plan.calendarDays} days · ${estimate.workDaysLeft.toStringAsFixed(1)} workdays"),
              style: TextStyle(color: SoferTokens.of(context).inkMuted),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: shownProgress.clamp(0.0, 1.0),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.pick(
                  he: "${estimate.doneUnits.toStringAsFixed(1)} מתוך ${estimate.totalUnits.toStringAsFixed(0)} $unit (${(shownProgress * 100).toStringAsFixed(0)}%)",
                  en: "${estimate.doneUnits.toStringAsFixed(1)} of ${estimate.totalUnits.toStringAsFixed(0)} $unit (${(shownProgress * 100).toStringAsFixed(0)}%)"),
              style: TextStyle(
                  fontSize: 13, color: SoferTokens.of(context).inkMuted),
            ),
            const Divider(height: 24),
            _statRow(
              estimate.paceMeasured
                  ? context.l10n.pick(he: "הקצב שלך:", en: "Your pace:")
                  : context.l10n.pick(
                      he: "לפי היעד היומי:", en: "Based on daily target:"),
              context.l10n.pick(
                  he: "${estimate.unitsPerWorkDay.toStringAsFixed(2)} $unit ליום עבודה",
                  en: "${estimate.unitsPerWorkDay.toStringAsFixed(2)} $unit per workday"),
            ),
            if (!estimate.paceMeasured)
              Text(
                context.l10n.pick(
                    he: "עדיין אין מספיק עבודה מתועדת בפרויקט, לכן החישוב לפי היעד היומי שהגדרת ולא לפי הקצב בפועל.",
                    en: "There is not enough recorded work in this project yet, so the calculation uses your daily target rather than your actual pace."),
                style: TextStyle(
                    fontSize: 12, color: SoferTokens.of(context).caution),
              ),
            if (targetPaceStr.isNotEmpty)
              _statRow(
                  context.l10n.pick(
                      he: "נדרש כדי לעמוד בתאריך היעד:",
                      en: "Required to meet the target date:"),
                  targetPaceStr),
            if (plan.skippedTotal > 0) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.pick(
                    he: "${plan.skippedTotal} ימים בדרך אינם ימי עבודה: ${formatSkippedDays(plan)}",
                    en: "${plan.skippedTotal} days along the way are not workdays: ${formatSkippedDays(plan, english: true)}"),
                style: TextStyle(
                    fontSize: 12, color: SoferTokens.of(context).inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Shown when the job size was never entered, since without it no date can
  /// be worked out at all.
  Widget _missingSizeCard(Project project) {
    final what = _sizeQuestion(project);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      color: SoferTokens.of(context).paper,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: SoferTokens.of(context).caution),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.pick(
                    he: "כדי לחשב צפי סיום צריך להזין בפרויקט את $what.",
                    en: "Enter $what in the project to calculate an estimated completion date."),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TefillinSlotAction { markStuck, markVoided, clear, remove }

enum _ProjectSection { overview, writing, details }
