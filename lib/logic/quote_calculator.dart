import '../work_days_calculator.dart';

/// What a job would take, and what it should cost.
class QuoteEstimate {
  /// Units of work requested — pages, mezuzot or sets.
  final double units;

  /// Learned from past work of the same type.
  final Duration timePerUnit;
  final Duration totalTime;

  /// Working days, honouring Shabbat, festivals and the half-day setting.
  final double workDays;
  final DateTime estimatedCompletion;

  /// Price that would achieve the requested hourly rate, before expenses.
  final double suggestedPrice;
  final double pricePerUnit;

  const QuoteEstimate({
    required this.units,
    required this.timePerUnit,
    required this.totalTime,
    required this.workDays,
    required this.estimatedCompletion,
    required this.suggestedPrice,
    required this.pricePerUnit,
  });
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
  static QuoteEstimate? estimate({
    required double units,
    required Duration timePerUnit,
    required double targetHourlyRate,
    required double hoursPerDay,
    required bool fridayMotzeiHalfDay,
    double expensesPerUnit = 0,
    DateTime? startingFrom,
  }) {
    if (units <= 0 || timePerUnit <= Duration.zero) return null;
    if (hoursPerDay <= 0) return null;

    final totalSeconds = (timePerUnit.inSeconds * units).round();
    final totalTime = Duration(seconds: totalSeconds);
    final totalHours = totalSeconds / 3600;

    final workDays = totalHours / hoursPerDay;
    final from = startingFrom ?? DateTime.now();

    final completion = estimatedCompletionDate(
      fromDate: from,
      remainingWorkUnits: workDays,
      // One "unit" per working day here, because workDays is already expressed
      // in days — this lets the shared calculator skip Shabbat and festivals.
      workUnitsPerDay: 1,
      fridayMotzeiHalfDay: fridayMotzeiHalfDay,
    );

    final labour = totalHours * targetHourlyRate;
    final materials = expensesPerUnit * units;
    final price = labour + materials;

    return QuoteEstimate(
      units: units,
      timePerUnit: timePerUnit,
      totalTime: totalTime,
      workDays: workDays,
      estimatedCompletion: completion,
      suggestedPrice: price,
      pricePerUnit: price / units,
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
