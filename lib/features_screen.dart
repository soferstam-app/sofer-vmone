import 'package:flutter/material.dart';

import 'models.dart';
import 'project_comparison_screen.dart';
import 'quote_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'plan/production_plan_screen.dart';
import 'reports/annual_report_screen.dart';
import 'reports/monthly_report_screen.dart';

/// Hub for the analysis tools.
///
/// These answer "what should I do" rather than "what did I do", so they sit
/// apart from the day-to-day summary screens rather than crowding the action
/// bar there.
class FeaturesScreen extends StatelessWidget {
  final List<Project> projects;
  final List<WorkSession> history;

  const FeaturesScreen({
    super.key,
    required this.projects,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("כלים")),
      body: ListView(
        padding: SoferTokens.of(context).isRules
            ? EdgeInsets.zero
            : const EdgeInsets.all(16),
        children: [
          if (SoferTokens.of(context).isRules) const SoferRule(strong: true),
          _tile(
            context,
            icon: Icons.leaderboard,
            title: "השוואת רווחיות",
            subtitle:
                "איזה סוג עבודה משתלם לך יותר, לפי מה שהרווחת בפועל לשעה",
            screen: ProjectComparisonScreen(
                projects: projects, history: history),
          ),
          _tile(
            context,
            icon: Icons.calendar_month,
            title: "לוח הספקים",
            subtitle:
                "לאיזה עמוד להגיע בכל יום — שבוע או חודש, להדפסה ולאקסל",
            screen: ProductionPlanScreen(projects: projects, history: history),
          ),
          _tile(
            context,
            icon: Icons.description,
            title: "דוח חודשי",
            subtitle:
                "כל יום בחודש: כמה נכתב, כמה זמן, דקות לשורה ורווח — להדפסה",
            screen:
                MonthlyReportScreen(projects: projects, history: history),
          ),
          _tile(
            context,
            icon: Icons.receipt_long,
            title: "דוח שנתי",
            subtitle:
                "הכנסות והוצאות לפי חודש, לשנת מס — לועזי, כמו שמבקשים",
            screen:
                AnnualReportScreen(projects: projects, history: history),
          ),
          _tile(
            context,
            icon: Icons.calculate,
            title: "מחשבון הצעת מחיר",
            subtitle:
                "כמה זמן ייקח, מתי יסתיים ומה לדרוש – לפי קצב הכתיבה שלך",
            screen: QuoteScreen(projects: projects, history: history),
          ),
        ],
      ),
    );
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
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => screen)),
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
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => screen)),
      ),
    );
  }
}
