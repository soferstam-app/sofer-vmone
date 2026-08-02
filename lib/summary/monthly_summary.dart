import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';

import '../format.dart';
import '../logic/date_logic.dart';
import '../logic/expense_logic.dart';
import '../logic/hebrew_clock.dart';
import '../logic/hebrew_work_calendar.dart';
import '../logic/production_calculator.dart';
import '../logic/profit_calculator.dart';
import '../logic/tefillin_summary.dart';
import '../models.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../logic/currency.dart';

/// What a Hebrew month came to.
///
/// Two hundred and forty lines of it lived inside the summary screen, reading
/// that screen's fields directly, so the month's figures could only be produced
/// by opening a summary and tapping. What it needs is stated in its arguments
/// now, which is also the list of everything a month's reckoning depends on.
Future<void> showMonthlySummary({
  required BuildContext context,
  required List<Project> projects,
  required List<WorkSession> history,
  required DateTime month,
  required DayStart dayStart,
  required WorkCalendarRules rules,
  required Currency currency,
}) async {
  // Filed by working day, not by clock time, so the monthly total and the sum
  // of the days it is made of cannot disagree at a month boundary.
  final monthSessions = history
      .where((s) =>
          !s.backlogOnly &&
          DateLogic.sessionIsInMonth(s, month, dayStart))
      .toList();

  if (monthSessions.isEmpty) {
    showAppError(context, "אין נתונים לחודש זה");
    return;
  }

  Duration totalMonthTime = Duration.zero;
  // Kept apart by currency. A month's work may span commissions agreed in more
  // than one, and there is no rate here to convert with — nor should there be:
  // the rate that matters is the one on the day of each amount.
  final earned = MoneyTotal();
  final double workDays = _workDaysInJewishMonth(rules, month);

  Duration timeForLineAvg = Duration.zero;
  int totalLinesForAvg = 0;

  Duration timeForParshiyaAvg = Duration.zero;
  int totalParshiyotForAvg = 0;

  List<Widget> projectWidgets = [];

  final grouped = _byProject(monthSessions);

  grouped.forEach((projId, sessions) {
    final project = projects.firstWhere(
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
        lines += ProductionCalculator.seferLinesInSession(s);
        projTime += s.duration;
      }

      totalLinesForAvg += lines;
      timeForLineAvg += projTime;

      final int linesPerPage = ProductionCalculator.linesPerPageOf(project);
      projectText =
          "${project.name}: ${lines ~/ linesPerPage} עמודים ו-${lines % linesPerPage} שורות";

      double pages = lines / linesPerPage.toDouble();
      projectProfit = ProfitCalculator.profit(project, sessions);
      actualForGoal = project.dailyGoalInLines ? lines.toDouble() : pages;
    } else if (project.type == ProjectType.mezuza) {
      double totalMezuzot = 0;
      Duration projTime = Duration.zero;
      int linesForThisProj = 0;

      for (var s in sessions) {
        projTime += s.duration;
        linesForThisProj += ProductionCalculator.mezuzaLinesInSession(s);
      }

      totalMezuzot = linesForThisProj / ProductionCalculator.linesPerMezuza;

      totalLinesForAvg += linesForThisProj;
      timeForLineAvg += projTime;

      String displayAmount = totalMezuzot % 1 == 0
          ? totalMezuzot.toInt().toString()
          : totalMezuzot.toStringAsFixed(1);

      projectText = "${project.name}: $displayAmount מזוזות";

      projectProfit = ProfitCalculator.profit(project, sessions);
      actualForGoal = totalMezuzot;
    } else if (project.type == ProjectType.tefillin) {
      String tefillinText = TefillinSummary.describe(sessions);
      projectText = "${project.name}: $tefillinText";

      for (var s in sessions) {
        // Null means the parshiya is only partly written — its time would
        // skew the per-parshiya average, so the session is skipped entirely.
        final completed =
            ProductionCalculator.completedParshiyotInSession(s);
        if (completed != null) {
          timeForParshiyaAvg += s.duration;
          totalParshiyotForAvg += completed;
        }
      }

      int totalUnits = 0;
      for (var s in sessions) {
        totalUnits += s.amount;
      }
      projectProfit = ProfitCalculator.profit(project, sessions);
      actualForGoal = totalUnits.toDouble();
    }

    earned.addAmount(projectProfit, project.currency);

    double target = 0;
    if (project.targetMonthly > 0) {
      target = project.targetMonthly.toDouble();
    } else if (project.targetDaily > 0) {
      target = project.targetDaily * workDays;
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
            backgroundColor: SoferTokens.of(context).rule,
            color: progressPercent >= 1 ? SoferTokens.of(context).positive : SoferTokens.of(context).accent,
            minHeight: 6,
          ),
          const SizedBox(height: 2),
          Text(
            "יעד: ${actualForGoal.toStringAsFixed(1)} / ${target.toStringAsFixed(1)} ($remainingText)",
            style: TextStyle(
              fontSize: 12,
              color: remaining <= 0 ? SoferTokens.of(context).positive : SoferTokens.of(context).danger,
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

  // Monthly expenses count in full; period expenses contribute only the
  // share of their range falling in this month; project expenses are charged
  // to their projects and deliberately excluded here, so no money is counted
  // twice.
  final allExpenses = await StorageService().loadExpenses();
  final spent = ExpenseLogic.totalForMonth(month, allExpenses);

  // Net is a subtraction, and a subtraction across currencies is not one. It is
  // stated only when the month's earnings and its costs are in the same
  // currency; otherwise the two lines above already say everything true.
  final earnedOne = earned.single(currency);
  final spentOne = spent.single(currency);
  final net = (earnedOne != null &&
          spentOne != null &&
          earnedOne.currency == spentOne.currency)
      ? earnedOne - spentOne
      : null;

  if (!context.mounted) return;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("סיכום חודשי"),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("סה\"כ זמן: ${formatClock(totalMonthTime, seconds: false)}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
                "הכנסות כתיבה (חודש): ${earned.format(currency, decimals: 2)}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (totalMonthTime.inSeconds > 0 && earnedOne != null)
              Text(
                  "שכר לשעה (חודש): ${formatMoney(earnedOne.amount / (totalMonthTime.inSeconds / 3600), earnedOne.currency)}",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SoferTokens.of(context).accent)),
            Text("הוצאות (חודש): ${spent.format(currency, decimals: 2)}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (net != null)
              Text("נטו (לאחר הוצאות): ${net.format(decimals: 2)}",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: net.amount >= 0
                          ? SoferTokens.of(context).positive
                          : SoferTokens.of(context).danger))
            else
              Text("נטו: לא ניתן לחשב — החודש כולל יותר ממטבע אחד",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SoferTokens.of(context).caution)),
            const Divider(),
            SizedBox(
              height: 200,
              child: _monthlyChart(monthSessions, month, dayStart),
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

Widget _monthlyChart(
    List<WorkSession> sessions, DateTime month, DayStart dayStart) {
  Map<int, Duration> dailyTotals = {};
  int daysCount =
      DateTime(month.year, month.month + 1, 0).day;

  for (var s in sessions) {
    // The bar a session lands on is the day it was filed under; using the raw
    // timestamp would put late-night work on the wrong column.
    final day = DateLogic.workingDateOf(s, dayStart).day;
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
                              color: SoferTokens.of(context).accent,
                              child: Tooltip(
                                message: "יום $day: ${minutes.toInt()} דקות",
                                child: Container(),
                              ),
                            );
                          },
                        ),
                      Container(height: 1, color: SoferTokens.of(context).inkFaint),
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

Map<String, List<WorkSession>> _byProject(List<WorkSession> sessions) {
  final grouped = <String, List<WorkSession>>{};
  for (final session in sessions) {
    grouped.putIfAbsent(session.projectId, () => []).add(session);
  }
  return grouped;
}

/// Working days in the Hebrew month containing [date].
///
/// The month is walked from its first to its last Hebrew day, so a monthly
/// target is measured against the month the writer actually thinks in. This
/// used to count Sunday to Thursday and nothing else, which ignored every
/// festival and made Tishrei look like an ordinary month.
double _workDaysInJewishMonth(WorkCalendarRules rules, DateTime date) {
  final jd = JewishDate.fromDateTime(date);
  final year = jd.getJewishYear();
  final month = jd.getJewishMonth();

  final first = JewishCalendar.initDate(year, month, 1);
  final last = JewishCalendar.initDate(year, month, jd.getDaysInJewishMonth());

  return HebrewWorkCalendar.countWorkDays(
    first.getGregorianCalendar(),
    last.getGregorianCalendar(),
    rules,
  );
}
