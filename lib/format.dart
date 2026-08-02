/// How a duration reads on screen.
///
/// Three shapes, and they are not interchangeable. A clock is what a running
/// timer shows and what a table of sittings reports, with seconds where they
/// are being counted and without where they are noise. A span is what a
/// sentence says in passing. A long span is what a form says when it has the
/// room and the writer is reading it rather than glancing at it.
///
/// The app had five private copies of one or another scattered through the
/// screens.
library;

import 'models.dart';

/// `₪1234` — a sum of money, rounded to the shekel.
///
/// For a figure the writer weighs rather than reconciles: what a commission
/// pays, what an hour comes to. Agorot in those is noise.
///
/// The symbol is written in forty-five places today and nowhere is it a
/// setting. That is fine while shekels are the only answer, and the moment a
/// writer abroad wants another it becomes the reason this function exists.
String formatMoney(num amount) => '₪${amount.toStringAsFixed(0)}';

/// `₪1234.56` — a sum of money to the agora.
///
/// For a figure that has to reconcile against something the writer can count:
/// what a purchase cost, what the expenses of a commission add up to.
String formatMoneyExact(num amount) => '₪${amount.toStringAsFixed(2)}';

/// `01:14:32`, or `01:14` — a stretch of time read as a clock.
///
/// Hours are not wrapped at 24: a sitting of thirty hours is a thing that
/// happens, and `06:12` for it would be a lie rather than a shorter truth.
String formatClock(Duration d, {bool seconds = true}) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final hm = '${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}';
  return seconds ? '$hm:${twoDigits(d.inSeconds.remainder(60))}' : hm;
}

/// `1 שע' 14 דק'` — a stretch of time read as a sentence would say it.
String formatSpan(Duration d) {
  if (d.inHours > 0) {
    final minutes = d.inMinutes.remainder(60);
    return minutes > 0 ? "${d.inHours} שע' $minutes דק'" : "${d.inHours} שע'";
  }
  return "${d.inMinutes} דק'";
}

/// `שעה ו-14 דקות` — the same stretch spelled out, for a form that has room.
///
/// Hebrew counts one, two and many differently, and the abbreviated form dodges
/// the question by never spelling the noun. Spelled out there is nowhere to
/// hide: this used to read "1 שעות ו-1 דקות", and to announce "0 שעות" for
/// three quarters of an hour.
String formatSpanLong(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);

  final parts = [
    if (hours > 0) hebrewCount(hours, one: 'שעה', two: 'שעתיים', many: 'שעות'),
    if (minutes > 0)
      hebrewCount(minutes, one: 'דקה', two: 'שתי דקות', many: 'דקות'),
  ];

  if (parts.isEmpty) {
    // Under a minute, but not nothing: a sitting that really was measured and
    // came to seconds must not read as though it was never measured at all.
    return d > Duration.zero ? 'פחות מדקה' : 'אין זמן';
  }
  if (parts.length == 1) return parts.first;
  return '${parts.first} ${hebrewPrefixed('ו', parts.last)}';
}

/// Attaches a one-letter prefix — ב, ל, מ, ו — the way Hebrew attaches it.
///
/// Hyphenated onto a numeral and joined straight onto a word: "ו-14 דקות", but
/// "ושתי דקות"; "ב-3 שבועות", but "בשבועיים". Every place that wrote the hyphen
/// unconditionally produced "ב-שבועיים", which no one says.
String hebrewPrefixed(String letter, String text) =>
    _startsWithDigit(text) ? '$letter-$text' : '$letter$text';

bool _startsWithDigit(String s) =>
    s.isNotEmpty && s.codeUnitAt(0) >= 0x30 && s.codeUnitAt(0) <= 0x39;

/// A session's working time, or the fact that none was given.
///
/// A record with no time used to print as `00:00`, which reads as "wrote for no
/// time at all" rather than "did not say".
String sessionTimeLabel(WorkSession s) =>
    s.timeRecorded ? formatClock(s.duration, seconds: false) : "ללא זמן";

/// A total, said to be partial when part of the work carries no time.
///
/// Without the qualifier the figure is simply an undercount, and there is no
/// way to tell it from a short day.
String workedLabel(Duration worked, bool someWithoutTime) {
  final total = formatClock(worked, seconds: false);
  if (!someWithoutTime) return total;
  return worked == Duration.zero ? "לא נרשם זמן" : "$total · חלק ללא זמן";
}

/// One, two and many, which Hebrew says three different ways. Only the third
/// takes the numeral: "שעתיים", never "2 שעות".
///
/// Every place in the app that counts something in Hebrew needs this, and every
/// place that did it by hand got it wrong the same way — "1 שעות", "2 שבועות",
/// "1 ימים". A ternary can only tell one from many, and Hebrew has a dual.
String hebrewCount(int n,
        {required String one, required String two, required String many}) =>
    switch (n) {
      1 => one,
      2 => two,
      _ => '$n $many',
    };
