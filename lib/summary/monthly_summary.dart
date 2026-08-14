import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';

import '../format.dart';
import '../logic/date_logic.dart';
import '../logic/expense_logic.dart';
import '../logic/hebrew_clock.dart';
import '../logic/hebrew_work_calendar.dart';
import '../logic/measured_work.dart';
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

    // Only what genuinely carries time. A negative duration from an imported
    // record used to subtract from the month.
    totalMonthTime += MeasuredWork.time(sessions);

    double projectProfit = 0;
    double actualForGoal = 0;
    String projectText = "";

    if (project.type == ProjectType.sefer) {
      int lines = 0;
      // Only the lines that came with time feed the average; every line feeds
      // the total. Both used to feed both, so measured minutes were divided by
      // output that had never been timed.
      int measuredLines = 0;
      Duration projTime = Duration.zero;
      for (var s in sessions) {
        final theseLines = ProductionCalculator.seferLinesInSession(s);
        lines += theseLines;
        if (MeasuredWork.countsForTime(s)) {
          measuredLines += theseLines;
          projTime += s.duration;
        }
      }

      totalLinesForAvg += measuredLines;
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
      int measuredLines = 0;

      for (var s in sessions) {
        final theseLines = ProductionCalculator.mezuzaLinesInSession(s);
        linesForThisProj += theseLines;
        if (MeasuredWork.countsForTime(s)) {
          measuredLines += theseLines;
          projTime += s.duration;
        }
      }

      totalMezuzot = linesForThisProj / ProductionCalculator.linesPerMezuza;

      totalLinesForAvg += measuredLines;
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
        if (completed != null && MeasuredWork.countsForTime(s)) {
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
      // A stated width, and the reason is not taste.
      //
      // AlertDialog sizes itself by asking its content how wide it wants to be,
      // and the daily chart inside is built with a LayoutBuilder — which cannot
      // answer that question at all. It throws "LayoutBuilder does not support
      // returning intrinsic dimensions", on every layout pass, and the dialog
      // goes round again: in a debug build that is a window that stops
      // responding the moment the summary is opened.
      //
      // A SizedBox with a fixed width answers for itself without consulting
      // what is inside it, so the question never reaches the LayoutBuilder.
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
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
                      color: SoferTokens.of(ctx).accent)),
            Text("הוצאות (חודש): ${spent.format(currency, decimals: 2)}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (net != null)
              Text("נטו (לאחר הוצאות): ${net.format(decimals: 2)}",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: net.amount >= 0
                          ? SoferTokens.of(ctx).positive
                          : SoferTokens.of(ctx).danger))
            else
              Text("נטו: לא ניתן לחשב — החודש כולל יותר ממטבע אחד",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SoferTokens.of(ctx).caution)),
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
  // Hebrew days, to match the month the summary is of. Indexed by Gregorian day
  // it drew a 31-column chart of a 29-day month, with the work landing on
  // whichever column the Gregorian date happened to fall on.
  final int daysCount = JewishDate.fromDateTime(month).getDaysInJewishMonth();

  for (var s in sessions) {
    // The bar a session lands on is the day it was filed under; using the raw
    // timestamp would put late-night work on the wrong column.
    final day = DateLogic.hebrewDayOfMonth(s, dayStart);
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
            // The bar shares its column with the baseline rule and the day
            // number, so it cannot have the whole height — a full-height bar
            // plus a one-pixel rule is a fraction of a pixel too tall, and a
            // fraction of a pixel is still an overflow.
            final barSpace =
                (constraints.maxHeight - 28).clamp(0.0, constraints.maxHeight);
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
                        Tooltip(
                          // Built once, not rebuilt on every animation frame:
                          // thirty of these re-created sixty times a second is
                          // work nobody asked for.
                          message: "יום $day: ${minutes.toInt()} דקות",
                          child: TweenAnimationBuilder<double>(
                            // Room for the bounce to bounce into. elasticOut
                            // overshoots past 1.0, so a full-height bar grew
                            // taller than the box holding it — an overflow on
                            // every bar on every frame for a second, which in a
                            // debug build is a flood of layout errors and a
                            // window that stops responding.
                            tween: Tween<double>(begin: 0, end: heightFactor),
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.elasticOut,
                            builder: (context, value, child) {
                              return Container(
                                // Clamped as well as budgeted: elasticOut
                                // overshoots past 1.0 on the way up.
                                height: barSpace * value.clamp(0.0, 1.0),
                                width: widthPerBar * 0.7,
                                color: SoferTokens.of(context).accent,
                              );
                            },
                          ),
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
