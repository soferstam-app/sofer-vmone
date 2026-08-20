import 'package:flutter/material.dart';
import 'logic/measured_work.dart';
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
import 'format.dart';
import 'logic/client_update.dart';
import 'logic/tefillin_state.dart';
import 'logic/tefillin_units.dart';
import 'project/progress_grids.dart';
import 'project/rhythm_panel.dart';
import 'project/tefillin_board.dart';
import 'logic/hebrew_clock.dart';
import 'logic/payment_ledger.dart';
import 'logic/proofread_board.dart';
import 'project/payment_sheet.dart';
import 'project/client_update_sheet.dart';

class ProjectSummaryScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;

  const ProjectSummaryScreen({
    super.key,
    required this.projects,
    required this.history,
  });

  @override
  State<ProjectSummaryScreen> createState() => _ProjectSummaryScreenState();
}

class _ProjectSummaryScreenState extends State<ProjectSummaryScreen> {
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

  /// Flags edited on this screen, held here so the board redraws before the
  /// write comes back. Keyed like [Project.tefillinFlags].
  Map<String, String>? _flagsOverride;

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
      dailyTarget: '${project.targetDaily} פרשיות',
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
    final where =
        'זוג ${slot.pair} · ${TefillinUnits.sideName(slot.side)} · $name';

    final action = await showModalBottomSheet<_TefillinSlotAction>(
      context: context,
      backgroundColor: t.paper,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
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
                  title: const Text('מסמן: ממתין לתיקון'),
                  onTap: () =>
                      Navigator.pop(ctx, _TefillinSlotAction.markStuck),
                ),
              if (slot.state != SlotState.voided)
                ListTile(
                  leading: Icon(Icons.block, color: t.danger),
                  title: const Text('מסמן: נפסל'),
                  onTap: () =>
                      Navigator.pop(ctx, _TefillinSlotAction.markVoided),
                ),
              if (slot.state == SlotState.stuck ||
                  slot.state == SlotState.voided)
                ListTile(
                  leading: Icon(Icons.undo, color: t.accent),
                  title: const Text('ביטול הסימון'),
                  onTap: () => Navigator.pop(ctx, _TefillinSlotAction.clear),
                ),
              if (slot.state == SlotState.voided)
                ListTile(
                  leading: Icon(Icons.restart_alt, color: t.danger),
                  title: const Text('הסר את הפרשייה והתחל מחדש'),
                  subtitle: const Text('גם הפרשיות שאחריה באותו סט יוסרו'),
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

    setState(() {
      _flagsOverride = next;
      _selectedProject = project.copyWith(tefillinFlags: next);
    });

    final all = await _storage.loadProjects();
    final at = all.indexWhere((p) => p.id == project.id);
    if (at != -1) {
      all[at] = all[at].copyWith(tefillinFlags: next);
      await _storage.saveProjects(all);
    }
  }

  /// Removes a rejected parshiya and every later parshiya in the same four.
  /// Keeping later work would leave an invalid set that appears valid on the
  /// board, so the cascade is part of the operation rather than a second
  /// question the writer can miss.
  Future<void> _removeTefillinFrom(Project project, TefillinSlot slot) async {
    final name = TefillinUnits.names[slot.parshiya - 1];
    final confirmed = await confirmAction(
      context,
      title: 'להסיר את פרשיית $name?',
      message: 'הפרשייה וכל הפרשיות שאחריה באותו סט יועברו לסל המחזור. '
          'לאחר מכן יהיה אפשר להתחיל את $name מחדש.',
      cancelLabel: 'ביטול',
      confirmLabel: 'הסר והתחל מחדש',
      danger: true,
    );
    if (!confirmed || !mounted) return;

    final side = slot.side == TefillinSide.head ? 'head' : 'hand';
    final nextFlags = {...project.tefillinFlags};
    for (var p = slot.parshiya; p <= 4; p++) {
      nextFlags.remove(Project.slotKey(slot.pair, side, p));
    }

    final nextHistory = TefillinState.removeFrom(
      history: widget.history,
      projectId: project.id,
      pair: slot.pair,
      side: slot.side,
      parshiya: slot.parshiya,
    );
    widget.history
      ..clear()
      ..addAll(nextHistory);

    final updated = project.copyWith(tefillinFlags: nextFlags);
    final localProject = widget.projects.indexWhere((p) => p.id == project.id);
    if (localProject != -1) widget.projects[localProject] = updated;
    setState(() {
      _flagsOverride = nextFlags;
      _selectedProject = updated;
    });

    final storedProjects = await _storage.loadProjects();
    final storedAt = storedProjects.indexWhere((p) => p.id == project.id);
    if (storedAt != -1) storedProjects[storedAt] = updated;
    await _storage.saveProjects(storedProjects);
    await _storage.saveHistory(widget.history);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('פרשיית $name הוסרה ואפשר להתחיל אותה מחדש')),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.projects.isNotEmpty) {
      _selectedProject = widget.projects.first;
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
    return Scaffold(
      appBar: AppBar(title: const Text("סיכום פרויקט")),
      body: Column(
        children: [
          if (widget.projects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: DropdownButtonFormField<Project>(
                initialValue: _selectedProject,
                decoration: const InputDecoration(
                  labelText: "בחר פרויקט",
                  border: OutlineInputBorder(),
                ),
                items: widget.projects.map((p) {
                  return DropdownMenuItem(value: p, child: Text(p.name));
                }).toList(),
                onChanged: (val) => setState(() => _selectedProject = val),
              ),
            ),
          if (_selectedProject != null)
            Expanded(
              child: _buildProjectContent(_selectedProject!),
            ),
        ],
      ),
    );
  }

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
    if (mine == 0 && out == 0) return 'הכול הושלם';

    return [
      if (mine > 0) '$mine ממתינות לך',
      if (out > 0) '$out אצל המגיה',
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
      history: widget.history,
    );
    final outstanding = ledger.outstanding;
    final value = ledger.isEmpty
        ? "לא נרשמו תשלומים"
        : [
            "התקבל ${ledger.received.format(project.currency)}",
            if (outstanding != null && outstanding.amount > 0)
              "נותר ${outstanding.format()}",
            if (outstanding != null && outstanding.amount == 0) "שולם במלואו",
          ].join(' · ');

    return InkWell(
      onTap: () async {
        final changed = await showPaymentSheet(
          context: context,
          project: project,
          history: widget.history,
          useGregorianDates: _useGregorianDates,
        );
        if (!changed || !mounted) return;
        final fresh = await _storage.loadPayments();
        if (mounted) setState(() => _payments = fresh);
      },
      child: _statRow("תשלומים:", value),
    );
  }

  Widget _buildProjectContent(Project project) {
    final sessions = widget.history
        .where((s) => s.projectId == project.id && !s.isDeleted)
        .toList();
    final sessionsForStats = sessions.where((s) => !s.backlogOnly).toList();

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
    final tefillinAverage = project.type == ProjectType.tefillin
        ? ProductionCalculator.tefillinAverageStats(sessionsWithTime)
        : null;

    String totalWrittenStr = "";
    double totalProfit = 0;
    String avgTimeStr = "";

    final Duration totalTime = MeasuredWork.time(sessionsWithTime);

    int totalLinesWritten = 0;
    if (project.type == ProjectType.sefer) {
      int totalLines = 0;
      for (var s in sessions) {
        totalLines += ProductionCalculator.seferLinesInSession(s);
      }
      totalLinesWritten = totalLines;

      final int linesPerPage = ProductionCalculator.linesPerPageOf(project);

      totalWrittenStr =
          "${totalLines ~/ linesPerPage} עמודים ו-${totalLines % linesPerPage} שורות";

      // The lines on the other side of the ratio, from the same records the
      // time came from — otherwise it divides lines that carried no time by
      // time that produced no lines.
      int linesForStats = 0;
      for (var s in sessionsWithTime) {
        linesForStats += ProductionCalculator.seferLinesInSession(s);
      }
      totalProfit = ProfitCalculator.profit(project, sessionsForStats);

      if (linesForStats > 0 && totalTime.inSeconds > 0) {
        double avg = totalTime.inMinutes / linesForStats;
        avgTimeStr = "${avg.toStringAsFixed(2)} דקות לשורה";
      }
    } else if (project.type == ProjectType.mezuza) {
      final int totalMezuzotLines =
          ProductionCalculator.mezuzaLinesTotal(sessions);
      double mezuzot = totalMezuzotLines / ProductionCalculator.linesPerMezuza;
      totalWrittenStr = "${mezuzot.toStringAsFixed(1)} מזוזות";
      final int mezuzaLinesForStats =
          ProductionCalculator.mezuzaLinesTotal(sessionsWithTime);
      totalProfit = ProfitCalculator.profit(project, sessionsForStats);

      if (mezuzaLinesForStats > 0 && totalTime.inSeconds > 0) {
        double avg = totalTime.inMinutes / mezuzaLinesForStats;
        avgTimeStr = "${avg.toStringAsFixed(2)} דקות לשורה";
      }
    } else {
      final int totalParshiyot = ProductionCalculator.parshiyotTotal(sessions);
      totalWrittenStr = "$totalParshiyot פרשיות (סה\"כ)";
      final int parshiyotForStats = tefillinAverage?.parshiyot ?? 0;
      totalProfit = ProfitCalculator.profit(project, sessionsForStats);

      final averageTime = tefillinAverage?.duration ?? Duration.zero;
      if (parshiyotForStats > 0 && averageTime.inSeconds > 0) {
        double avg = averageTime.inMinutes / parshiyotForStats;
        avgTimeStr = "${avg.toStringAsFixed(2)} דקות לפרשייה";
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
      history: widget.history,
      rules: _rules,
    );

    final String estimatedEndStr = estimate == null
        ? ""
        : formatDisplayDate(estimate.plan.completionDate, _useGregorianDates);

    String targetPaceStr = "";
    if (project.targetCompletionDate != null && estimate != null) {
      final needed = CompletionEstimator.paceRequiredFor(
        remainingUnits: estimate.remainingUnits,
        deadline: project.targetCompletionDate!,
        rules: _rules,
      );
      if (needed != null) {
        targetPaceStr = project.type == ProjectType.sefer
            ? "${(needed * ProductionCalculator.linesPerPageOf(project)).toStringAsFixed(1)} שורות ליום עבודה"
            : "${needed.toStringAsFixed(1)} ${_unitPlural(project.type)} ליום עבודה";
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
                      formatDate: (d) =>
                          formatDisplayDate(d, _useGregorianDates),
                    );
                    if (!mounted) return;
                    // Shown before it is sent. Going straight to a mailto link
                    // failed in two ways nobody could tell from the app being
                    // broken — see showClientUpdate.
                    await showClientUpdate(
                      context: context,
                      body: body,
                      subject: 'עדכון התקדמות – ${project.name}',
                      to: project.clientEmail,
                    );
                  },
                  icon: const Icon(Icons.email),
                  label: const Text("שלח עדכון ללקוח"),
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
                    _statRow("סך הכל נכתב:", totalWrittenStr),
                    if (_proofreadLine(project) != null)
                      _statRow("הגהה:", _proofreadLine(project)!),
                    _paymentRow(project),
                    _statRow("סך הכל רווח:",
                        formatMoneyExact(totalProfit, project.currency)),
                    if (projectExpenses > 0) ...[
                      _statRow("הוצאות משויכות:",
                          formatMoneyExact(projectExpenses, project.currency)),
                      _statRow(
                          "נטו (לאחר הוצאות):",
                          formatMoneyExact(
                              totalProfit - projectExpenses, project.currency)),
                    ],
                    if (hourlyRate != null)
                      _statRow("שכר לשעה:",
                          "${formatMoney(hourlyRate, project.currency)} לשעה"),
                    if (avgTimeStr.isNotEmpty) _statRow("ממוצע:", avgTimeStr),
                    if (someWorkUntimed)
                      _statRow("", "הממוצע מחושב רק מרשומות שנמדד בהן זמן"),
                  ],
                ),
              ),
            ),
            if (estimate != null)
              _completionCard(project, estimate, targetPaceStr)
            else if (project.plannedUnits == null)
              _missingSizeCard(project),
          ],
          // The ruled layout reaches the map through the button under the
          // figures, so it is not also laid out down the screen.
          if (SoferTokens.of(context).isCards) ...[
            if (project.type == ProjectType.sefer)
              seferProgressGrid(context, project, sessions),
            if (project.type == ProjectType.tefillin)
              _tefillinBoard(project, sessions),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
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
                  ? "כדי לחשב צפי סיום צריך להזין את ${_sizeQuestion(project)}"
                  : "העבודה הושלמה",
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
                  formatDate: (d) => formatDisplayDate(d, _useGregorianDates),
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
                    Text("${(estimate.progress * 100).toStringAsFixed(0)}%",
                        style: TextStyle(
                            fontFamily: t.numeralFamily,
                            fontSize: 27,
                            height: 1,
                            color: t.accent)),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text("מהעבודה נכתבו",
                          style: TextStyle(
                              fontFamily: t.labelFamily,
                              fontSize: 13,
                              color: t.inkMuted)),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                SoferProgress(estimate.progress),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Text.rich(
              TextSpan(children: [
                if (deadlineVerdict(
                        target: project.targetCompletionDate,
                        estimatedEnd: estimate.plan.completionDate)
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
                const SoferSectionTitle("העבודה", padding: EdgeInsets.zero),
                const SizedBox(height: 6),
                SoferStatRow("נכתב", totalWrittenStr),
                if (estimate != null)
                  SoferStatRow("נותרו",
                      "${estimate.remainingUnits.toStringAsFixed(0)} ${_unitPlural(project.type)}"),
                if (avgTimeStr.isNotEmpty)
                  SoferStatRow("ממוצע", avgTimeStr, last: !someWorkUntimed),
                if (someWorkUntimed)
                  SoferStatRow("", "רק מרשומות שנמדד בהן זמן", last: true),
              ],
            ),
          );

          final money = Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SoferSectionTitle("הכסף", padding: EdgeInsets.zero),
                const SizedBox(height: 6),
                if (projectExpenses > 0) ...[
                  SoferStatRow(
                      "רווח", formatMoney(totalProfit, project.currency)),
                  SoferStatRow("הוצאות משויכות",
                      formatMoney(projectExpenses, project.currency)),
                ],
                SoferStatRow(projectExpenses > 0 ? "נטו" : "רווח",
                    formatMoney(net, project.currency)),
                SoferStatRow(
                    "לשעה",
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
                      Text("מפת העבודה",
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
                Icon(Icons.chevron_left, color: t.inkFaint),
              ],
            ),
          ),
        ),
        const SoferRule(strong: true),
      ],
    );
  }

  /// What the map is a map of, in the unit the commission is counted in.
  static String _mapSubtitle(Project project) => switch (project.type) {
        ProjectType.sefer => "כל עמוד בספר, ומה נכתב בו",
        ProjectType.mezuza => "כל מזוזה בהזמנה, ומה כבר נכתב",
        ProjectType.tefillin => "כל זוג בהזמנה, ומה כבר נכתב",
      };

  /// The day the first session on this commission was recorded, or null when
  /// nothing has been.
  DateTime? _firstSessionDate(Project project) {
    DateTime? first;
    for (final s in widget.history) {
      if (s.projectId != project.id || s.isDeleted || s.backlogOnly) continue;
      if (first == null || s.startTime.isBefore(first)) first = s.startTime;
    }
    return first;
  }

  /// Opens the map of the whole commission, in whatever unit it is counted in.
  void _openMap(Project project) {
    final sessions = widget.history
        .where((s) => s.projectId == project.id && !s.isDeleted)
        .toList();

    if (project.type == ProjectType.sefer) {
      final linesPerPage = ProductionCalculator.linesPerPageOf(project);
      final lines = <int, Set<int>>{};
      for (final s in sessions) {
        if (s.amount <= 0) continue;
        final page = lines.putIfAbsent(s.amount, () => <int>{});
        for (var i = s.startLine; i <= s.endLine; i++) {
          page.add(i);
        }
      }
      showScrollMap(
        context,
        title: "מפת הספר",
        total: project.totalPages ?? ProductionCalculator.defaultTotalPages,
        fill: {
          for (final e in lines.entries)
            e.key: (e.value.length / linesPerPage).clamp(0.0, 1.0),
        },
        unitSingular: "עמוד",
        unitPlural: "עמודים",
      );
      return;
    }

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
            title: const Text("מפת העבודה"),
          ),
          body: StatefulBuilder(
            builder: (mapContext, setMapState) => _tefillinBoard(
              project,
              widget.history
                  .where((s) => s.projectId == project.id && !s.isDeleted)
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
    final done = ProfitCalculator.billableUnits(project, sessions);
    final total = (project.targetUnits ?? done.ceil()).clamp(1, 1 << 20);
    showScrollMap(
      context,
      title: "מפת המזוזות",
      total: total,
      fill: {
        for (var i = 1; i <= total; i++) i: (done - (i - 1)).clamp(0.0, 1.0),
      },
      unitSingular: "מזוזה",
      unitPlural: "מזוזות",
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
          ? "בקצב שנמדד — ${estimate.unitsPerWorkDay.toStringAsFixed(2)} $unit ליום עבודה"
          : "לפי היעד היומי שהגדרת, כי אין עוד מספיק עבודה מתועדת",
      "נותרו ${estimate.plan.calendarDays} ימים, מהם "
          "${estimate.workDaysLeft.toStringAsFixed(1)} ימי עבודה",
    ];
    if (estimate.plan.skippedTotal > 0) {
      parts.add("${estimate.plan.skippedTotal} ימים בדרך אינם ימי עבודה "
          "(${formatSkippedDays(estimate.plan, maxReasons: 2)})");
    }
    if (targetPaceStr.isNotEmpty) {
      parts.add("כדי לעמוד בתאריך היעד צריך $targetPaceStr");
    }
    return "${parts.join('. ')}.";
  }

  /// What is missing when a commission has no stated size.
  static String _sizeQuestion(Project project) => switch (project.type) {
        ProjectType.sefer => "מספר העמודים בספר",
        ProjectType.mezuza => "כמה מזוזות בהזמנה",
        ProjectType.tefillin => "כמה זוגות בהזמנה",
      };

  static String _unitPlural(ProjectType type) => switch (type) {
        ProjectType.sefer => 'עמודים',
        ProjectType.mezuza => 'מזוזות',
        ProjectType.tefillin => 'זוגות',
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
                const Text("צפי סיום",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              formatDisplayDateWithWeekday(
                  plan.completionDate, _useGregorianDates),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: SoferTokens.of(context).accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "בעוד ${plan.calendarDays} ימים · "
              "${estimate.workDaysLeft.toStringAsFixed(1)} ימי עבודה",
              style: TextStyle(color: SoferTokens.of(context).inkMuted),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: estimate.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text(
              "${estimate.doneUnits.toStringAsFixed(1)} מתוך "
              "${estimate.totalUnits.toStringAsFixed(0)} $unit "
              "(${(estimate.progress * 100).toStringAsFixed(0)}%)",
              style: TextStyle(
                  fontSize: 13, color: SoferTokens.of(context).inkMuted),
            ),
            const Divider(height: 24),
            _statRow(
              estimate.paceMeasured ? "הקצב שלך:" : "לפי היעד היומי:",
              "${estimate.unitsPerWorkDay.toStringAsFixed(2)} $unit ליום עבודה",
            ),
            if (!estimate.paceMeasured)
              Text(
                "עדיין אין מספיק עבודה מתועדת בפרויקט, לכן החישוב לפי היעד "
                "היומי שהגדרת ולא לפי הקצב בפועל.",
                style: TextStyle(
                    fontSize: 12, color: SoferTokens.of(context).caution),
              ),
            if (targetPaceStr.isNotEmpty)
              _statRow("נדרש כדי לעמוד בתאריך היעד:", targetPaceStr),
            if (plan.skippedTotal > 0) ...[
              const SizedBox(height: 8),
              Text(
                "${plan.skippedTotal} ימים בדרך אינם ימי עבודה: "
                "${formatSkippedDays(plan)}",
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
    final what = switch (project.type) {
      ProjectType.sefer => "מספר העמודים בספר",
      ProjectType.mezuza => "כמה מזוזות בהזמנה",
      ProjectType.tefillin => "כמה זוגות בהזמנה",
    };
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
                "כדי לחשב צפי סיום צריך להזין בפרויקט את $what.",
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
