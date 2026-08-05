import 'package:kosher_dart/kosher_dart.dart';

import '../format.dart';
import '../hebrew_utils.dart';
import '../models.dart';
import 'currency.dart';
import 'date_logic.dart';
import 'export_table.dart';
import 'hebrew_clock.dart';
import 'production_calculator.dart';
import 'profit_calculator.dart';

/// A month, day by day: what was written each day, how long it took, and what
/// it came to.
///
/// Asked for so a sofer can print the month and look at it away from the
/// screen. The figures existed one at a time on the monthly summary; nothing
/// had ever laid them out beside each other, which is where a writer sees that
/// his Sundays are twice his Thursdays.
///
/// A **Hebrew** month, like everything else about the work. The annual report
/// is the one exception, because a tax year belongs to somebody else.
class MonthlyReport {
  final JewishDate month;
  final List<ReportDay> days;
  final Project? project;

  /// Kept per currency, because a month may span commissions priced in more
  /// than one and adding those together gives a number that is not a total of
  /// anything. Almost always there is exactly one — see [MoneyTotal].
  final MoneyTotal earned;

  const MonthlyReport({
    required this.month,
    required this.days,
    required this.project,
    required this.earned,
  });

  Iterable<ReportDay> get worked => days.where((d) => d.hasWork);

  int get totalLines => days.fold(0, (sum, d) => sum + d.lines);

  Duration get totalTime =>
      days.fold(Duration.zero, (sum, d) => sum + d.worked);

  /// Minutes per line across the month, or null when nothing was timed.
  ///
  /// Computed from the month's totals rather than by averaging the daily
  /// averages — those weight a day of one line the same as a day of forty.
  double? get minutesPerLine {
    if (totalLines <= 0 || totalTime <= Duration.zero) return null;
    return totalTime.inMinutes / totalLines;
  }

  static MonthlyReport forMonth({
    required Project? project,
    required Iterable<WorkSession> history,
    required Iterable<Project> projects,
    required DateTime anyDayInMonth,
    required DayStart dayStart,
  }) {
    final jd = JewishDate.fromDateTime(anyDayInMonth);
    final first = JewishDate.initDate(
      jewishYear: jd.getJewishYear(),
      jewishMonth: jd.getJewishMonth(),
      jewishDayOfMonth: 1,
    );
    final length = first.getDaysInJewishMonth();

    // One commission, or all of them. A sofer with a single job wants it named;
    // one juggling three wants the month.
    final mine = history.where((s) =>
        !s.isDeleted &&
        !s.backlogOnly &&
        (project == null || s.projectId == project.id));

    // Converted once, not once per record.
    final monthHebrew = JewishDate.fromDateTime(anyDayInMonth);
    final byDay = <int, List<WorkSession>>{};
    for (final s in mine) {
      if (!DateLogic.sessionIsInHebrewMonth(s, monthHebrew, dayStart)) continue;
      final day = DateLogic.hebrewDayOfMonth(s, dayStart);
      byDay.putIfAbsent(day, () => []).add(s);
    }

    final earned = MoneyTotal();
    final days = <ReportDay>[];
    final walker = JewishDate.initDate(
      jewishYear: first.getJewishYear(),
      jewishMonth: first.getJewishMonth(),
      jewishDayOfMonth: 1,
    );

    for (var day = 1; day <= length; day++) {
      final date = walker.getGregorianCalendar();
      final sessions = byDay[day] ?? const <WorkSession>[];

      var lines = 0;
      var worked = Duration.zero;
      final dayEarned = MoneyTotal();

      for (final s in sessions) {
        final owner = _projectOf(projects, project, s.projectId);
        lines += owner?.type == ProjectType.mezuza
            ? ProductionCalculator.mezuzaLinesInSession(s)
            : ProductionCalculator.seferLinesInSession(s);
        // Only time that was actually given. A record with no time is not a
        // sitting of zero minutes, and averaging it as one would report this
        // writer as faster than he is.
        if (s.timeRecorded) worked += s.duration;

        if (owner != null) {
          final units = ProfitCalculator.billableUnits(owner, [s]);
          final amount = units * (owner.price - owner.expenses);
          dayEarned.addAmount(amount, owner.currency);
          earned.addAmount(amount, owner.currency);
        }
      }

      days.add(ReportDay(
        date: DateTime(date.year, date.month, date.day),
        hebrewDay: day,
        sittings: sessions.length,
        lines: lines,
        worked: worked,
        earned: dayEarned,
      ));
      if (day < length) walker.forward();
    }

    return MonthlyReport(
      month: first,
      days: days,
      project: project,
      earned: earned,
    );
  }

  static Project? _projectOf(
      Iterable<Project> projects, Project? only, String id) {
    if (only != null) return only.id == id ? only : null;
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The report as a table to print or export.
  ExportTable toExportTable({
    required Currency currency,
    required bool useGregorianDates,
  }) {
    final name = project?.name ?? 'כל הפרויקטים';
    final monthName = formatDisplayDateMonth(
        days.isEmpty ? DateTime.now() : days.first.date, useGregorianDates);

    final average = minutesPerLine;
    return ExportTable(
      title: '$name · $monthName',
      summary: [
        '$totalLines שורות',
        formatSpan(totalTime),
        if (average != null) '${average.toStringAsFixed(1)} דק׳ לשורה',
        earned.format(currency),
      ].join(' · '),
      headings: const ['תאריך', 'ישיבות', 'שורות', 'זמן', 'דק׳ לשורה', 'רווח'],
      note: 'ימים ללא כתיבה מופיעים ריקים. "דק׳ לשורה" מחושב רק מרשומות '
          'שנמדד בהן זמן — רשומה בלי זמן אינה ישיבה של אפס דקות.',
      rows: [
        for (final d in days)
          ExportRow(
            [
              '${formatHebrewNumber(d.hebrewDay)} (${d.date.day}/${d.date.month})',
              d.hasWork ? '${d.sittings}' : '',
              d.hasWork ? '${d.lines}' : '',
              d.worked > Duration.zero ? formatSpan(d.worked) : '',
              d.minutesPerLine?.toStringAsFixed(1) ?? '',
              d.earned.isEmpty ? '' : d.earned.format(currency),
            ],
            muted: !d.hasWork,
          ),
        ExportRow(
          [
            'סה״כ',
            '${worked.fold(0, (n, d) => n + d.sittings)}',
            '$totalLines',
            formatSpan(totalTime),
            average?.toStringAsFixed(1) ?? '',
            earned.format(currency),
          ],
          strong: true,
        ),
      ],
    );
  }
}

/// One day of the month.
class ReportDay {
  final DateTime date;
  final int hebrewDay;

  /// How many separate sittings. Two hours in one go and two hours in six
  /// pieces are different days, and the count is the only thing that says so.
  final int sittings;

  final int lines;
  final Duration worked;
  final MoneyTotal earned;

  const ReportDay({
    required this.date,
    required this.hebrewDay,
    required this.sittings,
    required this.lines,
    required this.worked,
    required this.earned,
  });

  bool get hasWork => sittings > 0;

  /// Minutes per line on this day, or null when nothing here was timed.
  double? get minutesPerLine {
    if (lines <= 0 || worked <= Duration.zero) return null;
    return worked.inMinutes / lines;
  }
}
