import 'package:kosher_dart/kosher_dart.dart';

import '../models.dart';
import 'date_logic.dart';
import 'hebrew_clock.dart';
import 'hebrew_work_calendar.dart';
import 'production_calculator.dart';
import 'profit_calculator.dart';

/// A month laid out day by day: where the writing should have reached by the
/// end of each one.
///
/// Asked for by a sofer, in his own words: *someone who sets himself a page a
/// day and is holding at page ten should see, on a calendar, which page he is
/// meant to be writing on each day of the month.* And then: *on Fridays and
/// Motzei Shabbat I make up what I missed, so it should say what I have to
/// catch up to by the weekend.*
///
/// The second half falls out of the first. A plan stated as a **cumulative
/// position** — "by the end of this day, be at page fourteen" — already answers
/// what has to be made up: it is the gap between that and where he actually is.
/// A plan stated as "write two pages today" would not; it would have to be
/// added up in the writer's head, on exactly the day he is already behind.
class MonthlyPlan {
  /// The Hebrew month this covers, and each of its days in order.
  final JewishDate month;
  final List<PlannedDay> days;

  /// Units written before the month began.
  final double openingUnits;

  /// Where the plan expects the writer to be at the end of the month.
  final double closingTarget;

  const MonthlyPlan({
    required this.month,
    required this.days,
    required this.openingUnits,
    required this.closingTarget,
  });

  /// Days that ask for writing. What "a month's work" means.
  Iterable<PlannedDay> get workingDays => days.where((d) => d.weight > 0);

  /// Where the writer actually is now.
  double get actualNow => days
      .where((d) => !d.isFuture)
      .fold(openingUnits, (best, d) => d.actual ?? best);

  /// Today, if the month contains it.
  PlannedDay? get today {
    for (final d in days) {
      if (d.isToday) return d;
    }
    return null;
  }

  /// How far behind the plan the writer is, or null when level or ahead.
  ///
  /// Measured against today's line rather than the month's end, which is the
  /// only comparison that means anything mid-month: being "behind" the closing
  /// target on the second of the month is not being behind at all.
  double? get behindBy {
    final t = today;
    if (t == null) return null;
    final short = t.plannedTarget - actualNow;
    return short > 0.01 ? short : null;
  }

  /// Builds the plan for the Hebrew month containing [anyDayInMonth].
  static MonthlyPlan forMonth({
    required Project project,
    required Iterable<WorkSession> history,
    required DateTime anyDayInMonth,
    required WorkCalendarRules rules,
    required DayStart dayStart,
    DateTime? now,
  }) {
    final today = DateLogic.effectiveDate(now ?? DateTime.now(), dayStart);
    final month = JewishDate.fromDateTime(anyDayInMonth);
    final first = JewishDate.initDate(
      jewishYear: month.getJewishYear(),
      jewishMonth: month.getJewishMonth(),
      jewishDayOfMonth: 1,
    );
    final length = first.getDaysInJewishMonth();

    final mine = history
        .where((s) => s.projectId == project.id && !s.isDeleted && !s.backlogOnly)
        .toList();

    // Everything written before the month opened. The plan is a line drawn
    // from where the writer already was, not from zero.
    // Stripped to midnight. `getGregorianCalendar` carries a time, and compared
    // against a session's date — which is already normalised — every session on
    // the first of the month counted as having happened before the month began.
    final raw = first.getGregorianCalendar();
    final firstDate = DateTime(raw.year, raw.month, raw.day);
    final opening =
        _unitsUpTo(project, mine, dayStart, firstDate, inclusive: false);

    final daily = dailyUnits(project);

    // Pass one: the straight line the month was planned on.
    final drafts = <_Draft>[];
    var cumulativeWeight = 0.0;
    final walker = JewishDate.initDate(
      jewishYear: first.getJewishYear(),
      jewishMonth: first.getJewishMonth(),
      jewishDayOfMonth: 1,
    );
    for (var day = 1; day <= length; day++) {
      final date = walker.getGregorianCalendar();
      final workDay = HebrewWorkCalendar.classifyHebrewDate(
          walker.getJewishYear(),
          walker.getJewishMonth(),
          walker.getJewishDayOfMonth(),
          rules);
      cumulativeWeight += workDay.value;

      drafts.add(_Draft(
        date: DateTime(date.year, date.month, date.day),
        hebrewDay: day,
        work: workDay,
        weightSoFar: cumulativeWeight,
      ));
      if (day < length) walker.forward();
    }

    final totalWeight = cumulativeWeight;
    final closing = opening + daily * totalWeight;

    // Pass two: what actually happened, and what remains.
    final weightLeftFromToday = drafts
        .where((d) => !d.date.isBefore(today))
        .fold(0.0, (sum, d) => sum + d.work.value);

    var actualNow = opening;
    for (final d in drafts) {
      if (d.date.isAfter(today)) break;
      actualNow =
          _unitsUpTo(project, mine, dayStart, d.date, inclusive: true);
    }

    var weightFromToday = 0.0;
    final days = <PlannedDay>[];
    for (final d in drafts) {
      final isToday = d.date == today;
      final isFuture = d.date.isAfter(today);
      if (!d.date.isBefore(today)) weightFromToday += d.work.value;

      // A past day is judged against the line as it was drawn: that is what
      // makes a shortfall visible at all. A day still to come is judged against
      // what is left to do, so a writer who has fallen behind sees the making
      // up spread across the days he actually has — which is what he asked
      // for, and what a fixed line drawn in the first week cannot give him.
      final planned = opening + daily * d.weightSoFar;
      // Never negative. A writer who has already passed the whole month's
      // target has nothing left to spread, and sharing out a negative
      // remainder walked the plan backwards — telling someone holding at page
      // twenty-five to reach page twenty-four by Thursday.
      final left = closing - actualNow > 0 ? closing - actualNow : 0.0;
      final adjusted = isFuture || isToday
          ? (weightLeftFromToday <= 0
              ? actualNow + left
              : actualNow + left * (weightFromToday / weightLeftFromToday))
          : planned;

      days.add(PlannedDay(
        date: d.date,
        hebrewDay: d.hebrewDay,
        weight: d.work.value,
        closedReason: d.work.reason,
        plannedTarget: planned,
        adjustedTarget: adjusted,
        actual: isFuture
            ? null
            : _unitsUpTo(project, mine, dayStart, d.date, inclusive: true),
        isToday: isToday,
        isFuture: isFuture,
      ));
    }

    return MonthlyPlan(
      month: first,
      days: days,
      openingUnits: opening,
      closingTarget: closing,
    );
  }

  /// The daily target expressed in the commission's own units.
  ///
  /// A sefer goal may be set in lines or in pages, and the plan speaks in
  /// pages — a calendar that says "be at line 431" tells a writer nothing he
  /// can act on without dividing it himself.
  static double dailyUnits(Project project) {
    if (project.type != ProjectType.sefer) {
      return project.targetDaily.toDouble();
    }
    if (!project.dailyGoalInLines) return project.targetDaily.toDouble();
    final perPage = ProductionCalculator.linesPerPageOf(project);
    return perPage <= 0 ? 0 : project.targetDaily / perPage;
  }

  static double _unitsUpTo(
    Project project,
    List<WorkSession> sessions,
    DayStart dayStart,
    DateTime day, {
    required bool inclusive,
  }) {
    final upTo = sessions.where((s) {
      final filed = DateLogic.workingDateOf(s, dayStart);
      final d = DateTime(filed.year, filed.month, filed.day);
      return inclusive ? !d.isAfter(day) : d.isBefore(day);
    });
    return ProfitCalculator.billableUnits(project, upTo);
  }
}

/// One day of the month, and what it asks for.
class PlannedDay {
  final DateTime date;

  /// 1–30.
  final int hebrewDay;

  /// 0 for a day off, 0.5 for a half day, 1 for a full one.
  final double weight;

  /// Why it is not a full working day. Null on an ordinary one.
  final NonWorkReason? closedReason;

  /// Where the month's original line puts the writer by the end of this day.
  final double plannedTarget;

  /// Where he needs to be by the end of this day given what has actually
  /// happened. Equal to [plannedTarget] for days already gone.
  final double adjustedTarget;

  /// Where he actually was. Null for a day still to come.
  final double? actual;

  final bool isToday;
  final bool isFuture;

  const PlannedDay({
    required this.date,
    required this.hebrewDay,
    required this.weight,
    required this.closedReason,
    required this.plannedTarget,
    required this.adjustedTarget,
    required this.actual,
    required this.isToday,
    required this.isFuture,
  });

  bool get isWorkingDay => weight > 0;
  bool get isHalfDay => weight > 0 && weight < 1;

  /// Fell short of what this day asked for. Only ever true of a day gone by.
  bool get isBehind {
    final done = actual;
    return done != null && !isFuture && done + 0.01 < plannedTarget;
  }
}

class _Draft {
  final DateTime date;
  final int hebrewDay;
  final WorkDay work;
  final double weightSoFar;

  const _Draft({
    required this.date,
    required this.hebrewDay,
    required this.work,
    required this.weightSoFar,
  });
}
