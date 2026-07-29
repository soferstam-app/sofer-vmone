import 'package:flutter/material.dart';

import 'models.dart';
import 'project_comparison_screen.dart';
import 'quote_screen.dart';

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
      appBar: AppBar(title: const Text("כלים"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: Colors.deepPurple.shade50,
          child: Icon(icon, color: Colors.deepPurple),
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
