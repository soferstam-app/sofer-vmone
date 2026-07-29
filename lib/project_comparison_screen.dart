import 'package:flutter/material.dart';

import 'logic/project_analytics.dart';
import 'models.dart';

/// Ranks projects by what they actually pay per hour.
///
/// Answers the question the app could not answer before: given everything the
/// writer has done, which kind of work is worth their time.
class ProjectComparisonScreen extends StatelessWidget {
  final List<Project> projects;
  final List<WorkSession> history;

  const ProjectComparisonScreen({
    super.key,
    required this.projects,
    required this.history,
  });

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final m = d.inMinutes.remainder(60);
      return m > 0 ? "${d.inHours} שע' $m דק'" : "${d.inHours} שע'";
    }
    return "${d.inMinutes} דק'";
  }

  @override
  Widget build(BuildContext context) {
    final ranked = ProjectAnalytics.rankByHourlyRate(projects, history);
    final ranked_ = ranked.where((p) => p.hasEnoughData).toList();
    final best = ranked_.isNotEmpty ? ranked_.first : null;
    final worst = ranked_.length > 1 ? ranked_.last : null;

    return Scaffold(
      appBar: AppBar(title: const Text("השוואת רווחיות"), centerTitle: true),
      body: ranked.isEmpty
          ? const Center(child: Text("אין פרויקטים להשוואה"))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (best != null && worst != null && best != worst)
                  Card(
                    color: Colors.deepPurple.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lightbulb,
                                  color: Colors.deepPurple.shade700),
                              const SizedBox(width: 8),
                              const Text("מה משתלם יותר",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "${best.project.name} מכניס לך "
                            "₪${best.profitPerHour!.toStringAsFixed(0)} לשעה, "
                            "מול ₪${worst.profitPerHour!.toStringAsFixed(0)} "
                            "ב${worst.project.name}.",
                            style: const TextStyle(fontSize: 15, height: 1.4),
                          ),
                          if (worst.profitPerHour! > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              "הפרש של פי "
                              "${(best.profitPerHour! / worst.profitPerHour!).toStringAsFixed(1)}.",
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade700),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                ...ranked.map((p) => _projectCard(context, p, best)),
                const SizedBox(height: 12),
                Text(
                  "החישוב מבוסס על זמן שנמדד בפועל. רשומות שהוזנו כהשלמת רקע "
                  "אינן נכללות, מכיוון שאין להן זמן עבודה אמיתי.",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
    );
  }

  Widget _projectCard(
      BuildContext context, ProjectPerformance p, ProjectPerformance? best) {
    final isBest = best != null && identical(p, best);

    if (!p.hasEnoughData) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: Icon(Icons.help_outline, color: Colors.grey.shade400),
          title: Text(p.project.name),
          subtitle: const Text("אין מספיק נתונים – לא נמדד זמן עבודה"),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isBest ? 3 : 1,
      shape: isBest
          ? RoundedRectangleBorder(
              side: BorderSide(color: Colors.deepPurple.shade300, width: 1.5),
              borderRadius: BorderRadius.circular(12))
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.project.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Text(
                  "₪${p.profitPerHour!.toStringAsFixed(0)}/שעה",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: isBest
                        ? Colors.green.shade700
                        : Colors.deepPurple.shade700,
                  ),
                ),
              ],
            ),
            const Divider(),
            _row("הופק:",
                "${p.units.toStringAsFixed(1)} ${p.unitNamePlural}"),
            _row("זמן עבודה:", _formatDuration(p.timeWorked)),
            if (p.timePerUnit != null)
              _row("זמן ל${p.unitName}:", _formatDuration(p.timePerUnit!)),
            _row("רווח:", "₪${p.profit.toStringAsFixed(2)}"),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );
}
