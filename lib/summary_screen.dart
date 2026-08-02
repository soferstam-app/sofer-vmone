import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'logic/date_logic.dart';
import 'logic/hebrew_clock.dart';
import 'logic/hebrew_work_calendar.dart';
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

class SummaryScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;
  final Function(List<WorkSession>) onHistoryUpdated;
  final bool useGregorianDates;

  const SummaryScreen({
    super.key,
    required this.projects,
    required this.history,
    required this.onHistoryUpdated,
    this.useGregorianDates = false,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _viewByMonth = false;
  final StorageService _storage = StorageService();

  /// Kept in sync with the setting so this screen files a session under the
  /// same working day the home screen displays.
  DayStart _dayStart = DayStart.midnight;

  /// Used to count the working days in a Hebrew month, so a monthly target is
  /// measured against the days the writer actually writes.
  WorkCalendarRules _rules = WorkCalendarRules.standard;

  @override
  void initState() {
    super.initState();
    _storage.getDayStart().then((d) {
      if (mounted) setState(() => _dayStart = d);
    });
    _storage.getWorkCalendarRules().then((r) {
      if (mounted) setState(() => _rules = r);
    });
  }

  List<WorkSession> _getSessionsForDate(DateTime date) {
    return widget.history.where((session) {
      if (session.backlogOnly) return false;
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
    final validProjectIds = widget.projects.map((p) => p.id).toSet();

    return Scaffold(
      appBar: AppBar(
        title: const Text("סיכומים"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: "עריכת רשומות",
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
                        horizontal:
                            SoferTokens.of(context).isRules ? 0 : 16),
                    children: groupedSessions.entries
                        .where((entry) => validProjectIds.contains(entry.key))
                        .map((entry) {
                      final project = widget.projects.firstWhere(
                        (p) => p.id == entry.key,
                        orElse: () => Project(
                          id: 'unknown',
                          name: 'פרויקט לא ידוע',
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
          Text(_viewByMonth ? "חודש" : "יום",
              style: TextStyle(
                  fontFamily: t.labelFamily,
                  fontSize: 12,
                  letterSpacing: 1.5,
                  color: t.inkMuted)),
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
            "כל זמן שהנר דולק אפשר לכתוב",
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
                  fontFamily: t.numeralFamily, fontSize: 17, color: t.inkMuted)),
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
          SoferStatRow("זמן עבודה", workedLabel(worked, someWithoutTime)),
          if (avgTimeText.isNotEmpty) SoferStatRow("ממוצע", avgTimeText),
          SoferStatRow("רווח נקי", formatMoneyExact(profit)),
          if (hourlyRate != null)
            SoferStatRow("שכר לשעה", formatMoney(hourlyRate),
                emphasise: true, last: !hasTarget),
          if (hasTarget) ...[
            const SizedBox(height: 14),
            SoferProgress(progressPercent),
            const SizedBox(height: 6),
            Text(
              "יעד יומי · $remainingText",
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
    Duration totalDuration = Duration.zero;
    int totalLinesWritten = 0;
    int totalMezuzaLines = 0;

    for (var s in sessions) {
      if (project.type == ProjectType.sefer) {
        totalLinesWritten += ProductionCalculator.seferLinesInSession(s);
      } else if (project.type == ProjectType.mezuza) {
        totalMezuzaLines += ProductionCalculator.mezuzaLinesInSession(s);
      }
    }
    for (var s in sessionsForStats) {
      totalDuration += s.duration;
    }

    // Plenty of sofrim record what they wrote and never how long it took. The
    // total is then true but incomplete, and saying so is the difference
    // between a figure that is partial and a figure that is wrong.
    final bool someWithoutTime =
        sessionsForStats.any((s) => !s.timeRecorded);

    int linesForStats = 0;
    int unitsForStats = 0;
    int parshiyotForStats = 0;
    int mezuzaLinesForStats = 0;
    for (var s in sessionsForStats) {
      if (project.type == ProjectType.sefer) {
        linesForStats += ProductionCalculator.seferLinesInSession(s);
      } else {
        unitsForStats += s.amount;
        if (project.type == ProjectType.tefillin) {
          parshiyotForStats += ProductionCalculator.parshiyotInSession(s);
        } else if (project.type == ProjectType.mezuza) {
          mezuzaLinesForStats += ProductionCalculator.mezuzaLinesInSession(s);
        }
      }
    }

    String outputText = "";
    double profit = 0;
    double progressPercent = 0;
    String remainingText = "";
    String avgTimeText = "";

    // The number that actually says whether the work is worth the time: a high
    // price per page written slowly can pay less than a low price written fast.
    final hourlyRate = ProfitCalculator.profitPerHour(
        project, sessionsForStats, totalDuration);

    if (project.type == ProjectType.sefer) {
      final int linesPerPage = ProductionCalculator.linesPerPageOf(project);

      int pages = totalLinesWritten ~/ linesPerPage;
      int lines = totalLinesWritten % linesPerPage;

      outputText = "$pages עמודים ו-$lines שורות";

      profit = ProfitCalculator.profit(project, sessionsForStats);

      if (linesForStats > 0 && totalDuration.inSeconds > 0) {
        double avgMinutes = totalDuration.inMinutes / linesForStats;
        avgTimeText = "${avgMinutes.toStringAsFixed(2)} דקות לשורה";
      }

      int targetLines = project.dailyGoalInLines
          ? project.targetDaily
          : (project.targetDaily * linesPerPage);
      if (targetLines > 0) {
        progressPercent = linesForStats / targetLines;
        int linesLeft = targetLines - linesForStats;
        if (linesLeft > 0) {
          remainingText = "נותרו $linesLeft שורות ליעד";
        } else {
          remainingText = "היעד הושלם!";
        }
      }
    } else {
      if (project.type == ProjectType.mezuza) {
        profit = ProfitCalculator.profit(project, sessionsForStats);
        double displayAmount =
            totalMezuzaLines / ProductionCalculator.linesPerMezuza;
        outputText = displayAmount % 1 == 0
            ? "${displayAmount.toInt()} מזוזות"
            : "${displayAmount.toStringAsFixed(1)} מזוזות";
      } else {
        profit = ProfitCalculator.profit(project, sessionsForStats);
        outputText = TefillinSummary.describe(sessions);
      }

      if (project.type == ProjectType.tefillin) {
        if (parshiyotForStats > 0 && totalDuration.inSeconds > 0) {
          double avgMinutes = totalDuration.inMinutes / parshiyotForStats;
          avgTimeText = "${avgMinutes.toStringAsFixed(2)} דקות לפרשייה";
        }
      } else if (project.type == ProjectType.mezuza) {
        if (mezuzaLinesForStats > 0 && totalDuration.inSeconds > 0) {
          double avgMinutes = totalDuration.inMinutes / mezuzaLinesForStats;
          avgTimeText = "${avgMinutes.toStringAsFixed(2)} דקות לשורה";
        }
      } else {
        if (unitsForStats > 0 && totalDuration.inSeconds > 0) {
          double avgMinutes = totalDuration.inMinutes / unitsForStats;
          avgTimeText = "${avgMinutes.toStringAsFixed(2)} דקות ליחידה";
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
        remainingText = left > 0 ? "נותרו $leftStr ליעד" : "היעד הושלם!";
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
            _buildInfoRow(Icons.edit_note, "הספק:", outputText),
            _buildInfoRow(Icons.timer, "זמן עבודה:",
                workedLabel(totalDuration, someWithoutTime)),
            if (avgTimeText.isNotEmpty)
              _buildInfoRow(Icons.speed, "ממוצע:", avgTimeText),
            _buildInfoRow(Icons.monetization_on, "רווח נקי:",
                formatMoneyExact(profit)),
            if (hourlyRate != null)
              _buildInfoRow(Icons.trending_up, "שכר לשעה:",
                  "${formatMoney(hourlyRate)} לשעה"),
            const SizedBox(height: 10),
            const Text("עמידה ביעד יומי:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: progressPercent > 1 ? 1 : progressPercent,
              backgroundColor: SoferTokens.of(context).rule,
              color: progressPercent >= 1 ? SoferTokens.of(context).positive : SoferTokens.of(context).accent,
              minHeight: 8,
            ),
            const SizedBox(height: 5),
            Text(
              remainingText,
              style: TextStyle(
                color:
                    remainingText.contains("הושלם") ? SoferTokens.of(context).positive : SoferTokens.of(context).danger,
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
            "סיכום חודשי",
            Icons.calendar_view_month,
            _showMonthlySummary,
          ),
          _buildActionButton("סיכום פרויקט", Icons.folder_special, () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProjectSummaryScreen(
                    projects: widget.projects, history: widget.history),
              ),
            );
          }),
          _buildActionButton("בחירת תאריך", Icons.date_range, _pickDate),
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
              title: const Text("בחר תאריך עברי"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("הצג חודש שלם"),
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
                          value: y, child: Text(formatHebrewYear(y)));
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
                        child: Text(getHebrewMonthName(m, isLeap)),
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
                            value: d, child: Text(formatHebrewNumber(d)));
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
                  child: const Text("ביטול"),
                ),
                ElevatedButton(
                  onPressed: () {
                    this.setState(() {
                      _viewByMonth = tempViewByMonth;
                      _selectedDate = jewishDate.getGregorianCalendar();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("בחר"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _getHebrewDate(DateTime date, [bool monthOnly = false]) {
    if (widget.useGregorianDates) {
      return monthOnly
          ? formatDisplayDateMonth(date, true)
          : formatDisplayDate(date, true);
    }
    final jewishDate = JewishDate.fromDateTime(date);
    final formatter = HebrewDateFormatter()..hebrewFormat = true;
    if (monthOnly) {
      // Manually construct month year string or use formatter and strip day
      return "${getHebrewMonthName(jewishDate.getJewishMonth(), jewishDate.isJewishLeapYear())} ${formatHebrewYear(jewishDate.getJewishYear())}";
    }
    return formatter.format(jewishDate);
  }


  void _showMonthlySummary() => showMonthlySummary(
        context: context,
        projects: widget.projects,
        history: widget.history,
        month: _selectedDate,
        dayStart: _dayStart,
        rules: _rules,
      );

  // --- עריכת היסטוריה ---
  /// All sessions, newest first, so a mistake from any day can be corrected
  /// without first navigating the summary to that date.
  void _showHistoryEditor() {
    showHistoryEditor(
      context: context,
      projects: widget.projects,
      history: widget.history,
      day: _selectedDate,
      dayLabel: widget.useGregorianDates
          ? formatDisplayDate(_selectedDate, true)
          : _getHebrewDate(_selectedDate),
      dayStart: _dayStart,
      useGregorianDates: widget.useGregorianDates,
      onHistoryUpdated: widget.onHistoryUpdated,
    );
  }
}
