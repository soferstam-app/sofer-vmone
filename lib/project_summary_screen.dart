import 'package:flutter/material.dart';
import 'models.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.projects.isNotEmpty) {
      _selectedProject = widget.projects.first;
    }
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
                value: _selectedProject,
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

    String totalWrittenStr = "";
    double totalProfit = 0;
    String avgTimeStr = "";

    Duration totalTime = Duration.zero;
    for (var s in sessions) totalTime += s.duration;

    if (project.type == ProjectType.sefer) {
      int totalLines = 0;
      for (var s in sessions) totalLines += (s.endLine - s.startLine + 1);

      int linesPerPage = project.linesPerPage ?? 42;
      if (linesPerPage == 0) linesPerPage = 42;

      totalWrittenStr =
          "${totalLines ~/ linesPerPage} עמודים ו-${totalLines % linesPerPage} שורות";

      double pages = totalLines / linesPerPage.toDouble();
      totalProfit = pages * (project.price - project.expenses);

      if (totalLines > 0) {
        double avg = totalTime.inMinutes / totalLines;
        avgTimeStr = "${avg.toStringAsFixed(2)} דקות לשורה";
      }
    } else if (project.type == ProjectType.mezuza) {
      int totalMezuzotLines = 0;
      for (var s in sessions) {
        if (s.endLine > 0) {
          totalMezuzotLines +=
              (s.amount > 0 ? (s.amount - 1) * 22 : 0) + s.endLine;
        } else {
          totalMezuzotLines += s.amount * 22;
        }
      }
      double mezuzot = totalMezuzotLines / 22.0;
      totalWrittenStr = "${mezuzot.toStringAsFixed(1)} מזוזות";
      totalProfit = mezuzot * (project.price - project.expenses);

      if (totalMezuzotLines > 0) {
        double avg = totalTime.inMinutes / totalMezuzotLines;
        avgTimeStr = "${avg.toStringAsFixed(2)} דקות לשורה";
      }
    } else {
      int totalParshiyot = 0;
      for (var s in sessions) {
        if (s.tefillinType == null && s.parshiya == null) {
          totalParshiyot += s.amount * 8;
        } else if (s.parshiya == null) {
          totalParshiyot += s.amount * 4;
        } else {
          totalParshiyot += s.amount;
        }
      }
      totalWrittenStr = "$totalParshiyot פרשיות (סה\"כ)";
      double sets = totalParshiyot / 8.0;
      totalProfit = sets * (project.price - project.expenses);

      if (totalParshiyot > 0) {
        double avg = totalTime.inMinutes / totalParshiyot;
        avgTimeStr = "${avg.toStringAsFixed(2)} דקות לפרשייה";
      }
    }

    return SingleChildScrollView(
      child: Column(
        children: [
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
                  if (avgTimeStr.isNotEmpty) _statRow("ממוצע:", avgTimeStr),
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
    int linesPerPage = project.linesPerPage ?? 42;
    if (linesPerPage == 0) linesPerPage = 42;

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
                // שימוש בגרדיאנט למילוי חלקי (מלמעלה למטה)
                gradient: progress > 0
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.green.shade300, // צבע החלק המלא
                          Colors.green.shade300,
                          Colors.white, // צבע החלק הריק
                          Colors.white,
                        ],
                        stops: [0.0, progress, progress, 1.0],
                      )
                    : null,
                color: progress == 0 ? Colors.white : null,
              ),
              alignment: Alignment.center,
              child: Text(
                _formatHebrewNumber(pageNum),
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
        title: Text("עמוד ${_formatHebrewNumber(page)}"),
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
        for (int i = 0; i < 8; i++) counts[i] += s.amount;
      } else if (s.tefillinType == 'head' && s.parshiya == null) {
        for (int i = 0; i < 4; i++) counts[i] += s.amount;
      } else if (s.tefillinType == 'hand' && s.parshiya == null) {
        for (int i = 4; i < 8; i++) counts[i] += s.amount;
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
}
