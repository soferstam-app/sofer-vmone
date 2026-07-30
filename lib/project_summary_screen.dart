import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
  String _soferName = '';

  /// Expenses charged directly to projects, loaded once so the summary can show
  /// what a project actually cost.
  List<Expense> _expenses = [];
  final StorageService _storage = StorageService();

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
    _storage.getSoferName().then((v) {
      if (mounted) setState(() => _soferName = v);
    });
    _storage.loadExpenses().then((v) {
      if (mounted) setState(() => _expenses = v);
    });
  }

  /// Builds the client progress update.
  ///
  /// Written as something a sofer could send as-is: what was written, how far
  /// along it is, and when it is expected to be finished — the last being what
  /// a client actually wants to know. Figures the screen cannot compute for a
  /// given project type are simply left out rather than shown empty.
  String _buildClientEmailBody({
    required Project project,
    required String totalWrittenStr,
    required String estimatedEndStr,
    required int totalLinesWritten,
  }) {
    final today = formatDisplayDate(DateTime.now(), _useGregorianDates);
    final lines = <String>[
      'בס"ד',
      '',
      'שלום וברכה,',
      '',
      'להלן עדכון על התקדמות העבודה בפרויקט "${project.name}", נכון לתאריך $today:',
      '',
    ];

    if (project.type == ProjectType.sefer && project.totalPages != null) {
      final linesPerPage = ProductionCalculator.linesPerPageOf(project);
      final totalLines = project.totalPages! * linesPerPage;
      lines.add('• נכתב עד כה: $totalWrittenStr'
          ' (מתוך ${project.totalPages} עמודים)');
      if (totalLines > 0) {
        final percent = (totalLinesWritten / totalLines * 100).clamp(0, 100);
        lines.add('• התקדמות: ${percent.toStringAsFixed(0)}%');
      }
    } else {
      lines.add('• נכתב עד כה: $totalWrittenStr');
    }

    if (estimatedEndStr.isNotEmpty) {
      lines.add('• צפי סיום משוער: $estimatedEndStr');
    }
    if (project.targetCompletionDate != null) {
      lines.add('• תאריך יעד מוסכם: '
          '${formatDisplayDate(project.targetCompletionDate!, _useGregorianDates)}');
    }

    lines.addAll([
      '',
      'אשמח לעמוד לרשותכם בכל שאלה.',
      '',
      'בברכה,',
    ]);
    if (_soferName.isNotEmpty) lines.add(_soferName);

    return lines.join('\n');
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

  Widget _buildProjectContent(Project project) {
    final sessions =
        widget.history.where((s) => s.projectId == project.id).toList();
    final sessionsForStats =
        sessions.where((s) => !s.backlogOnly).toList();

    String totalWrittenStr = "";
    double totalProfit = 0;
    String avgTimeStr = "";

    Duration totalTime = Duration.zero;
    for (var s in sessionsForStats) {
      totalTime += s.duration;
    }

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

      int linesForStats = 0;
      for (var s in sessionsForStats) {
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
          ProductionCalculator.mezuzaLinesTotal(sessionsForStats);
      totalProfit = ProfitCalculator.profit(project, sessionsForStats);

      if (mezuzaLinesForStats > 0 && totalTime.inSeconds > 0) {
        double avg = totalTime.inMinutes / mezuzaLinesForStats;
        avgTimeStr = "${avg.toStringAsFixed(2)} דקות לשורה";
      }
    } else {
      final int totalParshiyot =
          ProductionCalculator.parshiyotTotal(sessions);
      totalWrittenStr = "$totalParshiyot פרשיות (סה\"כ)";
      final int parshiyotForStats =
          ProductionCalculator.parshiyotTotal(sessionsForStats);
      totalProfit = ProfitCalculator.profit(project, sessionsForStats);

      if (parshiyotForStats > 0 && totalTime.inSeconds > 0) {
        double avg = totalTime.inMinutes / parshiyotForStats;
        avgTimeStr = "${avg.toStringAsFixed(2)} דקות לפרשייה";
      }
    }

    // Backlog sessions are excluded from both sides of this ratio: they carry
    // no earnings and their time is a placeholder.
    final hourlyRate =
        ProfitCalculator.profitPerHour(project, sessionsForStats, totalTime);
    final projectExpenses =
        ExpenseLogic.totalForProject(project.id, _expenses);

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
                    final body = _buildClientEmailBody(
                      project: project,
                      totalWrittenStr: totalWrittenStr,
                      estimatedEndStr: estimatedEndStr,
                      totalLinesWritten: totalLinesWritten,
                    );
                    final uri = Uri(
                      scheme: 'mailto',
                      path: project.clientEmail,
                      query:
                          'subject=${Uri.encodeComponent('עדכון התקדמות – ${project.name}')}&body=${Uri.encodeComponent(body)}',
                    );
                    final messenger = ScaffoldMessenger.of(context);
                    final opened = await canLaunchUrl(uri)
                        ? await launchUrl(uri)
                        : false;
                    if (!opened && mounted) {
                      // Previously this failed silently, so a user without a
                      // mail app configured saw nothing happen at all.
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                              "לא נמצאה תוכנת מייל במכשיר. ניתן להעתיק את פרטי ההתקדמות ידנית."),
                          backgroundColor: SoferTokens.of(context).danger,
                          duration: Duration(seconds: 5),
                        ),
                      );
                    }
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
                    _statRow(
                        "סך הכל רווח:", "₪${totalProfit.toStringAsFixed(2)}"),
                    if (projectExpenses > 0) ...[
                      _statRow("הוצאות משויכות:",
                          "₪${projectExpenses.toStringAsFixed(2)}"),
                      _statRow("נטו (לאחר הוצאות):",
                          "₪${(totalProfit - projectExpenses).toStringAsFixed(2)}"),
                    ],
                    if (hourlyRate != null)
                      _statRow("שכר לשעה:",
                          "₪${hourlyRate.toStringAsFixed(0)} לשעה"),
                    if (avgTimeStr.isNotEmpty) _statRow("ממוצע:", avgTimeStr),
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
              _buildSeferGrid(project, sessions),
            if (project.type == ProjectType.tefillin)
              _buildTefillinGrid(project, sessions),
          ],
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
                  color:
                      project.plannedUnits == null ? t.caution : t.inkMuted),
            ),
          )
        else ...[
          // The run from the day it began to the day it lands, with the agreed
          // deadline on the same line — so whether it will be met is read off
          // the line rather than worked out from two dates.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
            child: CommissionTimeline(
              elapsed: _elapsedFraction(project, estimate, started),
              marks: _timelineMarks(project, estimate, started),
            ),
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
                if (_deadlineVerdict(project, estimate) case final verdict?)
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
                  SoferStatRow("ממוצע", avgTimeStr, last: true),
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
                  SoferStatRow("רווח", "₪${totalProfit.toStringAsFixed(0)}"),
                  SoferStatRow("הוצאות משויכות",
                      "₪${projectExpenses.toStringAsFixed(0)}"),
                ],
                SoferStatRow(
                    projectExpenses > 0 ? "נטו" : "רווח",
                    "₪${net.toStringAsFixed(0)}"),
                SoferStatRow(
                    "לשעה",
                    hourlyRate == null
                        ? "—"
                        : "₪${hourlyRate.toStringAsFixed(0)}",
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
        ProjectType.tefillin => "כל סט בהזמנה, ומה כבר נכתב",
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

  /// The stretch of time the timeline is drawn on: from the day the work began
  /// to the day it ends — whichever of the estimate and the agreed deadline is
  /// later, so that both fit on the line.
  ({DateTime from, DateTime end}) _timelineRun(
      Project project, CompletionEstimate estimate, DateTime? started) {
    final from = started ?? DateTime.now();
    var end = estimate.plan.completionDate;
    final target = project.targetCompletionDate;
    if (target != null && target.isAfter(end)) end = target;
    return (from: from, end: end);
  }

  double _atOnRun(DateTime when, ({DateTime from, DateTime end}) run) {
    final span = run.end.difference(run.from).inDays;
    if (span <= 0) return 1;
    return (when.difference(run.from).inDays / span).clamp(0.0, 1.0);
  }

  /// How much of the run has already gone by. This, and not how much has been
  /// written, is what the line is a measure of.
  double _elapsedFraction(
          Project project, CompletionEstimate estimate, DateTime? started) =>
      _atOnRun(
          DateTime.now(), _timelineRun(project, estimate, started));

  /// Start, today, the estimate and — when there is one — the agreed deadline.
  ///
  /// Today carries no date of its own: the caption says which day it is, and
  /// printing it again only crowds the line.
  List<TimelineMark> _timelineMarks(
      Project project, CompletionEstimate estimate, DateTime? started) {
    final run = _timelineRun(project, estimate, started);
    final target = project.targetCompletionDate;

    return [
      TimelineMark(
          caption: "התחלה",
          value: formatDisplayDate(run.from, _useGregorianDates),
          at: 0),
      TimelineMark(
          caption: "היום", at: _atOnRun(DateTime.now(), run), current: true),
      TimelineMark(
          caption: "צפי סיום",
          value: formatDisplayDate(
              estimate.plan.completionDate, _useGregorianDates),
          at: _atOnRun(estimate.plan.completionDate, run)),
      if (target != null)
        TimelineMark(
            caption: "תאריך יעד",
            value: formatDisplayDate(target, _useGregorianDates),
            at: _atOnRun(target, run),
            quiet: true),
    ];
  }

  /// Whether the agreed deadline will be met, and by how much.
  ({String text, bool late})? _deadlineVerdict(
      Project project, CompletionEstimate estimate) {
    final target = project.targetCompletionDate;
    if (target == null) return null;

    final days =
        target.difference(estimate.plan.completionDate).inDays;
    if (days.abs() < 3) {
      return (text: "צפוי להסתיים בדיוק בתאריך היעד", late: false);
    }
    final weeks = (days.abs() / 7).floor();
    final amount = weeks >= 1
        ? "$weeks ${weeks == 1 ? 'שבוע' : 'שבועות'}"
        : "${days.abs()} ימים";
    return days > 0
        ? (text: "אתה מקדים את תאריך היעד ב-$amount", late: false)
        : (text: "אתה מאחר מתאריך היעד ב-$amount", late: true);
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

    // Mezuzot and tefillin are counted, not paginated: the map is how many of
    // the order are finished, filled from the first.
    final done = ProfitCalculator.billableUnits(project, sessions);
    final total = (project.targetUnits ?? done.ceil()).clamp(1, 1 << 20);
    showScrollMap(
      context,
      title: project.type == ProjectType.mezuza ? "מפת המזוזות" : "מפת הסטים",
      total: total,
      fill: {
        for (var i = 1; i <= total; i++)
          i: (done - (i - 1)).clamp(0.0, 1.0),
      },
      unitSingular: project.type == ProjectType.mezuza ? "מזוזה" : "סט",
      unitPlural: project.type == ProjectType.mezuza ? "מזוזות" : "סטים",
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
          "${estimate.workDaysLeft.toStringAsFixed(0)} ימי עבודה",
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
        ProjectType.tefillin => "כמה סטים בהזמנה",
      };

  static String _unitPlural(ProjectType type) => switch (type) {
        ProjectType.sefer => 'עמודים',
        ProjectType.mezuza => 'מזוזות',
        ProjectType.tefillin => 'סטים',
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
                Icon(Icons.event_available, color: SoferTokens.of(context).accent),
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
              style: TextStyle(fontSize: 13, color: SoferTokens.of(context).inkMuted),
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
                style: TextStyle(fontSize: 12, color: SoferTokens.of(context).caution),
              ),
            if (targetPaceStr.isNotEmpty)
              _statRow("נדרש כדי לעמוד בתאריך היעד:", targetPaceStr),
            if (plan.skippedTotal > 0) ...[
              const SizedBox(height: 8),
              Text(
                "${plan.skippedTotal} ימים בדרך אינם ימי עבודה: "
                "${formatSkippedDays(plan)}",
                style: TextStyle(fontSize: 12, color: SoferTokens.of(context).inkMuted),
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
      ProjectType.tefillin => "כמה סטים בהזמנה",
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

  Widget _buildSeferGrid(Project project, List<WorkSession> sessions) {
    int totalPages = project.totalPages ?? 245;
    final int linesPerPage = ProductionCalculator.linesPerPageOf(project);

    Map<int, Set<int>> pageContent = {};
    for (var s in sessions) {
      if (s.amount > 0) {
        pageContent.putIfAbsent(s.amount, () => {});
        for (int i = s.startLine; i <= s.endLine; i++) {
          pageContent[s.amount]!.add(i);
        }
      }
    }

    final t = SoferTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
          child: Row(
            children: [
              Expanded(
                child: Text("מפת העמודים",
                    style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 12,
                      letterSpacing: t.isRules ? 1.5 : 0,
                      fontWeight: t.isCards ? FontWeight.bold : FontWeight.normal,
                      color: t.isCards ? t.accent : t.inkMuted,
                    )),
              ),
              Text("$totalPages עמודים · לחיצה לפרטים",
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 11,
                      color: t.inkFaint)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          // A page-per-cell map of the whole scroll. Sized by a maximum cell
          // extent rather than a fixed column count: at six across, 245 pages
          // came to nearly six thousand pixels of grid and pushed everything
          // below it off the screen.
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 30,
              childAspectRatio: 1 / 1.35,
              crossAxisSpacing: 3,
              mainAxisSpacing: 3,
            ),
            itemCount: totalPages,
            itemBuilder: (context, index) {
              int pageNum = index + 1;
              Set<int> lines = pageContent[pageNum] ?? {};
              double progress = lines.length / linesPerPage;
              if (progress > 1.0) progress = 1.0;

              return InkWell(
                onTap: () =>
                    _showSeferPageDetails(pageNum, lines, linesPerPage),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: SoferTokens.of(context).rule),
                // How far into the page the writing got, filled from the top.
                // The accent marks what is done, here as everywhere.
                gradient: progress > 0
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          SoferTokens.of(context).accent,
                          SoferTokens.of(context).accent,
                          SoferTokens.of(context).paper,
                          SoferTokens.of(context).paper,
                        ],
                        stops: [0.0, progress, progress, 1.0],
                      )
                    : null,
                    color:
                        progress == 0 ? SoferTokens.of(context).paper : null,
                  ),
                  alignment: Alignment.center,
                  // At this size only the shortest numerals fit, and the map is
                  // read as a shape rather than page by page — the number is in
                  // the tap.
                  child: progress > 0
                      ? null
                      : Text(
                          formatHebrewNumber(pageNum),
                          style: TextStyle(
                            fontSize: 9,
                            color: SoferTokens.of(context).inkFaint,
                          ),
                          overflow: TextOverflow.clip,
                          maxLines: 1,
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showSeferPageDetails(int page, Set<int> lines, int maxLines) {
    String msg;
    if (lines.length >= maxLines) {
      msg = "מושלם, זיכית יהודים בעוד מוצר סת\"ם כשר ומהודר";
    } else if (lines.isEmpty) {
      msg = "טרם נכתב";
    } else {
      List<int> sorted = lines.toList()..sort();
      List<String> ranges = [];
      if (sorted.isNotEmpty) {
        int start = sorted.first;
        int end = start;
        for (int i = 1; i < sorted.length; i++) {
          if (sorted[i] == end + 1) {
            end = sorted[i];
          } else {
            ranges.add(start == end ? "$start" : "$start-$end");
            start = sorted[i];
            end = start;
          }
        }
        ranges.add(start == end ? "$start" : "$start-$end");
      }
      msg = "שורות שנכתבו: ${ranges.join(', ')}";
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("עמוד ${formatHebrewNumber(page)}"),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("סגור"))
        ],
      ),
    );
  }

  Widget _buildTefillinGrid(Project project, List<WorkSession> sessions) {
    List<int> counts = List.filled(8, 0);

    for (var s in sessions) {
      if (s.tefillinType == null && s.parshiya == null) {
        for (int i = 0; i < 8; i++) {
          counts[i] += s.amount;
        }
      } else if (s.tefillinType == 'head' && s.parshiya == null) {
        for (int i = 0; i < 4; i++) {
          counts[i] += s.amount;
        }
      } else if (s.tefillinType == 'hand' && s.parshiya == null) {
        for (int i = 4; i < 8; i++) {
          counts[i] += s.amount;
        }
      } else if (s.tefillinType != null && s.parshiya != null) {
        int max = s.tefillinType == 'head' ? 4 : 7;
        if (s.endLine == 0 || s.endLine >= max) {
          int base = s.tefillinType == 'head' ? 0 : 4;
          int idx = base + (s.parshiya! - 1);
          if (idx >= 0 && idx < 8) counts[idx] += s.amount;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text("תפילין של ראש",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children:
                List.generate(4, (i) => _buildTefillinBox(i, counts[i], true)),
          ),
          const SizedBox(height: 24),
          const Text("תפילין של יד",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(
                4, (i) => _buildTefillinBox(i, counts[i + 4], false)),
          ),
        ],
      ),
    );
  }

  Widget _buildTefillinBox(int index, int count, bool isHead) {
    List<String> names = ["קדש", "והיה כי יביאך", "שמע", "והיה אם שמוע"];
    String name = names[index];

    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text("פרשיית $name (${isHead ? 'ראש' : 'יד'})"),
            content: Text("נכתבו בשלמות: $count"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("סגור"))
            ],
          ),
        );
      },
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: count > 0 ? SoferTokens.of(context).paper : SoferTokens.of(context).rule,
          border: Border.all(color: SoferTokens.of(context).accent),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
