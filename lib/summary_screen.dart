import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'models.dart';
import 'project_summary_screen.dart';
import 'hebrew_utils.dart';
import 'storage_service.dart';

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

  List<WorkSession> _getSessionsForDate(DateTime date) {
    return widget.history.where((session) {
      if (_viewByMonth) {
        return session.startTime.year == date.year &&
            session.startTime.month == date.month;
      } else {
        return session.startTime.year == date.year &&
            session.startTime.month == date.month &&
            session.startTime.day == date.day;
      }
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.today_rounded,
                    color: Colors.deepPurple.shade300, size: 24),
                const SizedBox(width: 10),
                Text(
                  widget.useGregorianDates
                      ? (_viewByMonth
                          ? formatDisplayDateMonth(_selectedDate, true)
                          : formatDisplayDate(_selectedDate, true))
                      : _getHebrewDate(_selectedDate, _viewByMonth),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: dailySessions.isEmpty
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                size: 64, color: Colors.orange.shade300),
          ),
          const SizedBox(height: 20),
          Text(
            "כל זמן שהנר דולק אפשר לכתוב",
            style: TextStyle(
                fontSize: 18,
                fontStyle: FontStyle.italic,
                color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSummaryCard(Project project, List<WorkSession> sessions) {
    Duration totalDuration = Duration.zero;
    int totalLinesWritten = 0;
    int totalUnitsWritten = 0;
    int totalParshiyotForAvg = 0;
    int totalMezuzaLines = 0;

    for (var s in sessions) {
      totalDuration += s.duration;
      if (project.type == ProjectType.sefer) {
        totalLinesWritten += (s.endLine - s.startLine + 1);
      } else {
        totalUnitsWritten += s.amount;

        if (project.type == ProjectType.tefillin) {
          if (s.tefillinType == null && s.parshiya == null) {
            totalParshiyotForAvg += s.amount * 8;
          } else if ((s.tefillinType == 'head' || s.tefillinType == 'hand') &&
              s.parshiya == null) {
            totalParshiyotForAvg += s.amount * 4;
          } else {
            totalParshiyotForAvg += s.amount;
          }
        } else if (project.type == ProjectType.mezuza) {
          if (s.endLine > 0) {
            totalMezuzaLines +=
                (s.amount > 0 ? (s.amount - 1) * 22 : 0) + s.endLine;
          } else {
            totalMezuzaLines += s.amount * 22;
          }
        }
      }
    }

    String outputText = "";
    double profit = 0;
    double progressPercent = 0;
    String remainingText = "";
    String avgTimeText = "";

    if (project.type == ProjectType.sefer) {
      int linesPerPage = project.linesPerPage ?? 42;
      if (linesPerPage == 0) linesPerPage = 42;

      int pages = totalLinesWritten ~/ linesPerPage;
      int lines = totalLinesWritten % linesPerPage;

      outputText = "$pages עמודים ו-$lines שורות";

      double pagesDecimal = totalLinesWritten / linesPerPage;
      profit = pagesDecimal * (project.price - project.expenses);

      if (totalLinesWritten > 0) {
        double avgMinutes = totalDuration.inMinutes / totalLinesWritten;
        avgTimeText = "${avgMinutes.toStringAsFixed(2)} דקות לשורה";
      }

      int targetLines = project.targetDaily * linesPerPage;
      if (targetLines > 0) {
        progressPercent = totalLinesWritten / targetLines;
        int linesLeft = targetLines - totalLinesWritten;
        if (linesLeft > 0) {
          remainingText = "נותרו $linesLeft שורות ליעד";
        } else {
          remainingText = "היעד הושלם!";
        }
      }
    } else {
      if (project.type == ProjectType.mezuza) {
        double mezuzotCount = totalMezuzaLines / 22.0;
        profit = mezuzotCount * (project.price - project.expenses);
        String displayAmount = mezuzotCount % 1 == 0
            ? mezuzotCount.toInt().toString()
            : mezuzotCount.toStringAsFixed(1);
        outputText = "$displayAmount מזוזות";
      } else {
        profit = totalUnitsWritten * (project.price - project.expenses);
        outputText = _generateTefillinSummary(sessions);
      }

      if (project.type == ProjectType.tefillin) {
        if (totalParshiyotForAvg > 0) {
          double avgMinutes = totalDuration.inMinutes / totalParshiyotForAvg;
          avgTimeText = "${avgMinutes.toStringAsFixed(2)} דקות לפרשייה";
        }
      } else if (project.type == ProjectType.mezuza) {
        if (totalMezuzaLines > 0) {
          double avgMinutes = totalDuration.inMinutes / totalMezuzaLines;
          avgTimeText = "${avgMinutes.toStringAsFixed(2)} דקות לשורה";
        }
      } else {
        if (totalUnitsWritten > 0) {
          double avgMinutes = totalDuration.inMinutes / totalUnitsWritten;
          avgTimeText = "${avgMinutes.toStringAsFixed(2)} דקות ליחידה";
        }
      }

      if (project.targetDaily > 0) {
        double currentAmount = totalUnitsWritten.toDouble();
        if (project.type == ProjectType.mezuza) {
          currentAmount = totalMezuzaLines / 22.0;
        }

        progressPercent = currentAmount / project.targetDaily;
        double left = project.targetDaily - currentAmount;
        String leftStr =
            left % 1 == 0 ? left.toInt().toString() : left.toStringAsFixed(1);
        remainingText = left > 0 ? "נותרו $leftStr ליעד" : "היעד הושלם!";
      }
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
            _buildInfoRow(
                Icons.timer, "זמן עבודה:", _formatDuration(totalDuration)),
            if (avgTimeText.isNotEmpty)
              _buildInfoRow(Icons.speed, "ממוצע:", avgTimeText),
            _buildInfoRow(Icons.monetization_on, "רווח נקי:",
                "₪${profit.toStringAsFixed(2)}"),
            const SizedBox(height: 10),
            const Text("עמידה ביעד יומי:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: progressPercent > 1 ? 1 : progressPercent,
              backgroundColor: Colors.grey[200],
              color: progressPercent >= 1 ? Colors.green : Colors.blue,
              minHeight: 8,
            ),
            const SizedBox(height: 5),
            Text(
              remainingText,
              style: TextStyle(
                color:
                    remainingText.contains("הושלם") ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _generateTefillinSummary(List<WorkSession> sessions) {
    List<int> counts = List.filled(8, 0);
    List<String> partials = [];

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
        int maxLines = s.tefillinType == 'head' ? 4 : 7;
        if (s.endLine == 0 || s.endLine >= maxLines) {
          int baseIndex = s.tefillinType == 'head' ? 0 : 4;
          int pIndex = s.parshiya! - 1; // 0-3
          counts[baseIndex + pIndex] += s.amount;
        } else {
          String type = s.tefillinType == 'head' ? "ראש" : "יד";
          String pName = _getParshiyaName(s.parshiya!);
          partials.add("$pName של $type (עד שורה ${s.endLine})");
        }
      }
    }

    int pairs = counts.reduce((curr, next) => curr < next ? curr : next);
    for (int i = 0; i < 8; i++) {
      counts[i] -= pairs;
    }

    int headSets =
        counts.sublist(0, 4).reduce((curr, next) => curr < next ? curr : next);
    for (int i = 0; i < 4; i++) {
      counts[i] -= headSets;
    }

    int handSets =
        counts.sublist(4, 8).reduce((curr, next) => curr < next ? curr : next);
    for (int i = 4; i < 8; i++) {
      counts[i] -= handSets;
    }

    List<String> parts = [];
    if (pairs > 0) {
      parts.add(pairs == 1 ? "זוג תפילין אחד" : "$pairs זוגות תפילין");
    }
    if (headSets > 0) {
      parts.add("$headSets תפילין של ראש");
    }
    if (handSets > 0) {
      parts.add("$handSets תפילין של יד");
    }

    for (int i = 0; i < 8; i++) {
      if (counts[i] > 0) {
        String type = i < 4 ? "ראש" : "יד";
        String pName = _getParshiyaName((i % 4) + 1);
        if (counts[i] == 1) {
          parts.add("פרשיית $pName של $type");
        } else {
          parts.add("${counts[i]} פרשיות $pName של $type");
        }
      }
    }

    parts.addAll(partials);

    if (parts.isEmpty) return "לא נרשמה כתיבה משמעותית";
    return parts.join(", ");
  }

  String _getParshiyaName(int index) {
    switch (index) {
      case 1:
        return "קדש";
      case 2:
        return "והיה כי יביאך";
      case 3:
        return "שמע";
      case 4:
        return "והיה אם שמוע";
      default:
        return "";
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text("$label ", style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
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
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: Colors.deepPurple.shade50,
            foregroundColor: Colors.deepPurple,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
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

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}";
  }

  int _calculateWorkDaysInJewishMonth(DateTime date) {
    JewishDate jd = JewishDate.fromDateTime(date);
    int year = jd.getJewishYear();
    int month = jd.getJewishMonth();
    int daysInMonth = jd.getDaysInJewishMonth();

    int workDays = 0;
    for (int d = 1; d <= daysInMonth; d++) {
      JewishDate temp = JewishDate();
      temp.setJewishDate(year, month, d);
      DateTime gDate = temp.getGregorianCalendar();
      if (gDate.weekday == DateTime.sunday ||
          gDate.weekday <= DateTime.thursday) {
        workDays++;
      }
    }
    return workDays;
  }

  Future<void> _showMonthlySummary() async {
    final monthSessions = widget.history.where((s) {
      return s.startTime.year == _selectedDate.year &&
          s.startTime.month == _selectedDate.month;
    }).toList();

    if (monthSessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("אין נתונים לחודש זה")),
      );
      return;
    }

    Duration totalMonthTime = Duration.zero;
    double totalMonthlyProfit = 0;
    int workDays = _calculateWorkDaysInJewishMonth(_selectedDate);

    Duration timeForLineAvg = Duration.zero;
    int totalLinesForAvg = 0;

    Duration timeForParshiyaAvg = Duration.zero;
    int totalParshiyotForAvg = 0;

    List<Widget> projectWidgets = [];

    final grouped = _groupSessionsByProject(monthSessions);

    grouped.forEach((projId, sessions) {
      final project = widget.projects.firstWhere(
        (p) => p.id == projId,
        orElse: () => Project(
            id: 'u',
            name: '?',
            type: ProjectType.sefer,
            price: 0,
            expenses: 0,
            targetDaily: 0,
            targetMonthly: 0),
      );

      for (var s in sessions) {
        totalMonthTime += s.duration;
      }

      double projectProfit = 0;
      double actualForGoal = 0;
      String projectText = "";

      if (project.type == ProjectType.sefer) {
        int lines = 0;
        Duration projTime = Duration.zero;
        for (var s in sessions) {
          lines += (s.endLine - s.startLine + 1);
          projTime += s.duration;
        }

        totalLinesForAvg += lines;
        timeForLineAvg += projTime;

        int linesPerPage = project.linesPerPage ?? 42;
        if (linesPerPage == 0) linesPerPage = 42;
        projectText =
            "${project.name}: ${lines ~/ linesPerPage} עמודים ו-${lines % linesPerPage} שורות";

        double pages = lines / linesPerPage.toDouble();
        projectProfit = pages * (project.price - project.expenses);
        actualForGoal = pages;
      } else if (project.type == ProjectType.mezuza) {
        double totalMezuzot = 0;
        Duration projTime = Duration.zero;
        int linesForThisProj = 0;

        for (var s in sessions) {
          projTime += s.duration;
          int linesInSession = 0;
          if (s.endLine > 0) {
            linesInSession =
                (s.amount > 0 ? (s.amount - 1) * 22 : 0) + s.endLine;
          } else {
            linesInSession = s.amount * 22;
          }
          linesForThisProj += linesInSession;
        }

        totalMezuzot = linesForThisProj / 22.0;

        totalLinesForAvg += linesForThisProj;
        timeForLineAvg += projTime;

        String displayAmount = totalMezuzot % 1 == 0
            ? totalMezuzot.toInt().toString()
            : totalMezuzot.toStringAsFixed(1);

        projectText = "${project.name}: $displayAmount מזוזות";

        projectProfit = totalMezuzot * (project.price - project.expenses);
        actualForGoal = totalMezuzot;
      } else if (project.type == ProjectType.tefillin) {
        String tefillinText = _generateTefillinSummary(sessions);
        projectText = "${project.name}: $tefillinText";

        for (var s in sessions) {
          bool isWhole = false;
          int parshiyotCount = 0;

          if (s.tefillinType == null && s.parshiya == null) {
            isWhole = true;
            parshiyotCount = s.amount * 8;
          } else if ((s.tefillinType == 'head' || s.tefillinType == 'hand') &&
              s.parshiya == null) {
            isWhole = true;
            parshiyotCount = s.amount * 4;
          } else if (s.tefillinType != null && s.parshiya != null) {
            int max = s.tefillinType == 'head' ? 4 : 7;
            if (s.endLine == 0 || s.endLine >= max) {
              isWhole = true;
              parshiyotCount = s.amount;
            }
          }

          if (isWhole) {
            timeForParshiyaAvg += s.duration;
            totalParshiyotForAvg += parshiyotCount;
          }
        }

        int totalUnits = 0;
        for (var s in sessions) {
          totalUnits += s.amount;
        }
        projectProfit = totalUnits * (project.price - project.expenses);
        actualForGoal = totalUnits.toDouble();
      }

      totalMonthlyProfit += projectProfit;

      double target = 0;
      if (project.targetMonthly > 0) {
        target = project.targetMonthly.toDouble();
      } else if (project.targetDaily > 0) {
        target = (project.targetDaily * workDays).toDouble();
      }

      Widget? goalWidget;
      if (target > 0) {
        double progressPercent = actualForGoal / target;
        double remaining = target - actualForGoal;
        String remainingText =
            remaining <= 0 ? "הושלם!" : "נותרו ${remaining.toStringAsFixed(1)}";

        goalWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progressPercent > 1 ? 1 : progressPercent,
              backgroundColor: Colors.grey[200],
              color: progressPercent >= 1 ? Colors.green : Colors.blue,
              minHeight: 6,
            ),
            const SizedBox(height: 2),
            Text(
              "יעד: ${actualForGoal.toStringAsFixed(1)} / ${target.toStringAsFixed(1)} ($remainingText)",
              style: TextStyle(
                fontSize: 12,
                color: remaining <= 0 ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        );
      }

      projectWidgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("• $projectText"),
            if (goalWidget != null)
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: goalWidget,
              ),
          ],
        ),
      ));
    });

    double monthlyExpenses = 0;
    final allExpenses = await _storage.loadExpenses();
    for (var e in allExpenses) {
      if (e.date.year == _selectedDate.year &&
          e.date.month == _selectedDate.month) {
        monthlyExpenses += e.amount;
      }
    }
    final netAfterExpenses = totalMonthlyProfit - monthlyExpenses;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("סיכום חודשי"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("סה\"כ זמן: ${_formatDuration(totalMonthTime)}",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                  "הכנסות כתיבה (חודש): ₪${totalMonthlyProfit.toStringAsFixed(2)}",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text("הוצאות (חודש): ₪${monthlyExpenses.toStringAsFixed(2)}",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text("נטו (לאחר הוצאות): ₪${netAfterExpenses.toStringAsFixed(2)}",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color:
                          netAfterExpenses >= 0 ? Colors.green : Colors.red)),
              const Divider(),
              SizedBox(
                height: 200,
                child: _buildMonthlyChart(monthSessions),
              ),
              const Divider(),
              ...projectWidgets,
              const Divider(),
              const Text("ממוצעים:",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline)),
              if (totalLinesForAvg > 0)
                Text(
                    "ממוצע לשורה (ספר/מזוזה): ${(timeForLineAvg.inMinutes / totalLinesForAvg).toStringAsFixed(2)} דקות"),
              if (totalParshiyotForAvg > 0)
                Text(
                    "ממוצע לפרשייה (תפילין): ${(timeForParshiyaAvg.inMinutes / totalParshiyotForAvg).toStringAsFixed(2)} דקות"),
              if (totalLinesForAvg == 0 && totalParshiyotForAvg == 0)
                const Text("אין מספיק נתונים לחישוב ממוצעים"),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("סגור")),
        ],
      ),
    );
  }

  Widget _buildMonthlyChart(List<WorkSession> sessions) {
    Map<int, Duration> dailyTotals = {};
    int daysCount =
        DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;

    for (var s in sessions) {
      int day = s.startTime.day;
      dailyTotals[day] = (dailyTotals[day] ?? Duration.zero) + s.duration;
    }

    double maxMinutes = 0;
    dailyTotals.forEach((key, value) {
      if (value.inMinutes > maxMinutes) maxMinutes = value.inMinutes.toDouble();
    });

    if (maxMinutes == 0) maxMinutes = 60;

    return Column(
      children: [
        const Text("התקדמות יומית (דקות)",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              double widthPerBar = constraints.maxWidth / daysCount;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(daysCount, (index) {
                  int day = index + 1;
                  double minutes = dailyTotals[day]?.inMinutes.toDouble() ?? 0;
                  double heightFactor = minutes / maxMinutes;

                  return SizedBox(
                    width: widthPerBar,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (minutes > 0)
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: heightFactor),
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.elasticOut, // אפקט קפיצי
                            builder: (context, value, child) {
                              return Container(
                                height: constraints.maxHeight * value,
                                width: widthPerBar * 0.7,
                                color: Colors.deepPurple.shade300,
                                child: Tooltip(
                                  message: "יום $day: ${minutes.toInt()} דקות",
                                  child: Container(),
                                ),
                              );
                            },
                          ),
                        Container(height: 1, color: Colors.grey.shade300),
                        if (day % 5 == 0 || day == 1)
                          Text("$day", style: const TextStyle(fontSize: 8)),
                      ],
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- עריכת היסטוריה ---
  void _showHistoryEditor() {
    final sessions = _getSessionsForDate(_selectedDate);
    final selectedIds = <String>{};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return DraggableScrollableSheet(
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  AppBar(
                    title: const Text("עריכת רשומות"),
                    automaticallyImplyLeading: false,
                    actions: [
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  if (sessions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          if (selectedIds.isNotEmpty)
                            TextButton.icon(
                              icon: const Icon(Icons.delete_sweep),
                              label: Text("מחק נבחרים (${selectedIds.length})"),
                              onPressed: () =>
                                  _deleteSelected(ctx, selectedIds),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: sessions.isEmpty
                        ? const Center(child: Text("אין רשומות ליום זה"))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: sessions.length,
                            itemBuilder: (context, index) {
                              final s = sessions[index];
                              final p = widget.projects.firstWhere(
                                  (proj) => proj.id == s.projectId,
                                  orElse: () => Project(
                                      id: 'deleted',
                                      name: 'פרויקט נמחק',
                                      type: ProjectType.sefer,
                                      price: 0,
                                      expenses: 0,
                                      targetDaily: 0,
                                      targetMonthly: 0));
                              final isSelected = selectedIds.contains(s.id);
                              return ListTile(
                                leading: Checkbox(
                                  value: isSelected,
                                  onChanged: (v) {
                                    setSheetState(() {
                                      if (v == true) {
                                        selectedIds.add(s.id);
                                      } else {
                                        selectedIds.remove(s.id);
                                      }
                                    });
                                  },
                                ),
                                title: Text(p.name),
                                subtitle: Text(
                                    "${s.description}\n${_formatDuration(s.duration)}"),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit,
                                          color: Colors.blue),
                                      onPressed: () => _editSession(ctx, s),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () => _deleteSession(ctx, s),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _deleteSelected(BuildContext ctx, Set<String> selectedIds) {
    if (selectedIds.isEmpty) return;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("מחיקת רשומות"),
        content: Text("למחוק ${selectedIds.length} רשומות?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text("ביטול")),
          ElevatedButton(
            onPressed: () {
              final newHistory = widget.history
                  .where((s) => !selectedIds.contains(s.id))
                  .toList();
              widget.onHistoryUpdated(newHistory);
              Navigator.pop(dialogCtx);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("מחק"),
          ),
        ],
      ),
    );
  }

  void _editSession(BuildContext ctx, WorkSession s) async {
    final startCtrl = TextEditingController(
        text:
            "${s.startTime.hour.toString().padLeft(2, '0')}:${s.startTime.minute.toString().padLeft(2, '0')}");
    final endCtrl = TextEditingController(
        text:
            "${s.endTime.hour.toString().padLeft(2, '0')}:${s.endTime.minute.toString().padLeft(2, '0')}");
    final startLineCtrl = TextEditingController(text: s.startLine.toString());
    final endLineCtrl = TextEditingController(text: s.endLine.toString());
    final amountCtrl = TextEditingController(text: s.amount.toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("עריכת רשומה"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("שעת התחלה (HH:MM)"),
              TextField(controller: startCtrl),
              const SizedBox(height: 8),
              const Text("שעת סיום (HH:MM)"),
              TextField(controller: endCtrl),
              const SizedBox(height: 8),
              TextField(
                controller: startLineCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "שורה התחלה"),
              ),
              TextField(
                controller: endLineCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "שורה סיום"),
              ),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: "כמות (עמוד/מזוזה)"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text("ביטול")),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text("שמור")),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    DateTime? parseTime(String t) {
      final parts = t.split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0].trim());
      final m = int.tryParse(parts[1].trim());
      if (h == null || m == null) return null;
      return DateTime(
          s.startTime.year, s.startTime.month, s.startTime.day, h, m);
    }

    final startTime = parseTime(startCtrl.text) ?? s.startTime;
    final endTime = parseTime(endCtrl.text) ?? s.endTime;
    final startLine = int.tryParse(startLineCtrl.text) ?? s.startLine;
    final endLine = int.tryParse(endLineCtrl.text) ?? s.endLine;
    final amount = int.tryParse(amountCtrl.text) ?? s.amount;
    final updated = s.copyWith(
      startTime: startTime,
      endTime: endTime,
      startLine: startLine,
      endLine: endLine,
      amount: amount,
    );
    final newHistory =
        widget.history.map((e) => e.id == s.id ? updated : e).toList();
    widget.onHistoryUpdated(newHistory);
    if (ctx.mounted) Navigator.pop(ctx);
  }

  void _deleteSession(BuildContext ctx, WorkSession s) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("מחיקת רשומה"),
        content: const Text("האם אתה בטוח?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text("ביטול")),
          ElevatedButton(
            onPressed: () {
              final newHistory = List<WorkSession>.from(widget.history)
                ..removeWhere((item) => item.id == s.id);
              widget.onHistoryUpdated(newHistory);
              Navigator.pop(dialogCtx);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("מחק"),
          ),
        ],
      ),
    );
  }
}
