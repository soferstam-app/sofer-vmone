import 'hebrew_work_calendar.dart';

/// What a job would take, and what it should cost.
class QuoteEstimate {
  /// Units of work requested — pages, mezuzot or sets.
  final double units;

  /// Learned from past work of the same type.
  final Duration timePerUnit;
  final Duration totalTime;

  /// Working days, honouring Shabbat, festivals and the writer's own rules.
  final double workDays;

  /// The delivery date with its full reasoning — the Hebrew date, how many
  /// calendar days it is out, and which days were skipped on the way.
  final WorkPlan plan;

  /// Price that would achieve the requested hourly rate, materials included.
  final double suggestedPrice;
  final double pricePerUnit;

  /// The materials part of [suggestedPrice], separated out so a client can be
  /// shown what is labour and what is parchment.
  final double materials;

  const QuoteEstimate({
    required this.units,
    required this.timePerUnit,
    required this.totalTime,
    required this.workDays,
    required this.plan,
    required this.suggestedPrice,
    required this.pricePerUnit,
    required this.materials,
  });

  DateTime get estimatedCompletion => plan.completionDate;

  double get labour => suggestedPrice - materials;
}

/// Turns "how much work is this and what should I charge" into numbers,
/// using the writer's own measured pace rather than a guess.
class QuoteCalculator {
  const QuoteCalculator._();

  /// Builds an estimate.
  ///
  /// [hoursPerDay] is how long the writer actually sits and writes on a working
  /// day — not a calendar day — since that is what turns total hours into a
  /// delivery date.
  ///
  /// [expensesPerUnit] is added on top of the price needed to reach
  /// [targetHourlyRate], so materials do not quietly come out of the writer's
  /// own pay.
  ///
  /// [rules] decide which days count as writing days; they come from the same
  /// settings the project screens use, so a date quoted to a client and a date
  /// shown once the job starts cannot disagree.
  static QuoteEstimate? estimate({
    required double units,
    required Duration timePerUnit,
    required double targetHourlyRate,
    required double hoursPerDay,
    required WorkCalendarRules rules,
    double expensesPerUnit = 0,
    DateTime? startingFrom,
  }) {
    if (units <= 0 || timePerUnit <= Duration.zero) return null;
    if (hoursPerDay <= 0) return null;

    final totalSeconds = (timePerUnit.inSeconds * units).round();
    final totalTime = Duration(seconds: totalSeconds);
    final totalHours = totalSeconds / 3600;

    final workDays = totalHours / hoursPerDay;

    final plan = HebrewWorkCalendar.plan(
      from: startingFrom ?? DateTime.now(),
      workDaysNeeded: workDays,
      rules: rules,
    );
    if (plan == null) return null;

    final labour = totalHours * targetHourlyRate;
    final materials = expensesPerUnit * units;
    final price = labour + materials;

    return QuoteEstimate(
      units: units,
      timePerUnit: timePerUnit,
      totalTime: totalTime,
      workDays: workDays,
      plan: plan,
      suggestedPrice: price,
      pricePerUnit: price / units,
      materials: materials,
    );
  }

  /// Hourly rate a given price would actually yield — the inverse question,
  /// for checking an offer a client has already made.
  static double? impliedHourlyRate({
    required double totalPrice,
    required double units,
    required Duration timePerUnit,
    double expensesPerUnit = 0,
  }) {
    if (units <= 0 || timePerUnit <= Duration.zero) return null;
    final totalHours = (timePerUnit.inSeconds * units) / 3600;
    if (totalHours <= 0) return null;
    return (totalPrice - expensesPerUnit * units) / totalHours;
  }
}
