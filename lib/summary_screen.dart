import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'logic/date_logic.dart';
import 'logic/hebrew_clock.dart';
import 'logic/hebrew_work_calendar.dart';
import 'logic/measured_work.dart';
import 'logic/production_calculator.dart';
import 'logic/profit_calculator.dart';
import 'models.dart';
import 'project_summary_screen.dart';
import 'hebrew_utils.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'format.dart';
import 'summary/history_editor.dart';
import 'summary/monthly_summary.dart';
import 'logic/tefillin_summary.dart';
import 'logic/currency.dart';
import 'l10n/app_localizations.dart';

class SummaryScreen extends StatefulWidget {
  final List<Project> projects;
  final FutureOr<void> Function(List<Project>, List<WorkSession>)?
      onWorkCommitted;
  final List<WorkSession> history;
  final FutureOr<void> Function(List<WorkSession>) onHistoryUpdated;
  final Future<Project?> Function(Project project)? onEditProject;
  final Future<bool> Function(Project project)? onDeleteProject;
  final ValueChanged<Project>? onProjectUpdated;
  final bool useGregorianDates;

  const SummaryScreen({
    super.key,
    required this.projects,
    this.onWorkCommitted,
    required this.history,
    required this.onHistoryUpdated,
    this.onEditProject,
    this.onDeleteProject,
    this.onProjectUpdated,
    this.useGregorianDates = false,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late List<Project> _projects;
  late List<WorkSession> _history;
  DateTime _selectedDate = DateTime.now();
  bool _viewByMonth = false;
  final StorageService _storage = StorageService();

  /// Kept in sync with the setting so this screen files a session under the
  /// same working day the home screen displays.
  DayStart _dayStart = DayStart.midnight;

  /// Used to count the working days in a Hebrew month, so a monthly target is
  /// measured against the days the writer actually writes.
  WorkCalendarRules _rules = WorkCalendarRules.standard;

  /// Only what a total falls back to when there is nothing in it to read a
  /// currency from. Every amount shown comes from a record that carries its own.
  Currency _currency = Currency.ils;

  @override
  void initState() {
    super.initState();
    _projects = [...widget.projects];
    _history = [...widget.history];
    _storage.getDayStart().then((d) {
      if (mounted) setState(() => _dayStart = d);
    });
    _storage.getWorkCalendarRules().then((r) {
      if (mounted) setState(() => _rules = r);
    });
    _storage.getCurrency().then((c) {
      if (mounted) setState(() => _currency = c);
    });
  }

  Future<void> _historyUpdated(List<WorkSession> next) async {
    await widget.onHistoryUpdated(next);
    if (mounted) {
      setState(() => _history = next.where((s) => !s.isDeleted).toList());
    }
  }

  List<WorkSession> _getSessionsForDate(DateTime date) {
    return _history.where((session) {
      if (session.backlogOnly || session.isDeleted) {
        return false;
      }
      if (_viewByMonth) {
        return DateLogic.sessionIsInMonth(session, date, _dayStart);
      }
      return DateLogic.sessionIsOnDay(session, date, _dayStart);
    }).toList();
  }

  Map<String, List<WorkSession>> _groupSessionsByProject(
      List<WorkSession> sessions) {
    final Map<String, List<WorkSession>> grouped = {};
    for (var session in sessions) {
      if (!grouped.containsKey(session.projectId)) {
        grouped[session.projectId] = [];
      }
      grouped[session.projectId]!.add(session);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final dailySessions = _getSessionsForDate(_selectedDate);
    final groupedSessions = _groupSessionsByProject(dailySessions);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.pick(he: "סיכומים", en: "Summary")),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: context.l10n.pick(he: "עריכת רשומות", en: "Edit records"),
            onPressed: _showHistoryEditor,
          ),
        ],
      ),
      body: Column(
        children: [
          _dateHeader(),
          Expanded(
            child: dailySessions.isEmpty
                ? _buildEmptyState()
                : ListView(
                    // The ruled entries carry their own padding so their rules
                    // reach both edges; the cards keep their inset.
                    padding: EdgeInsets.symmetric(
                        horizontal: SoferTokens.of(context).isRules ? 0 : 16),
                    // Work whose commission has since been deleted is still
                    // work that was done, and it was deliberately recorded.
                    // Filtering the group out left a day that plainly had
                    // sittings showing an empty list and no explanation, so
                    // the group is shown and named instead.
                    children: groupedSessions.entries.map((entry) {
                      final project = _projects.firstWhere(
                        (p) => p.id == entry.key,
                        orElse: () => Project(
                          id: entry.key,
                          name: context.l10n.pick(
                            he: 'פרויקט שנמחק',
                            en: 'Deleted project',
                          ),
                          type: ProjectType.sefer,
                          price: 0,
                          expenses: 0,
                          targetDaily: 0,
                          targetMonthly: 0,
                        ),
                      );
                      return _buildProjectSummaryCard(project, entry.value);
                    }).toList(),
                  ),
          ),
          _buildBottomButtons(),
        ],
      ),
    );
  }

  /// The date the screen is showing.
  ///
  /// In the ruled layout it is a page heading — the date in the serif, sitting
  /// on the heavier rule — rather than a coloured line with an icon beside it.
  Widget _dateHeader() {
    final t = SoferTokens.of(context);
    final label = widget.useGregorianDates
        ? (_viewByMonth
            ? formatDisplayDateMonth(_selectedDate, true)
            : formatDisplayDate(_selectedDate, true))
        : _getHebrewDate(_selectedDate, _viewByMonth);

    if (t.isCards) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.today_rounded, color: t.accent, size: 24),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: t.accent)),
            const SizedBox(width: 8),
            // Both layouts get the same way in. See the ruled header.
            TextButton(
              onPressed: () => setState(() => _viewByMonth = !_viewByMonth),
              child: Text(
                  _viewByMonth
                      ? context.l10n.pick(he: "חודש ▾", en: "Month ▾")
                      : context.l10n.pick(he: "יום ▾", en: "Day ▾"),
                  style: TextStyle(fontSize: 13, color: t.accent)),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.ruleStrong)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 23, color: t.ink)),
          ),
          // Tappable. It was a label, and the only way to see a whole month was
          // a switch inside a dialog called "בחר תאריך עברי" — so writers
          // reported that the monthly summary showed them a single day, which
          // is exactly what it does when nobody can find the switch.
          TextButton(
            onPressed: () => setState(() => _viewByMonth = !_viewByMonth),
            child: Text(
                _viewByMonth
                    ? context.l10n.pick(he: "חודש ▾", en: "Month ▾")
                    : context.l10n.pick(he: "יום ▾", en: "Day ▾"),
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12,
                    letterSpacing: 1.5,
                    color: t.accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Icon(Icons.auto_awesome,
                size: 64, color: SoferTokens.of(context).caution),
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.pick(
              he: "כל זמן שהנר דולק אפשר לכתוב",
              en: "While the candle is burning, there is still time to write",
            ),
            style: TextStyle(
                fontSize: 18,
                fontStyle: FontStyle.italic,
                color: SoferTokens.of(context).inkMuted),
          ),
        ],
      ),
    );
  }

  /// A day's work on one commission, written as an entry in a ledger.
  ///
  /// Nothing here is a card. The output figure is set large on the right of the
  /// name, the money and time run underneath as ruled rows, and the daily
  /// target is a hairline segment with its remainder as one quiet sentence —
  /// where the modern layout uses a filled bar and a coloured verdict.
  Widget _ruledProjectEntry({
    required Project project,
    required String outputText,
    required Duration worked,
    required bool someWithoutTime,
    required String avgTimeText,
    required double profit,
    required double? hourlyRate,
    required double progressPercent,
    required String remainingText,
  }) {
    final t = SoferTokens.of(context);
    final met = progressPercent >= 1;

    // A daily target of zero is not a target. Without one there is no progress
    // to draw and no remainder to state, and drawing an empty bar under a
    // dangling "יעד יומי ·" was the defect.
    final hasTarget = remainingText.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.ruleStrong)),
      ),
      // Its own horizontal padding, so the rule runs the full width of the
      // screen the way ruling runs the full width of a page.
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(project.name,
              style: TextStyle(
                  fontFamily: t.numeralFamily,
                  fontSize: 17,
                  color: t.inkMuted)),
          const SizedBox(height: 3),
          // On its own line rather than opposite the name: the figure can be
          // "3 עמודים ו-12 שורות", which set beside a long project name
          // overflowed the row.
          Text(outputText,
              style: TextStyle(
                  fontFamily: t.numeralFamily,
                  fontSize: 26,
                  height: 1.15,
                  color: t.ink)),
          const SizedBox(height: 12),
          SoferStatRow(context.l10n.pick(he: "זמן עבודה", en: "Writing time"),
              workedLabel(worked, someWithoutTime)),
          if (avgTimeText.isNotEmpty)
            SoferStatRow(
                context.l10n.pick(he: "ממוצע", en: "Average"), avgTimeText),
          SoferStatRow(context.l10n.pick(he: "רווח נקי", en: "Net profit"),
              formatMoneyExact(profit, project.currency)),
          if (hourlyRate != null)
            SoferStatRow(context.l10n.pick(he: "שכר לשעה", en: "Hourly rate"),
                formatMoney(hourlyRate, project.currency),
                emphasise: true, last: !hasTarget),
          if (hasTarget) ...[
            const SizedBox(height: 14),
            SoferProgress(progressPercent),
            const SizedBox(height: 6),
            Text(
              context.l10n.pick(
                he: "יעד יומי · $remainingText",
                en: "Daily target · $remainingText",
              ),
              style: TextStyle(
                fontFamily: t.labelFamily,
                fontSize: 12,
                color: met ? t.positive : t.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectSummaryCard(Project project, List<WorkSession> sessions) {
    final sessionsForStats = sessions.where((s) => !s.backlogOnly).toList();
    final validOutputSessions =
        sessionsForStats.where((s) => !s.isInvalid).toList();
    final totalLinesWritten = project.type.isPaged
        ? ProductionCalculator.seferLinesTotal(validOutputSessions)
        : 0;
    final totalMezuzaLines = project.type == ProjectType.mezuza
        ? ProductionCalculator.mezuzaLinesTotal(validOutputSessions)
        : 0;
    // The records a ratio may use — see [MeasuredWork]. Time was already taken
    // only from these; the output below it was not, so measured minutes were
    // divided by lines that had never been timed.
    final measured = MeasuredWork.only(sessionsForStats);
    final totalDuration = MeasuredWork.time(measured);
    // Plenty of sofrim record what they wrote and never how long it took. The
    // total is then true but incomplete, and saying so is the difference
    // between a figure that is partial and a figure that is wrong.
    final bool someWithoutTime = MeasuredWork.anyUntimed(sessionsForStats);

    final linesForStats = project.type.isPaged
        ? ProductionCalculator.seferLinesTotal(validOutputSessions)
        : 0;
    final comparableLinesForStats = project.type == ProjectType.tefillin
        ? ProductionCalculator.tefillinSeferLinesTotal(measured,
            includeInvalid: true)
        : ProductionCalculator.comparableLinesTotal(project, measured,
            includeInvalid: true);
    int unitsForStats = 0;
    final mezuzaLinesForStats = project.type == ProjectType.mezuza
        ? ProductionCalculator.mezuzaLinesTotal(validOutputSessions)
        : 0;
    for (var s in validOutputSessions) {
      if (!project.type.isPaged) {
        unitsForStats += s.amount;
      }
    }

    String outputText = "";
    double profit = 0;
    double progressPercent = 0;
    String remainingText = "";
    String avgTimeText = "";

    // The number that actually says whether the work is worth the time: a high
    // price per page written slowly can pay less than a low price written fast.
    // A rate, so both sides come from the same measured records.
    final hourlyRate =
        ProfitCalculator.profitPerHour(project, measured, totalDuration);

    if (project.type.isPaged) {
      final int linesPerPage = ProductionCalculator.linesPerPageOf(project);

      int pages = totalLinesWritten ~/ linesPerPage;
      int lines = totalLinesWritten % linesPerPage;

      outputText = context.l10n.pick(
        he: "$pages עמודים ו-$lines שורות",
        en: "$pages pages and $lines lines",
      );

      profit = ProfitCalculator.profit(project, validOutputSessions);

      if (comparableLinesForStats > 0 && totalDuration.inSeconds > 0) {
        double avgMinutes =
            minutesWithSeconds(totalDuration) / comparableLinesForStats;
        avgTimeText = context.l10n.pick(
          he: "${avgMinutes.toStringAsFixed(2)} דקות לשורה",
          en: "${avgMinutes.toStringAsFixed(2)} minutes per line",
        );
      }

      int targetLines = project.dailyGoalInLines
          ? project.targetDaily
          : (project.targetDaily * linesPerPage);
      if (targetLines > 0) {
        progressPercent = linesForStats / targetLines;
        int linesLeft = targetLines - linesForStats;
        if (linesLeft > 0) {
          remainingText = context.l10n.pick(
            he: "נותרו $linesLeft שורות ליעד",
            en: "$linesLeft lines remaining",
          );
        } else {
          remainingText = context.l10n.pick(
            he: "היעד הושלם!",
            en: "Target reached!",
          );
        }
      }
    } else {
      if (project.type == ProjectType.mezuza) {
        profit = ProfitCalculator.profit(project, validOutputSessions);
        double displayAmount =
            totalMezuzaLines / ProductionCalculator.linesPerMezuza;
        outputText = displayAmount % 1 == 0
            ? context.l10n.pick(
                he: "${displayAmount.toInt()} מזוזות",
                en: "${displayAmount.toInt()} Mezuzot",
              )
            : context.l10n.pick(
                he: "${displayAmount.toStringAsFixed(1)} מזוזות",
                en: "${displayAmount.toStringAsFixed(1)} Mezuzot",
              );
      } else {
        profit = ProfitCalculator.profit(project, validOutputSessions);
        final description = TefillinSummary.describe(validOutputSessions,
            english: context.l10n.isEnglish);
        final physical = ProductionCalculator.tefillinPhysicalLinesTotal(
            validOutputSessions);
        final comparable =
            ProductionCalculator.tefillinSeferLinesTotal(validOutputSessions);
        final comparableText = comparable % 1 == 0
            ? comparable.toInt().toString()
            : comparable.toStringAsFixed(1);
        outputText = context.l10n.pick(
          he: "$physical ($comparableText) שורות · $description",
          en: "$physical ($comparableText) lines · $description",
        );
      }

      if (project.type == ProjectType.tefillin) {
        if (comparableLinesForStats > 0 && totalDuration.inSeconds > 0) {
          double avgMinutes =
              minutesWithSeconds(totalDuration) / comparableLinesForStats;
          avgTimeText = context.l10n.pick(
            he: "${avgMinutes.toStringAsFixed(2)} דקות לשורה",
            en: "${avgMinutes.toStringAsFixed(2)} minutes per line",
          );
        }
      } else if (project.type == ProjectType.mezuza) {
        if (comparableLinesForStats > 0 && totalDuration.inSeconds > 0) {
          double avgMinutes =
              minutesWithSeconds(totalDuration) / comparableLinesForStats;
          avgTimeText = context.l10n.pick(
            he: "${avgMinutes.toStringAsFixed(2)} דקות לשורה",
            en: "${avgMinutes.toStringAsFixed(2)} minutes per line",
          );
        }
      } else {
        if (unitsForStats > 0 && totalDuration.inSeconds > 0) {
          double avgMinutes = minutesWithSeconds(totalDuration) / unitsForStats;
          avgTimeText = context.l10n.pick(
            he: "${avgMinutes.toStringAsFixed(2)} דקות ליחידה",
            en: "${avgMinutes.toStringAsFixed(2)} minutes per unit",
          );
        }
      }

      if (project.targetDaily > 0) {
        double currentAmount = unitsForStats.toDouble();
        if (project.type == ProjectType.mezuza) {
          currentAmount =
              mezuzaLinesForStats / ProductionCalculator.linesPerMezuza;
        }

        progressPercent = currentAmount / project.targetDaily;
        double left = project.targetDaily - currentAmount;
        String leftStr =
            left % 1 == 0 ? left.toInt().toString() : left.toStringAsFixed(1);
        remainingText = left > 0
            ? context.l10n.pick(
                he: "נותרו $leftStr ליעד",
                en: "$leftStr remaining",
              )
            : context.l10n.pick(
                he: "היעד הושלם!",
                en: "Target reached!",
              );
      }
    }

    final t = SoferTokens.of(context);
    if (t.isRules) {
      return _ruledProjectEntry(
        project: project,
        outputText: outputText,
        worked: totalDuration,
        someWithoutTime: someWithoutTime,
        avgTimeText: avgTimeText,
        profit: profit,
        hourlyRate: hourlyRate,
        progressPercent: progressPercent,
        remainingText: remainingText,
      );
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              project.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildInfoRow(Icons.edit_note,
                context.l10n.pick(he: "הספק:", en: "Output:"), outputText),
            _buildInfoRow(
                Icons.timer,
                context.l10n.pick(he: "זמן עבודה:", en: "Writing time:"),
                workedLabel(totalDuration, someWithoutTime)),
            if (avgTimeText.isNotEmpty)
              _buildInfoRow(Icons.speed,
                  context.l10n.pick(he: "ממוצע:", en: "Average:"), avgTimeText),
            _buildInfoRow(
                Icons.monetization_on,
                context.l10n.pick(he: "רווח נקי:", en: "Net profit:"),
                formatMoneyExact(profit, project.currency)),
            if (hourlyRate != null)
              _buildInfoRow(
                  Icons.trending_up,
                  context.l10n.pick(he: "שכר לשעה:", en: "Hourly rate:"),
                  context.l10n.pick(
                    he: "${formatMoney(hourlyRate, project.currency)} לשעה",
                    en: "${formatMoney(hourlyRate, project.currency)} per hour",
                  )),
            const SizedBox(height: 10),
            Text(
                context.l10n
                    .pick(he: "עמידה ביעד יומי:", en: "Daily target progress:"),
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: progressPercent > 1 ? 1 : progressPercent,
              backgroundColor: SoferTokens.of(context).rule,
              color: progressPercent >= 1
                  ? SoferTokens.of(context).positive
                  : SoferTokens.of(context).accent,
              minHeight: 8,
            ),
            const SizedBox(height: 5),
            Text(
              remainingText,
              style: TextStyle(
                color: progressPercent >= 1
                    ? SoferTokens.of(context).positive
                    : SoferTokens.of(context).danger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: SoferTokens.of(context).inkMuted),
          const SizedBox(width: 8),
          Text("$label ", style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      color: SoferTokens.of(context).paper,
      // Five actions do not fit across a phone; scroll rather than overflow.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(
              context.l10n.pick(he: "סיכום חודשי", en: "Monthly summary"),
              Icons.calendar_view_month,
              _showMonthlySummary,
            ),
            _buildActionButton(
                context.l10n.pick(he: "סיכום פרויקט", en: "Project summary"),
                Icons.folder_special, () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProjectSummaryScreen(
                    projects: _projects,
                    history: _history,
                    onWorkCommitted: (nextProjects, nextHistory) async {
                      await widget.onWorkCommitted
                          ?.call(nextProjects, nextHistory);
                      if (mounted) {
                        setState(() {
                          _projects =
                              nextProjects.where((p) => !p.isDeleted).toList();
                          _history =
                              nextHistory.where((s) => !s.isDeleted).toList();
                        });
                      }
                    },
                    onEditProject: widget.onEditProject,
                    onDeleteProject: widget.onDeleteProject,
                    onProjectUpdated: widget.onProjectUpdated,
                    onHistoryUpdated: _historyUpdated,
                  ),
                ),
              );
            }),
            _buildActionButton(
                context.l10n.pick(he: "בחירת תאריך", en: "Choose date"),
                Icons.date_range,
                _pickDate),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    // A fixed width keeps the labels from running into each other now that
    // there are five actions in the row.
    return SizedBox(
      width: 86,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onTap,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              backgroundColor: SoferTokens.of(context).paper,
              foregroundColor: SoferTokens.of(context).accent,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    DateTime currentGregorian = _selectedDate;
    JewishDate jewishDate = JewishDate.fromDateTime(currentGregorian);
    bool tempViewByMonth = _viewByMonth;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            int currentYear = jewishDate.getJewishYear();
            int currentMonth = jewishDate.getJewishMonth();
            int currentDay = jewishDate.getJewishDayOfMonth();
            bool isLeap = jewishDate.isJewishLeapYear();
            int daysInMonth = jewishDate.getDaysInJewishMonth();

            List<int> years = List.generate(21, (i) => (currentYear - 10) + i);
            List<int> months;
            if (isLeap) {
              months = [7, 8, 9, 10, 11, 12, 13, 1, 2, 3, 4, 5, 6];
            } else {
              months = [7, 8, 9, 10, 11, 12, 1, 2, 3, 4, 5, 6];
            }
            List<int> days = List.generate(daysInMonth, (i) => i + 1);

            return AlertDialog(
              title: Text(context.l10n.pick(
                he: "בחר תאריך עברי",
                en: "Choose a Hebrew date",
              )),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(context.l10n.pick(
                        he: "הצג חודש שלם",
                        en: "Show full month",
                      )),
                      Switch(
                        value: tempViewByMonth,
                        onChanged: (val) =>
                            setState(() => tempViewByMonth = val),
                      ),
                    ],
                  ),
                  const Divider(),
                  DropdownButton<int>(
                    value: years.contains(currentYear) ? currentYear : years[0],
                    items: years.map((y) {
                      return DropdownMenuItem(
                          value: y,
                          child: Text(context.l10n.isEnglish
                              ? y.toString()
                              : formatHebrewYear(y)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        jewishDate.setJewishDate(val, 1, 1);
                        setState(() {});
                      }
                    },
                  ),
                  DropdownButton<int>(
                    value: months.contains(currentMonth) ? currentMonth : 1,
                    items: months.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(context.l10n.isEnglish
                            ? _englishMonthName(m, currentYear)
                            : getHebrewMonthName(m, isLeap)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        jewishDate.setJewishDate(currentYear, val, 1);
                        setState(() {});
                      }
                    },
                  ),
                  if (!tempViewByMonth)
                    DropdownButton<int>(
                      value: days.contains(currentDay) ? currentDay : 1,
                      items: days.map((d) {
                        return DropdownMenuItem(
                            value: d,
                            child: Text(context.l10n.isEnglish
                                ? d.toString()
                                : formatHebrewNumber(d)));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          jewishDate.setJewishDate(
                              currentYear, currentMonth, val);
                          setState(() {});
                        }
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    this.setState(() {
                      _viewByMonth = tempViewByMonth;
                      _selectedDate = jewishDate.getGregorianCalendar();
                    });
                    Navigator.pop(context);
                  },
                  child: Text(context.l10n.pick(he: "בחר", en: "Select")),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _englishMonthName(int month, int year) {
    final date = JewishDate()..setJewishDate(year, month, 1);
    final formatter = HebrewDateFormatter()..hebrewFormat = false;
    return formatter.format(date, pattern: 'MM');
  }

  String _getHebrewDate(DateTime date, [bool monthOnly = false]) {
    if (widget.useGregorianDates) {
      return monthOnly
          ? formatDisplayDateMonth(date, true)
          : formatDisplayDate(date, true);
    }
    final jewishDate = JewishDate.fromDateTime(date);
    final formatter = HebrewDateFormatter()
      ..hebrewFormat = !context.l10n.isEnglish;
    if (monthOnly) {
      // Manually construct month year string or use formatter and strip day
      return context.l10n.isEnglish
          ? formatter.format(jewishDate, pattern: 'MM yy')
          : "${getHebrewMonthName(jewishDate.getJewishMonth(), jewishDate.isJewishLeapYear())} ${formatHebrewYear(jewishDate.getJewishYear())}";
    }
    return formatter.format(jewishDate);
  }

  void _showMonthlySummary() => showMonthlySummary(
        context: context,
        projects: _projects,
        history: _history,
        month: _selectedDate,
        dayStart: _dayStart,
        rules: _rules,
        currency: _currency,
      );

  // --- עריכת היסטוריה ---
  /// All sessions, newest first, so a mistake from any day can be corrected
  /// without first navigating the summary to that date.
  void _showHistoryEditor() {
    showHistoryEditor(
      context: context,
      projects: _projects,
      history: _history,
      day: _selectedDate,
      dayLabel: widget.useGregorianDates
          ? formatDisplayDate(_selectedDate, true)
          : _getHebrewDate(_selectedDate),
      dayStart: _dayStart,
      useGregorianDates: widget.useGregorianDates,
      onHistoryUpdated: _historyUpdated,
    );
  }
}
