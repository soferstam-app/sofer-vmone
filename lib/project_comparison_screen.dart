import 'package:flutter/material.dart';

import 'logic/project_analytics.dart';
import 'models.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'format.dart';

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

  /// A results table rather than a stack of cards.
  ///
  /// The verdict is one sentence at the top, and every commission is a ruled row
  /// with a bar drawn to scale against the best-paying one — so the ranking is
  /// visible along the column rather than having to be reconstructed by reading
  /// each card's figure in turn.
  Widget _ruledTable(
    BuildContext context,
    List<ProjectPerformance> ranked,
    ProjectPerformance? best,
    ProjectPerformance? worst,
  ) {
    final t = SoferTokens.of(context);
    final top = best?.profitPerHour ?? 0;

    return ListView(
      children: [
        if (best != null && worst != null && best != worst)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: "העבודה שמשתלמת לך יותר היא "),
                TextSpan(
                    text: best.project.name,
                    style: TextStyle(color: t.accent)),
                TextSpan(
                    text: " — ${formatMoney(best.profitPerHour!)} לשעה, "
                        "פי ${(best.profitPerHour! / (worst.profitPerHour == 0 ? 1 : worst.profitPerHour!)).toStringAsFixed(1)} "
                        "מ${worst.project.name}."),
              ]),
              style: TextStyle(
                  fontFamily: t.labelFamily,
                  fontSize: 15,
                  height: 1.8,
                  color: t.inkMuted),
            ),
          ),
        const SoferRule(strong: true),
        for (var i = 0; i < ranked.length; i++)
          _ruledRow(context, ranked[i], i + 1, top),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Text(
            "המידה היא ₪ לשעה — רווח בניכוי הוצאות היחידה, חלקי הזמן שנמדד. "
            "מחיר גבוה לעמוד שנכתב לאט יכול לשלם פחות ממחיר נמוך שנכתב מהר.",
            style: TextStyle(
                fontFamily: t.labelFamily,
                fontSize: 12,
                height: 1.7,
                color: t.inkFaint),
          ),
        ),
      ],
    );
  }

  Widget _ruledRow(BuildContext context, ProjectPerformance p, int rank,
      double top) {
    final t = SoferTokens.of(context);
    final rate = p.profitPerHour;
    final share = (rate == null || top <= 0) ? 0.0 : (rate / top).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 26,
                child: Text("$rank",
                    style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 15,
                        color: t.inkFaint)),
              ),
              Expanded(
                child: Text(p.project.name,
                    style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 18,
                        color: t.ink)),
              ),
              Text(
                rate == null ? "—" : formatMoney(rate),
                style: TextStyle(
                    fontFamily: t.numeralFamily,
                    fontSize: 23,
                    color: rank == 1 && rate != null ? t.accent : t.ink),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 26),
            child: p.hasEnoughData
                ? SoferProgress(share)
                : Text("אין עוד מספיק נתונים",
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 12,
                        color: t.caution)),
          ),
          if (p.hasEnoughData) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 26),
              child: Text(
                "${p.units.toStringAsFixed(1)} ${p.unitNamePlural} · "
                "${formatSpan(p.timeWorked)} · "
                "${formatMoney(p.profit)}"
                "${p.timePerUnit == null ? '' : ' · ${formatSpan(p.timePerUnit!)} ל${p.unitName}'}",
                style: TextStyle(
                    fontFamily: t.labelFamily, fontSize: 12, color: t.inkMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ranked = ProjectAnalytics.rankByHourlyRate(projects, history);
    final ranked_ = ranked.where((p) => p.hasEnoughData).toList();
    final best = ranked_.isNotEmpty ? ranked_.first : null;
    final worst = ranked_.length > 1 ? ranked_.last : null;

    if (SoferTokens.of(context).isRules) {
      return Scaffold(
        appBar: AppBar(title: const Text("מה משתלם")),
        body: ranked.isEmpty
            ? const Center(child: Text("אין פרויקטים להשוואה"))
            : SoferPage(
                maxWidth: 760,
                child: _ruledTable(context, ranked, best, worst),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("השוואת רווחיות"), centerTitle: true),
      body: ranked.isEmpty
          ? const Center(child: Text("אין פרויקטים להשוואה"))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (best != null && worst != null && best != worst)
                  Card(
                    color: SoferTokens.of(context).paper,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.lightbulb,
                                  color: SoferTokens.of(context).accent),
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
                            "${formatMoney(best.profitPerHour!)} לשעה, "
                            "מול ${formatMoney(worst.profitPerHour!)} "
                            "ב${worst.project.name}.",
                            style: const TextStyle(fontSize: 15, height: 1.4),
                          ),
                          if (worst.profitPerHour! > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              "הפרש של פי "
                              "${(best.profitPerHour! / worst.profitPerHour!).toStringAsFixed(1)}.",
                              style: TextStyle(
                                  fontSize: 13, color: SoferTokens.of(context).inkMuted),
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
                  style: TextStyle(fontSize: 12, color: SoferTokens.of(context).inkMuted),
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
          leading: Icon(Icons.help_outline, color: SoferTokens.of(context).inkFaint),
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
              side: BorderSide(color: SoferTokens.of(context).accent, width: 1.5),
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
                  "${formatMoney(p.profitPerHour!)}/שעה",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: isBest
                        ? SoferTokens.of(context).positive
                        : SoferTokens.of(context).accent,
                  ),
                ),
              ],
            ),
            const Divider(),
            _row(context, "הופק:",
                "${p.units.toStringAsFixed(1)} ${p.unitNamePlural}"),
            _row(context, "זמן עבודה:", formatSpan(p.timeWorked)),
            if (p.timePerUnit != null)
              _row(context, "זמן ל${p.unitName}:", formatSpan(p.timePerUnit!)),
            _row(context, "רווח:", formatMoneyExact(p.profit)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: SoferTokens.of(context).inkMuted)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );
}
