import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'models.dart';
import 'project_summary_screen.dart';

class SummaryScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;
  final Function(List<WorkSession>) onHistoryUpdated;

  const SummaryScreen({
    super.key,
    required this.projects,
    required this.history,
    required this.onHistoryUpdated,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _viewByMonth = false;

  // --- לוגיקה לחישוב נתונים ---

  // סינון ההיסטוריה לפי היום הנבחר
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

  // קיבוץ סשנים לפי פרויקט
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

  // --- תצוגה ---

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
          // כותרת תאריך
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _getHebrewDate(_selectedDate, _viewByMonth),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ),

          // גוף המסך - כרטיסי סיכום או הודעה ריקה
          Expanded(
            child: dailySessions.isEmpty
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: groupedSessions.entries
                        .where((entry) => validProjectIds
                            .contains(entry.key)) // סינון פרויקטים מחוקים
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

          // כפתורים למטה
          _buildBottomButtons(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lightbulb, size: 60, color: Colors.orangeAccent),
          SizedBox(height: 20),
          Text(
            "כל זמן שהנר דולק אפשר לכתוב",
            style: TextStyle(fontSize: 18, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectSummaryCard(Project project, List<WorkSession> sessions) {
    // 1. חישובים בסיסיים
    Duration totalDuration = Duration.zero;
    int totalLinesWritten = 0; // לספר תורה
    int totalUnitsWritten = 0; // למזוזה/תפילין
    int totalParshiyotForAvg = 0; // לתפילין
    int totalMezuzaLines = 0; // למזוזה

    for (var s in sessions) {
      totalDuration += s.duration;
      if (project.type == ProjectType.sefer) {
        // חישוב שורות: סוף - התחלה + 1
        totalLinesWritten += (s.endLine - s.startLine + 1);
      } else {
        totalUnitsWritten += s.amount;

        // חישוב פרשיות לתפילין לצורך ממוצע
        if (project.type == ProjectType.tefillin) {
          if (s.tefillinType == null && s.parshiya == null) {
            // זוג שלם = 8 פרשיות
            totalParshiyotForAvg += s.amount * 8;
          } else if ((s.tefillinType == 'head' || s.tefillinType == 'hand') &&
              s.parshiya == null) {
            // סט ראש או יד = 4 פרשיות
            totalParshiyotForAvg += s.amount * 4;
          } else {
            // פרשייה בודדת
            totalParshiyotForAvg += s.amount;
          }
        } else if (project.type == ProjectType.mezuza) {
          // חישוב שורות למזוזה (22 שורות למזוזה)
          if (s.endLine > 0) {
            // אם הוזן מספר שורות ספציפי (חלקי)
            // נניח שכל היחידות המלאות (amount-1) הן 22 שורות, והאחרונה היא endLine
            totalMezuzaLines +=
                (s.amount > 0 ? (s.amount - 1) * 22 : 0) + s.endLine;
          } else {
            // מזוזות שלמות
            totalMezuzaLines += s.amount * 22;
          }
        }
      }
    }

    // 2. חישוב הספק (עמודים ושורות לספר)
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

      // חישוב רווח: (שורות שנכתבו / שורות לעמוד) * (מחיר - הוצאות)
      double pagesDecimal = totalLinesWritten / linesPerPage;
      profit = pagesDecimal * (project.price - project.expenses);

      // ממוצע דקות לשורה
      if (totalLinesWritten > 0) {
        double avgMinutes = totalDuration.inMinutes / totalLinesWritten;
        avgTimeText = "${avgMinutes.toStringAsFixed(2)} דקות לשורה";
      }

      // יעד יומי (בדרך כלל מוגדר בעמודים לספר)
      // נמיר את היעד לשורות לצורך חישוב מדויק
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
      // מזוזה / תפילין
      profit = totalUnitsWritten * (project.price - project.expenses);

      if (project.type == ProjectType.mezuza) {
        outputText = "$totalUnitsWritten מזוזות";
      } else {
        // לוגיקה מורכבת לתפילין
        outputText = _generateTefillinSummary(sessions);
      }

      // חישוב ממוצעים ויעדים למזוזה/תפילין
      // הערה: בתפילין החישוב לפי "יחידות" גולמיות עשוי להיות לא מדויק אם מערבבים סטים ופרשיות,
      // אך לצורך הסטטיסטיקה הכללית נשאיר זאת כך או נשפר בהמשך.
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
        progressPercent = totalUnitsWritten / project.targetDaily;
        int left = project.targetDaily - totalUnitsWritten;
        remainingText = left > 0 ? "נותרו $left ליעד" : "היעד הושלם!";
      }
    }

    // עיצוב הכרטיס
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // כותרת הפרויקט
            Text(
              project.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),

            // נתונים
            _buildInfoRow(Icons.edit_note, "הספק:", outputText),
            _buildInfoRow(
                Icons.timer, "זמן עבודה:", _formatDuration(totalDuration)),
            if (avgTimeText.isNotEmpty)
              _buildInfoRow(Icons.speed, "ממוצע:", avgTimeText),
            _buildInfoRow(Icons.monetization_on, "רווח נקי:",
                "₪${profit.toStringAsFixed(2)}"),

            const SizedBox(height: 10),
            // עמידה ביעד
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
    // מונים לכל אחת מ-8 הפרשיות (4 ראש, 4 יד)
    // אינדקס 0-3: ראש 1-4. אינדקס 4-7: יד 1-4.
    List<int> counts = List.filled(8, 0);
    List<String> partials = [];

    for (var s in sessions) {
      // 1. סט שלם (זוג)
      if (s.tefillinType == null && s.parshiya == null) {
        for (int i = 0; i < 8; i++) counts[i] += s.amount;
      }
      // 2. סט ראש
      else if (s.tefillinType == 'head' && s.parshiya == null) {
        for (int i = 0; i < 4; i++) counts[i] += s.amount;
      }
      // 3. סט יד
      else if (s.tefillinType == 'hand' && s.parshiya == null) {
        for (int i = 4; i < 8; i++) counts[i] += s.amount;
      }
      // 4. פרשייה בודדת
      else if (s.tefillinType != null && s.parshiya != null) {
        int maxLines = s.tefillinType == 'head' ? 4 : 7;
        // אם נכתבו כל השורות או שהמשתמש לא הזין שורות (0) - נחשב כשלם
        if (s.endLine == 0 || s.endLine >= maxLines) {
          int baseIndex = s.tefillinType == 'head' ? 0 : 4;
          int pIndex = s.parshiya! - 1; // 0-3
          counts[baseIndex + pIndex] += s.amount; // בדרך כלל 1
        } else {
          // פרשייה חלקית
          String type = s.tefillinType == 'head' ? "ראש" : "יד";
          String pName = _getParshiyaName(s.parshiya!);
          partials.add("$pName של $type (עד שורה ${s.endLine})");
        }
      }
    }

    // חישוב סטים שלמים
    // זוגות (המינימום של כל ה-8)
    int pairs = counts.reduce((curr, next) => curr < next ? curr : next);
    for (int i = 0; i < 8; i++) counts[i] -= pairs;

    // תפילין של ראש (המינימום של 4 הראשונים)
    int headSets =
        counts.sublist(0, 4).reduce((curr, next) => curr < next ? curr : next);
    for (int i = 0; i < 4; i++) counts[i] -= headSets;

    // תפילין של יד (המינימום של 4 האחרונים)
    int handSets =
        counts.sublist(4, 8).reduce((curr, next) => curr < next ? curr : next);
    for (int i = 4; i < 8; i++) counts[i] -= handSets;

    // בניית הפלט
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

    // פרשיות בודדות שנותרו
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

    // הוספת חלקיים
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
                          value: y, child: Text(_formatHebrewYear(y)));
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
                        child: Text(_getHebrewMonthName(m, isLeap)),
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
                            value: d, child: Text(_formatHebrewNumber(d)));
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
    final jewishDate = JewishDate.fromDateTime(date);
    final formatter = HebrewDateFormatter()..hebrewFormat = true;
    if (monthOnly) {
      // Manually construct month year string or use formatter and strip day
      return "${_getHebrewMonthName(jewishDate.getJewishMonth(), jewishDate.isJewishLeapYear())} ${_formatHebrewYear(jewishDate.getJewishYear())}";
    }
    return formatter.format(jewishDate);
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}";
  }

  String _formatHebrewYear(int year) {
    final formatter = HebrewDateFormatter()..hebrewFormat = true;
    final tempDate = JewishDate();
    tempDate.setJewishDate(year, 1, 1);
    return formatter.format(tempDate).split(' ').last;
  }

  String _getHebrewMonthName(int monthIndex, bool isLeap) {
    const months = [
      "ניסן",
      "אייר",
      "סיון",
      "תמוז",
      "אב",
      "אלול",
      "תשרי",
      "חשון",
      "כסלו",
      "טבת",
      "שבט"
    ];
    if (monthIndex <= 6) return months[monthIndex - 1];
    if (monthIndex >= 7 && monthIndex <= 11) return months[monthIndex - 1];
    if (isLeap) {
      if (monthIndex == 12) return "אדר א'";
      if (monthIndex == 13) return "אדר ב'";
    } else {
      if (monthIndex == 12) return "אדר";
    }
    return "";
  }

  String _formatHebrewNumber(int n) {
    if (n > 30) return n.toString();
    const ones = ["", "א", "ב", "ג", "ד", "ה", "ו", "ז", "ח", "ט"];
    if (n == 15) return "טו";
    if (n == 16) return "טז";
    if (n < 10) return ones[n];
    if (n == 10) return "י";
    if (n < 20) return "י${ones[n % 10]}";
    if (n == 20) return "כ";
    if (n < 30) return "כ${ones[n % 10]}";
    if (n == 30) return "ל";
    return n.toString();
  }

  // חישוב ימי עבודה (א-ה) בחודש העברי
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
      // ימי עבודה: ראשון (7) עד חמישי (4). שישי (5) ושבת (6) לא נחשבים.
      if (gDate.weekday == DateTime.sunday ||
          gDate.weekday <= DateTime.thursday) {
        workDays++;
      }
    }
    return workDays;
  }

  // --- לוגיקה לסיכום חודשי ---

  void _showMonthlySummary() {
    // 1. סינון לפי חודש ושנה של התאריך הנבחר
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

    // משתנים לצבירה
    Duration totalMonthTime = Duration.zero;
    double totalMonthlyProfit = 0;
    int workDays = _calculateWorkDaysInJewishMonth(_selectedDate);

    // ממוצע שורות (ספר + מזוזה)
    Duration timeForLineAvg = Duration.zero;
    int totalLinesForAvg = 0;

    // ממוצע פרשיות (תפילין)
    Duration timeForParshiyaAvg = Duration.zero;
    int totalParshiyotForAvg = 0;

    // ווידג'טים לפלט
    List<Widget> projectWidgets = [];

    // קיבוץ לפי פרויקטים לחישוב הספקים
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

      // צבירת זמן כללי
      for (var s in sessions) totalMonthTime += s.duration;

      double projectProfit = 0;
      double actualForGoal = 0; // כמות לחישוב יעד (עמודים/מזוזות/יחידות)
      String projectText = "";

      if (project.type == ProjectType.sefer) {
        int lines = 0;
        Duration projTime = Duration.zero;
        for (var s in sessions) {
          lines += (s.endLine - s.startLine + 1);
          projTime += s.duration;
        }

        // הוספה לממוצע שורות כללי
        totalLinesForAvg += lines;
        timeForLineAvg += projTime;

        int linesPerPage = project.linesPerPage ?? 42;
        if (linesPerPage == 0) linesPerPage = 42;
        projectText =
            "${project.name}: ${lines ~/ linesPerPage} עמודים ו-${lines % linesPerPage} שורות";

        // חישוב רווח ויעד (לפי עמודים)
        double pages = lines / linesPerPage.toDouble();
        projectProfit = pages * (project.price - project.expenses);
        actualForGoal = pages;
      } else if (project.type == ProjectType.mezuza) {
        double totalMezuzot = 0;
        Duration projTime = Duration.zero;
        int linesForThisProj = 0;

        for (var s in sessions) {
          projTime += s.duration;
          // חישוב שורות לממוצע
          int linesInSession = 0;
          if (s.endLine > 0) {
            // חלקי
            linesInSession =
                (s.amount > 0 ? (s.amount - 1) * 22 : 0) + s.endLine;
          } else {
            // שלם
            linesInSession = s.amount * 22;
          }
          linesForThisProj += linesInSession;
        }

        // המרה למזוזות עשרוניות (למשל 3.5)
        totalMezuzot = linesForThisProj / 22.0;

        // הוספה לממוצע שורות כללי
        totalLinesForAvg += linesForThisProj;
        timeForLineAvg += projTime;

        // עיגול יפה (אם שלם הצג כשלם, אחרת כעשרוני עם ספרה אחת)
        String displayAmount = totalMezuzot % 1 == 0
            ? totalMezuzot.toInt().toString()
            : totalMezuzot.toStringAsFixed(1);

        projectText = "${project.name}: $displayAmount מזוזות";

        // חישוב רווח ויעד (לפי מזוזות)
        projectProfit = totalMezuzot * (project.price - project.expenses);
        actualForGoal = totalMezuzot;
      } else if (project.type == ProjectType.tefillin) {
        // שימוש בפונקציה הקיימת לסיכום טקסטואלי
        String tefillinText = _generateTefillinSummary(sessions);
        projectText = "${project.name}: $tefillinText";

        // חישוב ממוצע לפרשייה (רק שלמות!)
        for (var s in sessions) {
          bool isWhole = false;
          int parshiyotCount = 0;

          if (s.tefillinType == null && s.parshiya == null) {
            // זוג = 8
            isWhole = true;
            parshiyotCount = s.amount * 8;
          } else if ((s.tefillinType == 'head' || s.tefillinType == 'hand') &&
              s.parshiya == null) {
            // סט = 4
            isWhole = true;
            parshiyotCount = s.amount * 4;
          } else if (s.tefillinType != null && s.parshiya != null) {
            // בודדת
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

        // חישוב רווח ויעד (לפי יחידות גולמיות כרגע)
        int totalUnits = 0;
        for (var s in sessions) totalUnits += s.amount;
        projectProfit = totalUnits * (project.price - project.expenses);
        actualForGoal = totalUnits.toDouble();
      }

      totalMonthlyProfit += projectProfit;

      // חישוב עמידה ביעד
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

    // בניית הדיאלוג
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
              Text("רווח נקי חודשי: ₪${totalMonthlyProfit.toStringAsFixed(2)}",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
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

  // --- עריכת היסטוריה ---
  void _showHistoryEditor() {
    // מציג את כל ההיסטוריה של היום הנבחר (או החודש אם רוצים להרחיב)
    // כרגע נציג את היום הנבחר כדי שיהיה קל להתמצא
    final sessions = _getSessionsForDate(_selectedDate);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
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
                      onPressed: () => Navigator.pop(context))
                ],
              ),
              Expanded(
                child: sessions.isEmpty
                    ? const Center(child: Text("אין רשומות ליום זה"))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final s = sessions[index];
                          final p = widget.projects
                              .firstWhere((proj) => proj.id == s.projectId,
                                  orElse: () => Project(
                                        id: 'deleted',
                                        name: 'פרויקט נמחק',
                                        type: ProjectType.sefer,
                                        price: 0,
                                        expenses: 0,
                                        targetDaily: 0,
                                        targetMonthly: 0,
                                      ));

                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text(
                                "${s.description}\n${_formatDuration(s.duration)}"),
                            isThreeLine: true,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteSession(s),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteSession(WorkSession s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מחיקת רשומה"),
        content: const Text("האם אתה בטוח?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          ElevatedButton(
            onPressed: () {
              final newHistory = List<WorkSession>.from(widget.history)
                ..removeWhere((item) => item.id == s.id);
              widget.onHistoryUpdated(newHistory);
              Navigator.pop(ctx); // סגירת דיאלוג
              Navigator.pop(
                  context); // סגירת ה-Sheet כדי לרענן (או להשתמש ב-StatefulBuilder בתוך ה-Sheet)
              _showHistoryEditor(); // פתיחה מחדש לרענון
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("מחק"),
          ),
        ],
      ),
    );
  }
}
