import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'logic/production_calculator.dart';
import 'logic/profit_calculator.dart';
import 'models.dart';
import 'hebrew_utils.dart';
import 'storage_service.dart';
import 'work_days_calculator.dart';

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
  bool _fridayMotzeiHalfDay = false;
  bool _useGregorianDates = false;
  String _soferName = '';
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    if (widget.projects.isNotEmpty) {
      _selectedProject = widget.projects.first;
    }
    _storage.getFridayMotzeiHalfDay().then((v) {
      if (mounted) setState(() => _fridayMotzeiHalfDay = v);
    });
    _storage.getUseGregorianDates().then((v) {
      if (mounted) setState(() => _useGregorianDates = v);
    });
    _storage.getSoferName().then((v) {
      if (mounted) setState(() => _soferName = v);
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

    String estimatedEndStr = "";
    String targetLinesPerDayStr = "";
    int remaining = 0;
    if (project.type == ProjectType.sefer) {
      int totalPages = project.totalPages ?? 245;
      final int linesPerPage = ProductionCalculator.linesPerPageOf(project);
      int totalLines = totalPages * linesPerPage;
      remaining = totalLines - totalLinesWritten;
      if (remaining > 0 && sessions.isNotEmpty) {
        DateTime first = sessions
            .map((s) => s.startTime)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        DateTime last = sessions
            .map((s) => s.endTime)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        double workDaysInPeriod =
            countWorkDays(first, last, _fridayMotzeiHalfDay);
        double linesPerWorkDay = workDaysInPeriod > 0
            ? totalLinesWritten / workDaysInPeriod
            : (project.targetDaily > 0 ? project.targetDaily.toDouble() : 10);
        if (linesPerWorkDay <= 0) linesPerWorkDay = 10;
        DateTime from = DateTime.now();
        DateTime est = estimatedCompletionDate(
          fromDate: from,
          remainingWorkUnits: remaining.toDouble(),
          workUnitsPerDay: linesPerWorkDay,
          fridayMotzeiHalfDay: _fridayMotzeiHalfDay,
        );
        estimatedEndStr = "${est.day}/${est.month}/${est.year}";
      }
      if (project.targetCompletionDate != null && remaining > 0) {
        DateTime target = project.targetCompletionDate!;
        DateTime today = DateTime.now();
        if (target.isAfter(today)) {
          double wd = countWorkDays(today, target, _fridayMotzeiHalfDay);
          if (wd > 0) {
            double perDay = remaining / wd;
            targetLinesPerDayStr =
                "${perDay.toStringAsFixed(1)} שורות ליום עבודה";
          }
        }
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
                        const SnackBar(
                          content: Text(
                              "לא נמצאה תוכנת מייל במכשיר. ניתן להעתיק את פרטי ההתקדמות ידנית."),
                          backgroundColor: Colors.red,
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
                  if (hourlyRate != null)
                    _statRow("שכר לשעה:",
                        "₪${hourlyRate.toStringAsFixed(0)} לשעה"),
                  if (avgTimeStr.isNotEmpty) _statRow("ממוצע:", avgTimeStr),
                  if (estimatedEndStr.isNotEmpty)
                    _statRow("מתי אני אמור לסיים:", estimatedEndStr),
                  if (targetLinesPerDayStr.isNotEmpty)
                    _statRow("שורות ליום שנותר (לפי תאריך יעד):",
                        targetLinesPerDayStr),
                ],
              ),
            ),
          ),
          if (project.type == ProjectType.sefer)
            _buildSeferGrid(project, sessions),
          if (project.type == ProjectType.tefillin)
            _buildTefillinGrid(project, sessions),
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

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 6,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemCount: totalPages,
        itemBuilder: (context, index) {
          int pageNum = index + 1;
          Set<int> lines = pageContent[pageNum] ?? {};
          double progress = lines.length / linesPerPage;
          if (progress > 1.0) progress = 1.0;

          return InkWell(
            onTap: () => _showSeferPageDetails(pageNum, lines, linesPerPage),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                gradient: progress > 0
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.green.shade300,
                          Colors.green.shade300,
                          Colors.white,
                          Colors.white,
                        ],
                        stops: [0.0, progress, progress, 1.0],
                      )
                    : null,
                color: progress == 0 ? Colors.white : null,
              ),
              alignment: Alignment.center,
              child: Text(
                formatHebrewNumber(pageNum),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          );
        },
      ),
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
          color: count > 0 ? Colors.deepPurple.shade100 : Colors.grey.shade200,
          border: Border.all(color: Colors.deepPurple),
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
