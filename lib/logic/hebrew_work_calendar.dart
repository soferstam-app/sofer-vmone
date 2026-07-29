/// Hebrew-calendar working-day arithmetic — the single place that decides
/// whether a given day is available for writing, and how long a job will take.
///
/// ## Why everything here runs on the Hebrew calendar
///
/// Every day a sofer does not write is defined by the Hebrew calendar: Shabbat,
/// Yom Tov, Chol HaMoed, the fasts, the days between Yom Kippur and Sukkot, the
/// week before Pesach. None of them has a fixed Gregorian date. Asking "is
/// 12 April a working day" is not a question that can be answered; asking "is
/// 14 Nisan a working day" always can.
///
/// ## How the conversion is kept to a minimum
///
/// `JewishDate` carries the Gregorian date, the Hebrew date, the day of week
/// and the absolute day number side by side, and `JewishDate.forward()`
/// increments all four together with plain integer arithmetic — no calendar
/// conversion at all. So a walk over a year of days costs:
///
///   1 conversion in (the starting instant → Hebrew date)
///   n cheap increments
///   1 conversion out (only if a caller actually wants a `DateTime`)
///
/// The naive alternative — `JewishCalendar.fromDateTime(d)` inside the loop —
/// pays a full conversion per day, which is what the old
/// `work_days_calculator.dart` did. Results here also carry the Hebrew date of
/// the answer directly ([WorkPlan.completion]), so a screen that displays
/// Hebrew dates never converts back to Gregorian at all.
///
/// ## The day boundary
///
/// A Hebrew day starts at nightfall, which depends on where the writer is. The
/// app has no location, so a day here is the civil date — the same convention
/// the rest of the app already uses for filing a work session. This can only
/// matter for work done between nightfall and midnight on the eve of a
/// festival, and never affects a completion date, which is a whole number of
/// days out.
library;

import 'package:kosher_dart/kosher_dart.dart';

/// Why a day is not a full working day.
enum NonWorkReason {
  shabbat,
  friday,
  yomTov,
  cholHamoed,
  erevYomTov,
  fast,
  tishaBeav,
  erevTishaBeav,
  betweenYomKippurAndSukkot,
  weekBeforePesach,
  purim,
  chanukah,
  minorHoliday,
  roshChodesh;

  String get label => switch (this) {
        NonWorkReason.shabbat => 'שבת',
        NonWorkReason.friday => 'ערב שבת',
        NonWorkReason.yomTov => 'יום טוב',
        NonWorkReason.cholHamoed => 'חול המועד',
        NonWorkReason.erevYomTov => 'ערב חג',
        NonWorkReason.fast => 'צום',
        NonWorkReason.tishaBeav => 'תשעה באב',
        NonWorkReason.erevTishaBeav => 'ערב תשעה באב',
        NonWorkReason.betweenYomKippurAndSukkot => 'בין כיפור לסוכות',
        NonWorkReason.weekBeforePesach => 'השבוע שלפני פסח',
        NonWorkReason.purim => 'פורים',
        NonWorkReason.chanukah => 'חנוכה',
        NonWorkReason.minorHoliday => 'יום מיוחד',
        NonWorkReason.roshChodesh => 'ראש חודש',
      };
}

/// How much of a Friday is spent writing.
enum FridayWork {
  none,
  half,
  full;

  double get value => switch (this) {
        FridayWork.none => 0,
        FridayWork.half => 0.5,
        FridayWork.full => 1,
      };

  String get label => switch (this) {
        FridayWork.none => 'לא עובד',
        FridayWork.half => 'חצי יום',
        FridayWork.full => 'יום מלא',
      };
}

/// Which days the writer treats as time off.
///
/// Shabbat, Yom Tov and Tisha BeAv are not configurable — no writing gets done
/// on them. The rest are, because soferim genuinely differ on whether they sit
/// down during Chanukah or on Rosh Chodesh, and a wrong assumption here
/// silently distorts every delivery date the app produces.
class WorkCalendarRules {
  /// Israel keeps one day of Yom Tov, the diaspora two. This changes both the
  /// festival days themselves and where Chol HaMoed begins.
  final bool inIsrael;

  final FridayWork friday;

  /// Saturday night, after Shabbat ends, counted as half a working day.
  final bool motzeiShabbatHalfDay;

  final bool skipCholHamoed;
  final bool skipErevYomTov;

  /// The minor fasts: 17 Tammuz, Tzom Gedalya, 10 Tevet, Ta'anit Esther.
  final bool skipFasts;

  final bool skipErevTishaBeav;

  /// 11–14 Tishrei, when the sukka is being built.
  final bool skipBetweenYomKippurAndSukkot;

  /// 8–14 Nisan.
  final bool skipWeekBeforePesach;

  final bool skipPurim;
  final bool skipChanukah;

  /// Tu BiShvat, Lag BaOmer, Pesach Sheni, Tu BeAv, Purim Katan, Isru Chag.
  final bool skipMinorHolidays;

  final bool skipRoshChodesh;

  const WorkCalendarRules({
    this.inIsrael = true,
    this.friday = FridayWork.none,
    this.motzeiShabbatHalfDay = false,
    this.skipCholHamoed = true,
    this.skipErevYomTov = true,
    this.skipFasts = true,
    this.skipErevTishaBeav = true,
    this.skipBetweenYomKippurAndSukkot = true,
    this.skipWeekBeforePesach = true,
    this.skipPurim = true,
    this.skipChanukah = true,
    this.skipMinorHolidays = false,
    this.skipRoshChodesh = false,
  });

  /// The defaults, named for readability at call sites.
  static const WorkCalendarRules standard = WorkCalendarRules();

  WorkCalendarRules copyWith({
    bool? inIsrael,
    FridayWork? friday,
    bool? motzeiShabbatHalfDay,
    bool? skipCholHamoed,
    bool? skipErevYomTov,
    bool? skipFasts,
    bool? skipErevTishaBeav,
    bool? skipBetweenYomKippurAndSukkot,
    bool? skipWeekBeforePesach,
    bool? skipPurim,
    bool? skipChanukah,
    bool? skipMinorHolidays,
    bool? skipRoshChodesh,
  }) =>
      WorkCalendarRules(
        inIsrael: inIsrael ?? this.inIsrael,
        friday: friday ?? this.friday,
        motzeiShabbatHalfDay: motzeiShabbatHalfDay ?? this.motzeiShabbatHalfDay,
        skipCholHamoed: skipCholHamoed ?? this.skipCholHamoed,
        skipErevYomTov: skipErevYomTov ?? this.skipErevYomTov,
        skipFasts: skipFasts ?? this.skipFasts,
        skipErevTishaBeav: skipErevTishaBeav ?? this.skipErevTishaBeav,
        skipBetweenYomKippurAndSukkot:
            skipBetweenYomKippurAndSukkot ?? this.skipBetweenYomKippurAndSukkot,
        skipWeekBeforePesach: skipWeekBeforePesach ?? this.skipWeekBeforePesach,
        skipPurim: skipPurim ?? this.skipPurim,
        skipChanukah: skipChanukah ?? this.skipChanukah,
        skipMinorHolidays: skipMinorHolidays ?? this.skipMinorHolidays,
        skipRoshChodesh: skipRoshChodesh ?? this.skipRoshChodesh,
      );

  Map<String, dynamic> toJson() => {
        'inIsrael': inIsrael,
        'friday': friday.name,
        'motzeiShabbatHalfDay': motzeiShabbatHalfDay,
        'skipCholHamoed': skipCholHamoed,
        'skipErevYomTov': skipErevYomTov,
        'skipFasts': skipFasts,
        'skipErevTishaBeav': skipErevTishaBeav,
        'skipBetweenYomKippurAndSukkot': skipBetweenYomKippurAndSukkot,
        'skipWeekBeforePesach': skipWeekBeforePesach,
        'skipPurim': skipPurim,
        'skipChanukah': skipChanukah,
        'skipMinorHolidays': skipMinorHolidays,
        'skipRoshChodesh': skipRoshChodesh,
      };

  factory WorkCalendarRules.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) {
      final v = json[key];
      return v is bool ? v : fallback;
    }

    return WorkCalendarRules(
      inIsrael: flag('inIsrael', true),
      friday: FridayWork.values.firstWhere(
        (f) => f.name == json['friday'],
        orElse: () => FridayWork.none,
      ),
      motzeiShabbatHalfDay: flag('motzeiShabbatHalfDay', false),
      skipCholHamoed: flag('skipCholHamoed', true),
      skipErevYomTov: flag('skipErevYomTov', true),
      skipFasts: flag('skipFasts', true),
      skipErevTishaBeav: flag('skipErevTishaBeav', true),
      skipBetweenYomKippurAndSukkot: flag('skipBetweenYomKippurAndSukkot', true),
      skipWeekBeforePesach: flag('skipWeekBeforePesach', true),
      skipPurim: flag('skipPurim', true),
      skipChanukah: flag('skipChanukah', true),
      skipMinorHolidays: flag('skipMinorHolidays', false),
      skipRoshChodesh: flag('skipRoshChodesh', false),
    );
  }
}

/// One day, classified.
class WorkDay {
  /// 0 for a day off, 1 for a full day, 0.5 for a half day.
  final double value;

  /// Null on an ordinary full working day.
  final NonWorkReason? reason;

  const WorkDay(this.value, this.reason);

  bool get isOff => value == 0;
}

/// The outcome of planning a piece of work.
class WorkPlan {
  /// Hebrew date the work finishes on. Kept as a `JewishDate` so a screen that
  /// shows Hebrew dates never has to convert anything.
  final JewishDate completion;

  /// The same day as a `DateTime`, for storage and for Gregorian display.
  final DateTime completionDate;

  /// Days on the wall calendar from the start until completion, inclusive.
  final int calendarDays;

  /// Working days the job actually needs — a half day counts as a half.
  final double workDaysNeeded;

  /// How many days were lost to each reason along the way, so the app can say
  /// *why* a two-week job lands a month out.
  final Map<NonWorkReason, int> skipped;

  const WorkPlan({
    required this.completion,
    required this.completionDate,
    required this.calendarDays,
    required this.workDaysNeeded,
    required this.skipped,
  });

  int get skippedTotal => skipped.values.fold(0, (sum, count) => sum + count);

  /// Reasons ordered by how much time each one cost, for a short summary line.
  List<MapEntry<NonWorkReason, int>> get skippedByImpact =>
      skipped.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Working-day arithmetic on the Hebrew calendar.
class HebrewWorkCalendar {
  const HebrewWorkCalendar._();

  /// A job that never finishes must not hang the app. Twenty years is far
  /// beyond any real sefer Torah and still cheap to walk.
  static const int _maxDays = 366 * 20;

  /// Positions a `JewishCalendar` on the Hebrew day containing [moment].
  ///
  /// This is the one conversion into Hebrew space; everything downstream steps
  /// forward from here without converting again.
  static JewishCalendar hebrewDayOf(DateTime moment, WorkCalendarRules rules) {
    final jc = JewishCalendar.fromDateTime(
        DateTime(moment.year, moment.month, moment.day));
    jc.inIsrael = rules.inIsrael;
    return jc;
  }

  /// Classifies a Hebrew date given directly, without a Gregorian date ever
  /// entering into it.
  ///
  /// The rules are all stated in Hebrew dates — 8 Nisan, 11 Tishrei, 9 Av — so
  /// this is the form in which they can be checked.
  static WorkDay classifyHebrewDate(
    int jewishYear,
    int jewishMonth,
    int jewishDayOfMonth,
    WorkCalendarRules rules,
  ) =>
      classify(
        JewishCalendar.initDate(jewishYear, jewishMonth, jewishDayOfMonth,
            inIsrael: rules.inIsrael),
        rules,
      );

  /// Classifies the day [jc] is currently positioned on.
  ///
  /// The festival reasons are settled first, and only then the weekday. That
  /// order matters: a Friday that is also Chol HaMoed has to be off even for a
  /// writer who works full Fridays, and a Saturday night that is still Yom Tov
  /// must not be credited as half a day.
  static WorkDay classify(JewishCalendar jc, WorkCalendarRules rules) {
    final festival = _festivalReason(jc, rules);
    if (festival != null) return WorkDay(0, festival);

    final dayOfWeek = jc.getDayOfWeek();

    if (dayOfWeek == JewishDate.saturday) {
      return rules.motzeiShabbatHalfDay
          ? const WorkDay(0.5, null)
          : const WorkDay(0, NonWorkReason.shabbat);
    }

    if (dayOfWeek == JewishDate.friday) {
      return WorkDay(
        rules.friday.value,
        rules.friday == FridayWork.full ? null : NonWorkReason.friday,
      );
    }

    return const WorkDay(1, null);
  }

  /// The Hebrew-calendar reason this day is off, or null if there is none.
  ///
  /// Tested in order of weight, so Yom Kippur is reported as Yom Tov rather
  /// than as a fast, and Erev Pesach as an eve rather than as part of the week
  /// before Pesach. The day is off either way; the label should name the
  /// strongest reason.
  static NonWorkReason? _festivalReason(
      JewishCalendar jc, WorkCalendarRules rules) {
    final month = jc.getJewishMonth();
    final day = jc.getJewishDayOfMonth();
    final index = jc.getYomTovIndex();

    if (_isYomTovAssurBemelacha(index)) return NonWorkReason.yomTov;
    if (index == JewishCalendar.TISHA_BEAV) return NonWorkReason.tishaBeav;

    if (rules.skipFasts && _isMinorFast(index)) return NonWorkReason.fast;

    if (rules.skipErevTishaBeav &&
        _isErevTishaBeav(month, day, jc.getDayOfWeek())) {
      return NonWorkReason.erevTishaBeav;
    }

    if (rules.skipErevYomTov && _isErevYomTov(index, day)) {
      return NonWorkReason.erevYomTov;
    }

    if (rules.skipCholHamoed &&
        (index == JewishCalendar.CHOL_HAMOED_PESACH ||
            index == JewishCalendar.CHOL_HAMOED_SUCCOS ||
            index == JewishCalendar.HOSHANA_RABBA)) {
      return NonWorkReason.cholHamoed;
    }

    if (rules.skipBetweenYomKippurAndSukkot &&
        month == JewishDate.TISHREI &&
        day >= 11 &&
        day <= 14) {
      return NonWorkReason.betweenYomKippurAndSukkot;
    }

    if (rules.skipWeekBeforePesach &&
        month == JewishDate.NISSAN &&
        day >= 8 &&
        day <= 14) {
      return NonWorkReason.weekBeforePesach;
    }

    if (rules.skipPurim &&
        (index == JewishCalendar.PURIM ||
            index == JewishCalendar.SHUSHAN_PURIM)) {
      return NonWorkReason.purim;
    }

    if (rules.skipChanukah && index == JewishCalendar.CHANUKAH) {
      return NonWorkReason.chanukah;
    }

    if (rules.skipMinorHolidays &&
        (_isMinorHoliday(index) || _isIsruChag(month, day, rules.inIsrael))) {
      return NonWorkReason.minorHoliday;
    }

    if (rules.skipRoshChodesh && jc.isRoshChodesh()) {
      return NonWorkReason.roshChodesh;
    }

    return null;
  }

  /// Working days between [from] and [to], both inclusive.
  ///
  /// Used to turn "he wrote 300 lines between these two dates" into a daily
  /// pace that is not diluted by the Shabbatot and festivals in between.
  static double countWorkDays(
    DateTime from,
    DateTime to,
    WorkCalendarRules rules,
  ) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return 0;

    final days = end.difference(start).inDays + 1;
    final jc = hebrewDayOf(start, rules);

    var total = 0.0;
    for (var i = 0; i < days; i++) {
      total += classify(jc, rules).value;
      if (i < days - 1) jc.forward();
    }
    return total;
  }

  /// The first day from [from] onwards on which any writing gets done.
  static DateTime nextWorkDay(DateTime from, WorkCalendarRules rules) {
    final jc = hebrewDayOf(from, rules);
    for (var i = 0; i < _maxDays; i++) {
      if (!classify(jc, rules).isOff) return jc.getGregorianCalendar();
      jc.forward();
    }
    return DateTime(from.year, from.month, from.day);
  }

  /// When [workDaysNeeded] days of writing, starting from [from], will be done.
  ///
  /// Returns null when there is nothing to do, or when the rules leave no
  /// working days at all — better a blank than an invented date.
  static WorkPlan? plan({
    required DateTime from,
    required double workDaysNeeded,
    required WorkCalendarRules rules,
  }) {
    if (workDaysNeeded <= 0 ||
        workDaysNeeded.isNaN ||
        workDaysNeeded.isInfinite) {
      return null;
    }

    final jc = hebrewDayOf(from, rules);
    final skipped = <NonWorkReason, int>{};

    var done = 0.0;
    for (var elapsed = 0; elapsed < _maxDays; elapsed++) {
      final today = classify(jc, rules);
      if (today.isOff) {
        final reason = today.reason;
        if (reason != null) skipped[reason] = (skipped[reason] ?? 0) + 1;
      } else {
        done += today.value;
        // Rounding guard: accumulated halves must not drift a job one extra
        // day out on the final step.
        if (done >= workDaysNeeded - 1e-9) {
          return WorkPlan(
            completion: jc.clone(),
            completionDate: jc.getGregorianCalendar(),
            calendarDays: elapsed + 1,
            workDaysNeeded: workDaysNeeded,
            skipped: skipped,
          );
        }
      }
      jc.forward();
    }
    return null;
  }

  /// Every non-working day between two dates, for a "why is it so far out"
  /// breakdown or a calendar strip.
  static List<({DateTime date, JewishDate hebrew, NonWorkReason reason})> daysOff(
    DateTime from,
    DateTime to,
    WorkCalendarRules rules,
  ) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return const [];

    final days = end.difference(start).inDays + 1;
    final jc = hebrewDayOf(start, rules);
    final result = <({DateTime date, JewishDate hebrew, NonWorkReason reason})>[];

    for (var i = 0; i < days; i++) {
      final classified = classify(jc, rules);
      final reason = classified.reason;
      if (classified.isOff && reason != null) {
        result.add((
          date: jc.getGregorianCalendar(),
          hebrew: jc.clone(),
          reason: reason,
        ));
      }
      if (i < days - 1) jc.forward();
    }
    return result;
  }

  // ---------------------------------------------------------------------
  // Day tests. Each one reads the Hebrew month, day and weekday already held
  // on the object, so none of them costs a calendar conversion.
  // ---------------------------------------------------------------------

  static bool _isYomTovAssurBemelacha(int index) =>
      index == JewishCalendar.PESACH ||
      index == JewishCalendar.SHAVUOS ||
      index == JewishCalendar.SUCCOS ||
      index == JewishCalendar.SHEMINI_ATZERES ||
      index == JewishCalendar.SIMCHAS_TORAH ||
      index == JewishCalendar.ROSH_HASHANA ||
      index == JewishCalendar.YOM_KIPPUR;

  /// Tisha BeAv is handled separately, as it is never a working day.
  static bool _isMinorFast(int index) =>
      index == JewishCalendar.SEVENTEEN_OF_TAMMUZ ||
      index == JewishCalendar.FAST_OF_GEDALYAH ||
      index == JewishCalendar.TENTH_OF_TEVES ||
      index == JewishCalendar.FAST_OF_ESTHER;

  /// Erev Yom Tov, including 20 Nisan — Chol HaMoed, but also the eve of the
  /// seventh day of Pesach.
  ///
  /// Outside Israel the eve of every second festival day is itself Yom Tov, so
  /// it needs no separate case here.
  static bool _isErevYomTov(int index, int day) =>
      index == JewishCalendar.EREV_PESACH ||
      index == JewishCalendar.EREV_SHAVUOS ||
      index == JewishCalendar.EREV_ROSH_HASHANA ||
      index == JewishCalendar.EREV_YOM_KIPPUR ||
      index == JewishCalendar.EREV_SUCCOS ||
      (index == JewishCalendar.CHOL_HAMOED_PESACH && day == 20);

  /// The day before the fast of the ninth of Av, as actually observed.
  ///
  /// When 9 Av falls on Shabbat the fast moves to the tenth and its eve moves
  /// with it. Derived from the weekday of the day in hand rather than by
  /// stepping to another date, to keep the loop allocation-free.
  static bool _isErevTishaBeav(int month, int day, int dayOfWeek) {
    if (month != JewishDate.AV) return false;
    final ninthDayOfWeek = (dayOfWeek - 1 + (9 - day)) % 7 + 1;
    final observed = ninthDayOfWeek == JewishDate.saturday ? 10 : 9;
    return day == observed - 1;
  }

  static bool _isMinorHoliday(int index) =>
      index == JewishCalendar.TU_BESHVAT ||
      index == JewishCalendar.LAG_BAOMER ||
      index == JewishCalendar.PESACH_SHENI ||
      index == JewishCalendar.TU_BEAV ||
      index == JewishCalendar.PURIM_KATAN ||
      index == JewishCalendar.SHUSHAN_PURIM_KATAN;

  /// The day after the last day of Pesach, Shavuot and Sukkot.
  ///
  /// Computed here rather than through `JewishCalendar.isIsruChag()`, which in
  /// this version of the package tests a constant it shares with Shushan Purim
  /// Katan and so answers a different question.
  static bool _isIsruChag(int month, int day, bool inIsrael) {
    final offset = inIsrael ? 0 : 1;
    return (month == JewishDate.NISSAN && day == 22 + offset) ||
        (month == JewishDate.SIVAN && day == 7 + offset) ||
        (month == JewishDate.TISHREI && day == 23 + offset);
  }
}
