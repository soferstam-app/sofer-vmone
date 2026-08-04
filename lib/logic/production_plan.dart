import 'package:kosher_dart/kosher_dart.dart';

import '../models.dart';
import 'date_logic.dart';
import 'hebrew_clock.dart';
import 'hebrew_work_calendar.dart';
import 'production_calculator.dart';
import 'profit_calculator.dart';

/// A stretch of days laid out one by one: where the writing should have reached
/// by the end of each.
///
/// Asked for by a sofer, in his own words: *someone who sets himself a page a
/// day and is holding at page ten should see, on a calendar, which page he is
/// meant to be writing on each day.* And then: *on Fridays and Motzei Shabbat I
/// make up what I missed, so it should say what I have to catch up to by the
/// weekend.*
///
/// The second half falls out of the first. A plan stated as a **cumulative
/// position** — "by the end of this day, be at page fourteen" — already answers
/// what has to be made up: it is the gap between that and where he actually is.
/// A plan stated as "write two pages today" would not; it would have to be
/// added up in the writer's head, on exactly the day he is already behind.
///
/// The same engine serves a week and a month, because they are the same
/// question over a different number of days.
class ProductionPlan {
  final DateTime from;
  final DateTime to;
  final List<PlannedDay> days;

  /// Units written before the stretch began.
  final double openingUnits;

  /// Where the plan expects the writer to be at the end of it.
  final double closingTarget;

  const ProductionPlan({
    required this.from,
    required this.to,
    required this.days,
    required this.openingUnits,
    required this.closingTarget,
  });

  /// Days that ask for writing. What "a week's work" or "a month's work" means.
  Iterable<PlannedDay> get workingDays => days.where((d) => d.weight > 0);

  /// Where the writer actually is now.
  double get actualNow => days
      .where((d) => !d.isFuture)
      .fold(openingUnits, (best, d) => d.actual ?? best);

  /// Today, if the stretch contains it.
  PlannedDay? get today {
    for (final d in days) {
      if (d.isToday) return d;
    }
    return null;
  }

  /// How far behind the plan the writer is, or null when level or ahead.
  ///
  /// Measured against today's line rather than the stretch's end, which is the
  /// only comparison that means anything part way through: being "behind" the
  /// closing target on the second day is not being behind at all.
  double? get behindBy {
    final t = today;
    if (t == null) return null;
    final short = t.plannedTarget - actualNow;
    return short > 0.01 ? short : null;
  }

  /// The Hebrew month containing [anyDayInMonth].
  static ProductionPlan forMonth({
    required Project project,
    required Iterable<WorkSession> history,
    required DateTime anyDayInMonth,
    required WorkCalendarRules rules,
    required DayStart dayStart,
    Map<DateTime, double> overrides = const {},
    DateTime? now,
  }) {
    final jd = JewishDate.fromDateTime(anyDayInMonth);
    final first = JewishDate.initDate(
      jewishYear: jd.getJewishYear(),
      jewishMonth: jd.getJewishMonth(),
      jewishDayOfMonth: 1,
    );
    final last = JewishDate.initDate(
      jewishYear: jd.getJewishYear(),
      jewishMonth: jd.getJewishMonth(),
      jewishDayOfMonth: first.getDaysInJewishMonth(),
    );
    return forRange(
      project: project,
      history: history,
      from: _midnight(first.getGregorianCalendar()),
      to: _midnight(last.getGregorianCalendar()),
      rules: rules,
      dayStart: dayStart,
      overrides: overrides,
      now: now,
    );
  }

  /// The week containing [anyDayInWeek], Sunday to Shabbat.
  ///
  /// The Hebrew week begins on Sunday, and a plan that began on Monday would
  /// cut every weekend — the days this writer said he catches up on — in half.
  static ProductionPlan forWeek({
    required Project project,
    required Iterable<WorkSession> history,
    required DateTime anyDayInWeek,
    required WorkCalendarRules rules,
    required DayStart dayStart,
    Map<DateTime, double> overrides = const {},
    DateTime? now,
  }) {
    final day = _midnight(anyDayInWeek);
    // Dart counts Monday as 1; the week here starts on Sunday.
    final sunday = day.subtract(Duration(days: day.weekday % 7));
    return forRange(
      project: project,
      history: history,
      from: sunday,
      to: sunday.add(const Duration(days: 6)),
      rules: rules,
      dayStart: dayStart,
      overrides: overrides,
      now: now,
    );
  }

  /// Any stretch of days at all.
  ///
  /// [overrides] replaces the calendar's own weight for a day — 0 for "I am not
  /// writing that day", 1 for "I am, whatever the rule says". Changing one
  /// moves every day after it, which is the whole point of planning on a
  /// cumulative line rather than a fixed one.
  static ProductionPlan forRange({
    required Project project,
    required Iterable<WorkSession> history,
    required DateTime from,
    required DateTime to,
    required WorkCalendarRules rules,
    required DayStart dayStart,
    Map<DateTime, double> overrides = const {},
    DateTime? now,
  }) {
    final start = _midnight(from);
    final end = _midnight(to);
    final today = _midnight(DateLogic.effectiveDate(now ?? DateTime.now(), dayStart));

    final mine = history
        .where((s) => s.projectId == project.id && !s.isDeleted && !s.backlogOnly)
        .toList();

    // The plan is a line drawn from where the writer already was, not from zero.
    final opening = _unitsUpTo(project, mine, dayStart, start, inclusive: false);
    final daily = dailyUnits(project);

    // Pass one: the straight line the stretch was planned on.
    final drafts = <_Draft>[];
    var cumulativeWeight = 0.0;
    final length = end.difference(start).inDays + 1;
    final walker = JewishDate.fromDateTime(start);

    for (var i = 0; i < length; i++) {
      final date = start.add(Duration(days: i));
      final calendar = HebrewWorkCalendar.classifyHebrewDate(
        walker.getJewishYear(),
        walker.getJewishMonth(),
        walker.getJewishDayOfMonth(),
        rules,
      );
      // A writer's own decision beats the calendar's. He knows about the
      // wedding on Tuesday; the rules do not.
      final override = overrides[date];
      final weight = override ?? calendar.value;
      cumulativeWeight += weight;

      drafts.add(_Draft(
        date: date,
        hebrewDay: walker.getJewishDayOfMonth(),
        weight: weight,
        reason: weight > 0 ? null : (calendar.reason ?? NonWorkReason.shabbat),
        overridden: override != null && override != calendar.value,
        weightSoFar: cumulativeWeight,
      ));
      if (i < length - 1) walker.forward();
    }

    final closing = opening + daily * cumulativeWeight;

    // Pass two: what actually happened, and what is left.
    final weightLeftFromToday = drafts
        .where((d) => !d.date.isBefore(today))
        .fold(0.0, (sum, d) => sum + d.weight);

    var actualNow = opening;
    for (final d in drafts) {
      if (d.date.isAfter(today)) break;
      actualNow = _unitsUpTo(project, mine, dayStart, d.date, inclusive: true);
    }

    // Never negative: a writer already past the whole target has nothing left
    // to spread, and sharing out a negative remainder walked the plan backwards.
    final left = closing - actualNow > 0 ? closing - actualNow : 0.0;

    var weightFromToday = 0.0;
    final days = <PlannedDay>[];
    for (final d in drafts) {
      final isToday = d.date == today;
      final isFuture = d.date.isAfter(today);
      if (!d.date.isBefore(today)) weightFromToday += d.weight;

      // A past day is judged against the line as it was drawn: that is what
      // makes a shortfall visible at all. A day still to come is judged against
      // what is left to do, so a writer who has fallen behind sees the making
      // up spread across the days he actually has.
      final planned = opening + daily * d.weightSoFar;
      final adjusted = isFuture || isToday
          ? (weightLeftFromToday <= 0
              ? actualNow + left
              : actualNow + left * (weightFromToday / weightLeftFromToday))
          : planned;

      days.add(PlannedDay(
        date: d.date,
        hebrewDay: d.hebrewDay,
        weight: d.weight,
        closedReason: d.reason,
        isOverridden: d.overridden,
        plannedTarget: planned,
        adjustedTarget: adjusted,
        actual: isFuture
            ? null
            : _unitsUpTo(project, mine, dayStart, d.date, inclusive: true),
        isToday: isToday,
        isFuture: isFuture,
      ));
    }

    return ProductionPlan(
      from: start,
      to: end,
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

  /// `getGregorianCalendar` carries a time, and compared against a session's
  /// date — which is already normalised — every session on the first day of a
  /// range counted as having happened before the range began.
  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

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

/// One day of the plan, and what it asks for.
class PlannedDay {
  final DateTime date;

  /// Day of the Hebrew month, 1–30.
  final int hebrewDay;

  /// 0 for a day off, 0.5 for a half day, 1 for a full one.
  final double weight;

  /// Why it is not a full working day. Null on an ordinary one.
  final NonWorkReason? closedReason;

  /// The writer overruled the calendar for this day.
  final bool isOverridden;

  /// Where the original line puts the writer by the end of this day.
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
    this.isOverridden = false,
    required this.plannedTarget,
    required this.adjustedTarget,
    required this.actual,
    required this.isToday,
    required this.isFuture,
  });

  bool get isWorkingDay => weight > 0;
  bool get isHalfDay => weight > 0 && weight < 1;

  /// The target that is worth showing: the adjusted one where it still matters,
  /// the original where the day has already been judged against it.
  double get shownTarget => isFuture || isToday ? adjustedTarget : plannedTarget;

  /// Fell short of what this day asked for. Only ever true of a day gone by.
  bool get isBehind {
    final done = actual;
    return done != null && !isFuture && done + 0.01 < plannedTarget;
  }
}

class _Draft {
  final DateTime date;
  final int hebrewDay;
  final double weight;
  final NonWorkReason? reason;
  final bool overridden;
  final double weightSoFar;

  const _Draft({
    required this.date,
    required this.hebrewDay,
    required this.weight,
    required this.reason,
    required this.overridden,
    required this.weightSoFar,
  });
}
