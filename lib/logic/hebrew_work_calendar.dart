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
/// Results also carry the Hebrew date of the answer directly
/// ([WorkPlan.completion]), so a screen that displays Hebrew dates never
/// converts back to Gregorian at all.
///
/// ## Two kinds of day
///
/// Some days are never writing days and are not offered as a choice: Shabbat,
/// Yom Tov, Chol HaMoed, the eves of festivals, Purim and Shushan Purim, Tisha
/// BeAv and its eve. These **override every other rule** — a Shabbat of
/// Chanukah is Shabbat, whatever Chanukah is set to.
///
/// Everything else that soferim actually differ on is a setting with three
/// states — a full day, half a day, or not a working day. Where more than one
/// setting applies to the same day, the most restrictive wins: a Friday of
/// Chanukah is off if either Friday or Chanukah is off.
library;

import 'package:kosher_dart/kosher_dart.dart';

import 'calendar_days.dart';

/// How much of a day is spent writing.
enum DayWeight {
  full,
  half,
  none;

  double get value => switch (this) {
        DayWeight.full => 1,
        DayWeight.half => 0.5,
        DayWeight.none => 0,
      };

  String get label => switch (this) {
        DayWeight.full => 'יום מלא',
        DayWeight.half => 'חצי יום',
        DayWeight.none => 'לא עובד',
      };

  static DayWeight fromName(String? name, DayWeight fallback) =>
      DayWeight.values.firstWhere((w) => w.name == name, orElse: () => fallback);
}

/// Why a day is not a full working day.
enum NonWorkReason {
  // Fixed — never configurable.
  shabbat,
  yomTov,
  cholHamoed,
  erevYomTov,
  purim,
  tishaBeav,
  erevTishaBeav,

  // Configurable.
  friday,
  motzeiShabbat,
  chanukah,
  fastSeventeenTammuz,
  fastGedalya,
  fastTenthTevet,
  fastEsther,
  lagBaomer,
  isruChag,
  beforePesach,
  betweenYomKippurAndSukkot;

  String get label => switch (this) {
        NonWorkReason.shabbat => 'שבת',
        NonWorkReason.yomTov => 'יום טוב',
        NonWorkReason.cholHamoed => 'חול המועד',
        NonWorkReason.erevYomTov => 'ערב חג',
        NonWorkReason.purim => 'פורים',
        NonWorkReason.tishaBeav => 'תשעה באב',
        NonWorkReason.erevTishaBeav => 'ערב תשעה באב',
        NonWorkReason.friday => 'ערב שבת',
        NonWorkReason.motzeiShabbat => 'מוצאי שבת',
        NonWorkReason.chanukah => 'חנוכה',
        NonWorkReason.fastSeventeenTammuz => 'י״ז בתמוז',
        NonWorkReason.fastGedalya => 'צום גדליה',
        NonWorkReason.fastTenthTevet => 'י׳ בטבת',
        NonWorkReason.fastEsther => 'תענית אסתר',
        NonWorkReason.lagBaomer => 'ל״ג בעומר',
        NonWorkReason.isruChag => 'איסרו חג',
        NonWorkReason.beforePesach => 'לפני פסח',
        NonWorkReason.betweenYomKippurAndSukkot => 'בין כיפור לסוכות',
      };

  /// Whether the writer can change how this day is counted.
  bool get isConfigurable => index >= NonWorkReason.friday.index;
}

/// Which days the writer treats as time off.
///
/// Only the days soferim genuinely differ on appear here. Shabbat, Yom Tov,
/// Chol HaMoed, the eves of festivals, Purim, Shushan Purim, Tisha BeAv and its
/// eve are not settings — no writing gets done on them. Rosh Chodesh, Tu
/// BiShvat, Pesach Sheni, Purim Katan, Tu BeAv and Yom HaAtzmaut are not
/// settings either — they are ordinary working days.
class WorkCalendarRules {
  /// Bumped whenever the stored shape changes. [fromJson] migrates anything
  /// older, so a settings file written by any past version still opens.
  static const int currentSchemaVersion = 2;

  /// Israel keeps one day of Yom Tov, the diaspora two. This changes the
  /// festival days themselves, where Chol HaMoed begins, and when Isru Chag
  /// falls.
  final bool inIsrael;

  /// Never a full day: a Friday is short and preparing for Shabbat takes the
  /// rest of it. Only [DayWeight.half] and [DayWeight.none] apply.
  final DayWeight friday;

  /// Saturday night, after Shabbat ends. Never a full day — Shabbat itself is
  /// not negotiable — so only [DayWeight.half] and [DayWeight.none] apply.
  final DayWeight motzeiShabbat;

  final DayWeight chanukah;

  // Each fast separately: a sofer may sit down on the tenth of Tevet and not
  // on the seventeenth of Tammuz.
  final DayWeight fastSeventeenTammuz;
  final DayWeight fastGedalya;
  final DayWeight fastTenthTevet;
  final DayWeight fastEsther;

  final DayWeight lagBaomer;
  final DayWeight isruChag;

  /// How many days before Pesach are cleared for preparation, counting back
  /// from the first day of the festival. 7 covers 8–14 Nisan. Clamped to 0–14
  /// so the window can never spill back into Adar.
  final int daysBeforePesach;
  final DayWeight beforePesach;

  /// 11–14 Tishrei. The fourteenth is Erev Sukkot and is off regardless.
  final DayWeight betweenYomKippurAndSukkot;

  const WorkCalendarRules({
    this.inIsrael = true,
    this.friday = DayWeight.none,
    this.motzeiShabbat = DayWeight.none,
    this.chanukah = DayWeight.none,
    this.fastSeventeenTammuz = DayWeight.none,
    this.fastGedalya = DayWeight.none,
    this.fastTenthTevet = DayWeight.none,
    this.fastEsther = DayWeight.none,
    this.lagBaomer = DayWeight.none,
    this.isruChag = DayWeight.none,
    this.daysBeforePesach = 7,
    this.beforePesach = DayWeight.none,
    this.betweenYomKippurAndSukkot = DayWeight.none,
  });

  /// The defaults, named for readability at call sites.
  static const WorkCalendarRules standard = WorkCalendarRules();

  /// The window before Pesach, as Hebrew days of Nisan. Empty when the setting
  /// is zero.
  ({int from, int to})? get pesachWindow {
    final days = daysBeforePesach.clamp(0, 14);
    if (days <= 0) return null;
    return (from: 15 - days, to: 14);
  }

  WorkCalendarRules copyWith({
    bool? inIsrael,
    DayWeight? friday,
    DayWeight? motzeiShabbat,
    DayWeight? chanukah,
    DayWeight? fastSeventeenTammuz,
    DayWeight? fastGedalya,
    DayWeight? fastTenthTevet,
    DayWeight? fastEsther,
    DayWeight? lagBaomer,
    DayWeight? isruChag,
    int? daysBeforePesach,
    DayWeight? beforePesach,
    DayWeight? betweenYomKippurAndSukkot,
  }) =>
      WorkCalendarRules(
        inIsrael: inIsrael ?? this.inIsrael,
        friday: friday ?? this.friday,
        motzeiShabbat: motzeiShabbat ?? this.motzeiShabbat,
        chanukah: chanukah ?? this.chanukah,
        fastSeventeenTammuz: fastSeventeenTammuz ?? this.fastSeventeenTammuz,
        fastGedalya: fastGedalya ?? this.fastGedalya,
        fastTenthTevet: fastTenthTevet ?? this.fastTenthTevet,
        fastEsther: fastEsther ?? this.fastEsther,
        lagBaomer: lagBaomer ?? this.lagBaomer,
        isruChag: isruChag ?? this.isruChag,
        daysBeforePesach: daysBeforePesach ?? this.daysBeforePesach,
        beforePesach: beforePesach ?? this.beforePesach,
        betweenYomKippurAndSukkot:
            betweenYomKippurAndSukkot ?? this.betweenYomKippurAndSukkot,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': currentSchemaVersion,
        'inIsrael': inIsrael,
        'friday': friday.name,
        'motzeiShabbat': motzeiShabbat.name,
        'chanukah': chanukah.name,
        'fastSeventeenTammuz': fastSeventeenTammuz.name,
        'fastGedalya': fastGedalya.name,
        'fastTenthTevet': fastTenthTevet.name,
        'fastEsther': fastEsther.name,
        'lagBaomer': lagBaomer.name,
        'isruChag': isruChag.name,
        'daysBeforePesach': daysBeforePesach,
        'beforePesach': beforePesach.name,
        'betweenYomKippurAndSukkot': betweenYomKippurAndSukkot.name,
      };

  /// Reads a stored settings blob of any version this app has ever written.
  ///
  /// Unknown keys are ignored and missing keys take their default, so a file
  /// from a newer build still opens and a file from an older one is not
  /// rejected for lacking fields that did not exist yet.
  factory WorkCalendarRules.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'] is int
        ? json['schemaVersion'] as int
        // Version 1 predates the field: it had a single `skip<Thing>` boolean
        // per category and a `friday` of none/half/full.
        : 1;

    if (version < 2) return _fromV1(json);

    DayWeight weight(String key, [DayWeight fallback = DayWeight.none]) =>
        DayWeight.fromName(json[key] as String?, fallback);

    /// Friday and motzei Shabbat are never full days; a stored `full` — from a
    /// hand-edited file or an older shape — is clamped rather than honoured.
    DayWeight halfAtMost(String key) {
      final value = weight(key);
      return value == DayWeight.half ? DayWeight.half : DayWeight.none;
    }

    return WorkCalendarRules(
      inIsrael: json['inIsrael'] is bool ? json['inIsrael'] as bool : true,
      friday: halfAtMost('friday'),
      motzeiShabbat: halfAtMost('motzeiShabbat'),
      chanukah: weight('chanukah'),
      fastSeventeenTammuz: weight('fastSeventeenTammuz'),
      fastGedalya: weight('fastGedalya'),
      fastTenthTevet: weight('fastTenthTevet'),
      fastEsther: weight('fastEsther'),
      lagBaomer: weight('lagBaomer'),
      isruChag: weight('isruChag'),
      daysBeforePesach:
          json['daysBeforePesach'] is int ? json['daysBeforePesach'] as int : 7,
      beforePesach: weight('beforePesach'),
      betweenYomKippurAndSukkot: weight('betweenYomKippurAndSukkot'),
    );
  }

  /// Migration from the first stored shape.
  ///
  /// Version 1 asked yes/no per category; a "yes" becomes [DayWeight.none] —
  /// the day was skipped — and a "no" becomes [DayWeight.full]. Categories that
  /// version 1 had and version 2 dropped (Rosh Chodesh, the minor days) are
  /// discarded, since those are now always working days.
  static WorkCalendarRules _fromV1(Map<String, dynamic> json) {
    DayWeight fromSkip(String key, {bool defaultSkip = true}) {
      final skip = json[key] is bool ? json[key] as bool : defaultSkip;
      return skip ? DayWeight.none : DayWeight.full;
    }

    // Version 1 offered a full Friday; it is no longer an option, so it lands
    // on "not a working day" — the default nobody had to choose.
    final v1Friday =
        json['friday'] == 'half' ? DayWeight.half : DayWeight.none;
    final oldMotzei = json['motzeiShabbatHalfDay'] == true;
    final fasts = fromSkip('skipFasts');

    return WorkCalendarRules(
      inIsrael: json['inIsrael'] is bool ? json['inIsrael'] as bool : true,
      friday: v1Friday,
      motzeiShabbat: oldMotzei ? DayWeight.half : DayWeight.none,
      chanukah: fromSkip('skipChanukah'),
      fastSeventeenTammuz: fasts,
      fastGedalya: fasts,
      fastTenthTevet: fasts,
      fastEsther: fasts,
      // Version 1 grouped these under one "minor days" flag that defaulted to
      // working.
      lagBaomer: fromSkip('skipMinorHolidays', defaultSkip: false),
      isruChag: fromSkip('skipMinorHolidays', defaultSkip: false),
      daysBeforePesach: 7,
      beforePesach: fromSkip('skipWeekBeforePesach'),
      betweenYomKippurAndSukkot: fromSkip('skipBetweenYomKippurAndSukkot'),
    );
  }
}

/// One day, classified.
class WorkDay {
  /// 0 for a day off, 1 for a full day, 0.5 for a half day.
  final double value;

  /// Null only on an ordinary full working day.
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
  /// *why* a two-week job lands a month out. Half days are not counted here;
  /// only days with no writing at all.
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
  /// The days that are never writing days are settled first and short-circuit
  /// everything else. Only then do the configurable categories apply, and where
  /// several of them cover the same day the most restrictive one decides.
  static WorkDay classify(JewishCalendar jc, WorkCalendarRules rules) {
    final fixed = fixedReason(jc, rules.inIsrael);
    if (fixed != null) return WorkDay(0, fixed);

    var weight = DayWeight.full;
    NonWorkReason? reason;

    void consider(DayWeight candidate, NonWorkReason because) {
      if (candidate.value < weight.value) {
        weight = candidate;
        reason = because;
      }
    }

    final dayOfWeek = jc.getDayOfWeek();
    final month = jc.getJewishMonth();
    final day = jc.getJewishDayOfMonth();
    final index = jc.getYomTovIndex();

    if (dayOfWeek == JewishDate.saturday) {
      // Shabbat is never a full day; the only question is whether Saturday
      // night counts for half.
      consider(
        rules.motzeiShabbat == DayWeight.half ? DayWeight.half : DayWeight.none,
        rules.motzeiShabbat == DayWeight.half
            ? NonWorkReason.motzeiShabbat
            : NonWorkReason.shabbat,
      );
    } else if (dayOfWeek == JewishDate.friday) {
      // Never a full day either: a Friday is short, and preparing for Shabbat
      // takes the rest of it.
      consider(
        rules.friday == DayWeight.half ? DayWeight.half : DayWeight.none,
        NonWorkReason.friday,
      );
    }

    if (index == JewishCalendar.CHANUKAH) {
      consider(rules.chanukah, NonWorkReason.chanukah);
    }
    if (index == JewishCalendar.SEVENTEEN_OF_TAMMUZ) {
      consider(rules.fastSeventeenTammuz, NonWorkReason.fastSeventeenTammuz);
    }
    if (index == JewishCalendar.FAST_OF_GEDALYAH) {
      consider(rules.fastGedalya, NonWorkReason.fastGedalya);
    }
    if (index == JewishCalendar.TENTH_OF_TEVES) {
      consider(rules.fastTenthTevet, NonWorkReason.fastTenthTevet);
    }
    if (index == JewishCalendar.FAST_OF_ESTHER) {
      consider(rules.fastEsther, NonWorkReason.fastEsther);
    }
    if (index == JewishCalendar.LAG_BAOMER) {
      consider(rules.lagBaomer, NonWorkReason.lagBaomer);
    }
    if (_isIsruChag(month, day, rules.inIsrael)) {
      consider(rules.isruChag, NonWorkReason.isruChag);
    }
    if (rules.pesachWindow case final window?) {
      if (month == JewishDate.NISSAN &&
          day >= window.from &&
          day <= window.to) {
        consider(rules.beforePesach, NonWorkReason.beforePesach);
      }
    }
    if (month == JewishDate.TISHREI && day >= 11 && day <= 14) {
      consider(rules.betweenYomKippurAndSukkot,
          NonWorkReason.betweenYomKippurAndSukkot);
    }

    return WorkDay(weight.value, weight == DayWeight.full ? null : reason);
  }

  /// The reason this day can never be a writing day, or null.
  ///
  /// These override every setting: a Shabbat of Chanukah is Shabbat whatever
  /// Chanukah is set to, and Chol HaMoed stays closed for a writer who works
  /// full Fridays.
  ///
  /// Ordered by weight, so Yom Kippur reads as Yom Tov rather than as a fast
  /// and Erev Pesach as an eve rather than as part of the week before Pesach.
  static NonWorkReason? fixedReason(JewishCalendar jc, bool inIsrael) {
    final month = jc.getJewishMonth();
    final day = jc.getJewishDayOfMonth();
    final index = jc.getYomTovIndex();

    if (_isYomTovAssurBemelacha(index)) return NonWorkReason.yomTov;
    if (index == JewishCalendar.TISHA_BEAV) return NonWorkReason.tishaBeav;
    if (_isErevTishaBeav(month, day, jc.getDayOfWeek())) {
      return NonWorkReason.erevTishaBeav;
    }
    if (_isErevYomTov(index, day)) return NonWorkReason.erevYomTov;
    if (index == JewishCalendar.CHOL_HAMOED_PESACH ||
        index == JewishCalendar.CHOL_HAMOED_SUCCOS ||
        index == JewishCalendar.HOSHANA_RABBA) {
      return NonWorkReason.cholHamoed;
    }
    if (index == JewishCalendar.PURIM ||
        index == JewishCalendar.SHUSHAN_PURIM) {
      return NonWorkReason.purim;
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

    // Calendar days, not elapsed hours: a range spanning the spring change came
    // out one day short, so the last day of it went uncounted. See
    // [CalendarDays].
    final days = CalendarDays.inclusiveLength(start, end);
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

  /// Every day in a range that is not a full working day, for a "why is it so
  /// far out" breakdown or a preview strip.
  static List<({DateTime date, JewishDate hebrew, WorkDay day})> daysOff(
    DateTime from,
    DateTime to,
    WorkCalendarRules rules,
  ) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return const [];

    final days = CalendarDays.inclusiveLength(start, end);
    final jc = hebrewDayOf(start, rules);
    final result = <({DateTime date, JewishDate hebrew, WorkDay day})>[];

    for (var i = 0; i < days; i++) {
      final classified = classify(jc, rules);
      if (classified.reason != null) {
        result.add((
          date: jc.getGregorianCalendar(),
          hebrew: jc.clone(),
          day: classified,
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
