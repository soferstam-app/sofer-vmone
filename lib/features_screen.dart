import 'package:flutter/material.dart';

import 'entry/entry_sheet.dart';
import 'models.dart';
import 'project_comparison_screen.dart';
import 'quote_screen.dart';
import 'orders_screen.dart';
import 'storage_service.dart';
import 'writing_journal_screen.dart';
import 'proofread/proofread_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'plan/production_plan_screen.dart';
import 'reports/annual_report_screen.dart';
import 'reports/monthly_report_screen.dart';
import 'l10n/app_localizations.dart';

/// Hub for the analysis tools.
///
/// These answer "what should I do" rather than "what did I do", so they sit
/// apart from the day-to-day summary screens rather than crowding the action
/// bar there.
class FeaturesScreen extends StatelessWidget {
  final List<Project> projects;
  final List<WorkSession> history;
  final Future<void> Function(List<WorkSession>)? onHistoryCommitted;
  final Future<void> Function(Project project)? onProjectCreated;
  final Future<void> Function(EntrySave save)? onEntrySave;

  const FeaturesScreen({
    super.key,
    required this.projects,
    required this.history,
    this.onHistoryCommitted,
    this.onProjectCreated,
    this.onEntrySave,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.pick(he: "כלים", en: "Tools"))),
      body: ListView(
        padding: SoferTokens.of(context).isRules
            ? EdgeInsets.zero
            : const EdgeInsets.all(16),
        children: [
          if (SoferTokens.of(context).isRules) const SoferRule(strong: true),
          _tile(
            context,
            icon: Icons.assignment,
            title: context.l10n.pick(he: "הזמנות", en: "Orders"),
            subtitle: context.l10n.pick(
                he: "לקוחות, התחייבויות, פריטים ואספקות",
                en: "Customers, commitments, items, and deliveries"),
            screen: OrdersScreen(projects: projects),
          ),
          _tile(
            context,
            icon: Icons.table_chart_outlined,
            title: context.l10n.pick(he: "יומן כתיבה", en: "Writing Journal"),
            subtitle: context.l10n.pick(
                he: "טבלה שבועית להזנה מרוכזת, להדפסה ול־Excel",
                en: "Weekly batch entry, printable forms, and Excel export"),
            screen: WritingJournalScreen(
              projects: projects,
              history: history,
              onProjectCreated: onProjectCreated ?? _saveProject,
              onSave: onEntrySave ?? _saveEntry,
              onHistoryCommitted: onHistoryCommitted,
            ),
          ),
          _tile(
            context,
            icon: Icons.leaderboard,
            title: context.l10n
                .pick(he: "השוואת רווחיות", en: "Profitability comparison"),
            subtitle: context.l10n.pick(
                he: "איזה סוג עבודה משתלם לך יותר, לפי מה שהרווחת בפועל לשעה",
                en: "Which type of work pays better based on your actual hourly earnings"),
            screen:
                ProjectComparisonScreen(projects: projects, history: history),
          ),
          _tile(
            context,
            icon: Icons.calendar_month,
            title: context.l10n.pick(he: "לוח הספקים", en: "Output plan"),
            subtitle: context.l10n.pick(
                he: "לאיזה עמוד להגיע בכל יום — שבוע או חודש, להדפסה ולאקסל",
                en: "The page to reach each day, by week or month, for print or Excel"),
            screen: ProductionPlanScreen(projects: projects, history: history),
          ),
          _tile(
            context,
            icon: Icons.description,
            title: context.l10n.pick(he: "דוח חודשי", en: "Monthly report"),
            subtitle: context.l10n.pick(
                he: "כל יום בחודש: כמה נכתב, כמה זמן, דקות לשורה ורווח — להדפסה",
                en: "Daily writing, time, minutes per line, and profit for a whole month"),
            screen: MonthlyReportScreen(projects: projects, history: history),
          ),
          _tile(
            context,
            icon: Icons.receipt_long,
            title: context.l10n.pick(he: "דוח שנתי", en: "Annual report"),
            subtitle: context.l10n.pick(
                he: "הכנסות והוצאות לפי חודש, לשנת מס — לועזי, כמו שמבקשים",
                en: "Income and expenses by month for a Gregorian tax year"),
            screen: AnnualReportScreen(projects: projects, history: history),
          ),
          _tile(
            context,
            icon: Icons.fact_check_outlined,
            title:
                context.l10n.pick(he: "מעקב הגהה", en: "Proofreading tracker"),
            subtitle: context.l10n.pick(
                he: "מה נשלח למגיה, מה חזר, כמה זמן זה לקח וכמה זה עלה",
                en: "What was sent for proofreading, what returned, how long it took, and its cost"),
            screen: ProofreadScreen(projects: projects),
          ),
          _tile(
            context,
            icon: Icons.calculate,
            title: context.l10n
                .pick(he: "מחשבון הצעת מחיר", en: "Quote calculator"),
            subtitle: context.l10n.pick(
                he: "כמה זמן ייקח, מתי יסתיים ומה לדרוש – לפי קצב הכתיבה שלך",
                en: "Estimate duration, completion date, and price from your writing pace"),
            screen: QuoteScreen(
              projects: projects,
              history: history,
              onProjectCreated: onProjectCreated,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProject(Project project) async {
    final storage = StorageService();
    final current = await storage.loadProjects();
    await storage.saveProjects([
      for (final item in current)
        if (item.id != project.id) item,
      project,
    ]);
  }

  Future<void> _saveEntry(EntrySave save) async {
    final storage = StorageService();
    final current = await storage.loadHistory();
    final ids = save.sessions
        .map((session) => session.entryId)
        .whereType<String>()
        .toSet();
    await storage.saveHistory([
      for (final session in current)
        if (session.entryId == null || !ids.contains(session.entryId)) session,
      ...save.sessions,
    ]);
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget screen,
  }) {
    final t = SoferTokens.of(context);

    // A contents page: numbered entries, the title in the serif, one line of
    // description, and a hairline. No avatar, no chevron, no card.
    if (t.isRules) {
      return InkWell(
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
        child: Container(
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontFamily: t.numeralFamily,
                            fontSize: 20,
                            color: t.ink)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontFamily: t.labelFamily,
                            fontSize: 13,
                            height: 1.6,
                            color: t.inkMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(icon, size: 20, color: t.inkFaint),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: SoferTokens.of(context).paper,
          child: Icon(icon, color: SoferTokens.of(context).accent),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(fontSize: 13)),
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      ),
    );
  }
}
