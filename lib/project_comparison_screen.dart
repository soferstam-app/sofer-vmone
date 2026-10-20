import 'package:flutter/material.dart';

import 'logic/project_analytics.dart';
import 'models.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'format.dart';
import 'l10n/app_localizations.dart';

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
                TextSpan(
                    text: context.l10n.pick(
                        he: "העבודה שמשתלמת לך יותר היא ",
                        en: "Your most profitable work is ")),
                TextSpan(
                    text: best.project.name, style: TextStyle(color: t.accent)),
                TextSpan(
                    text: context.l10n.pick(
                        he: " — ${formatMoney(best.profitPerHour!, best.project.currency)} לשעה, פי ${(best.profitPerHour! / (worst.profitPerHour == 0 ? 1 : worst.profitPerHour!)).toStringAsFixed(1)} מ${worst.project.name}.",
                        en: " — ${formatMoney(best.profitPerHour!, best.project.currency)} per hour, ${(best.profitPerHour! / (worst.profitPerHour == 0 ? 1 : worst.profitPerHour!)).toStringAsFixed(1)}× ${worst.project.name}.")),
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
            context.l10n.pick(
                he: "המידה היא ₪ לשעה — רווח בניכוי הוצאות היחידה, חלקי הזמן שנמדד. מחיר גבוה לעמוד שנכתב לאט יכול לשלם פחות ממחיר נמוך שנכתב מהר.",
                en: "The measure is earnings per hour: profit after per-unit expenses, divided by measured time. A high price for a slowly written page can pay less than a lower price written quickly."),
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

  Widget _ruledRow(
      BuildContext context, ProjectPerformance p, int rank, double top) {
    final t = SoferTokens.of(context);
    final rate = p.profitPerHour;
    final share =
        (rate == null || top <= 0) ? 0.0 : (rate / top).clamp(0.0, 1.0);

    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
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
                rate == null ? "—" : formatMoney(rate, p.project.currency),
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
                : Text(
                    context.l10n.pick(
                        he: "אין עוד מספיק נתונים", en: "Not enough data yet"),
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
                "${p.units.toStringAsFixed(1)} ${_unitPlural(context, p.project.type)} · "
                "${formatSpan(p.timeWorked, english: context.l10n.isEnglish)} · "
                "${formatMoney(p.profit, p.project.currency)}"
                "${p.timePerUnit == null ? '' : context.l10n.pick(he: ' · ${formatSpan(p.timePerUnit!)} ל${p.unitName}', en: ' · ${formatSpan(p.timePerUnit!, english: true)} per ${_unitSingular(context, p.project.type)}')}",
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
        appBar: AppBar(
            title:
                Text(context.l10n.pick(he: "מה משתלם", en: "Profitability"))),
        body: ranked.isEmpty
            ? Center(
                child: Text(context.l10n.pick(
                    he: "אין פרויקטים להשוואה", en: "No projects to compare")))
            : SoferPage(
                maxWidth: 760,
                child: _ruledTable(context, ranked, best, worst),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(context.l10n
              .pick(he: "השוואת רווחיות", en: "Profitability comparison")),
          centerTitle: true),
      body: ranked.isEmpty
          ? Center(
              child: Text(context.l10n.pick(
                  he: "אין פרויקטים להשוואה", en: "No projects to compare")))
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
                              Text(
                                  context.l10n.pick(
                                      he: "מה משתלם יותר",
                                      en: "Most profitable"),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.pick(
                                he: "${best.project.name} מכניס לך ${formatMoney(best.profitPerHour!, best.project.currency)} לשעה, מול ${formatMoney(worst.profitPerHour!, worst.project.currency)} ב${worst.project.name}.",
                                en: "${best.project.name} earns ${formatMoney(best.profitPerHour!, best.project.currency)} per hour, compared with ${formatMoney(worst.profitPerHour!, worst.project.currency)} for ${worst.project.name}."),
                            style: const TextStyle(fontSize: 15, height: 1.4),
                          ),
                          if (worst.profitPerHour! > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              context.l10n.pick(
                                  he: "הפרש של פי ${(best.profitPerHour! / worst.profitPerHour!).toStringAsFixed(1)}.",
                                  en: "A ${(best.profitPerHour! / worst.profitPerHour!).toStringAsFixed(1)}× difference."),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: SoferTokens.of(context).inkMuted),
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
                  context.l10n.pick(
                      he: "החישוב מבוסס על זמן שנמדד בפועל. רשומות שהוזנו כהשלמת רקע אינן נכללות, מכיוון שאין להן זמן עבודה אמיתי.",
                      en: "The calculation uses actual measured time. Records entered as historical completion are excluded because they do not have real work time."),
                  style: TextStyle(
                      fontSize: 12, color: SoferTokens.of(context).inkMuted),
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
          leading:
              Icon(Icons.help_outline, color: SoferTokens.of(context).inkFaint),
          title: Text(p.project.name),
          subtitle: Text(context.l10n.pick(
              he: "אין מספיק נתונים – לא נמדד זמן עבודה",
              en: "Not enough data — no work time measured")),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isBest ? 3 : 1,
      shape: isBest
          ? RoundedRectangleBorder(
              side:
                  BorderSide(color: SoferTokens.of(context).accent, width: 1.5),
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
                  context.l10n.pick(
                      he: "${formatMoney(p.profitPerHour!, p.project.currency)}/שעה",
                      en: "${formatMoney(p.profitPerHour!, p.project.currency)}/hour"),
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
            _row(context, context.l10n.pick(he: "הופק:", en: "Produced:"),
                "${p.units.toStringAsFixed(1)} ${_unitPlural(context, p.project.type)}"),
            _row(context, context.l10n.pick(he: "זמן עבודה:", en: "Work time:"),
                formatSpan(p.timeWorked, english: context.l10n.isEnglish)),
            if (p.timePerUnit != null)
              _row(
                  context,
                  context.l10n.pick(
                      he: "זמן ל${p.unitName}:",
                      en: "Time per ${_unitSingular(context, p.project.type)}:"),
                  formatSpan(p.timePerUnit!, english: context.l10n.isEnglish)),
            _row(context, context.l10n.pick(he: "רווח:", en: "Profit:"),
                formatMoneyExact(p.profit, p.project.currency)),
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
            Text(label,
                style: TextStyle(color: SoferTokens.of(context).inkMuted)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      );

  String _unitSingular(BuildContext context, ProjectType type) =>
      switch (type) {
        ProjectType.sefer => context.l10n.pick(he: 'עמוד', en: 'page'),
        ProjectType.megillah => context.l10n.pick(he: 'פרויקט', en: 'project'),
        ProjectType.mezuza => context.l10n.pick(he: 'מזוזה', en: 'Mezuzah'),
        ProjectType.tefillin => context.l10n.pick(he: 'זוג', en: 'set'),
      };

  String _unitPlural(BuildContext context, ProjectType type) => switch (type) {
        ProjectType.sefer => context.l10n.pick(he: 'עמודים', en: 'pages'),
        ProjectType.megillah =>
          context.l10n.pick(he: 'פרויקטים', en: 'projects'),
        ProjectType.mezuza => context.l10n.pick(he: 'מזוזות', en: 'Mezuzot'),
        ProjectType.tefillin => context.l10n.pick(he: 'זוגות', en: 'sets'),
      };
}
