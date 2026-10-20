import 'package:kosher_dart/kosher_dart.dart';

import '../format.dart';
import '../hebrew_utils.dart';
import '../models.dart';
import 'currency.dart';
import 'date_logic.dart';
import 'export_table.dart';
import 'hebrew_clock.dart';
import 'measured_work.dart';
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

  /// Physical lines attempted in work that was later marked invalid. They are
  /// shown separately from output, while their measured time remains in the
  /// pace denominator.
  int get totalInvalidLines => days.fold(0, (sum, d) => sum + d.invalidLines);

  /// Lines from records that carried time — the denominator of any average
  /// involving it. See [MeasuredWork].
  int get totalMeasuredLines => days.fold(0, (sum, d) => sum + d.measuredLines);

  double get totalComparableMeasuredLines =>
      days.fold(0.0, (sum, d) => sum + d.comparableMeasuredLinesForAverage);

  double get totalComparableLines =>
      days.fold(0.0, (sum, d) => sum + d.comparableLines);

  Duration get totalTime =>
      days.fold(Duration.zero, (sum, d) => sum + d.worked);

  /// Minutes per line across the month, or null when nothing was timed.
  ///
  /// Computed from the month's totals rather than by averaging the daily
  /// averages — those weight a day of one line the same as a day of forty.
  double? get minutesPerLine {
    if (totalComparableMeasuredLines <= 0 || totalTime <= Duration.zero) {
      return null;
    }
    return minutesWithSeconds(totalTime) / totalComparableMeasuredLines;
  }

  /// Some of the month's output carried no time, so the average above rests on
  /// part of it. A screen showing the figure has to be able to say so.
  bool get someWorkUntimed => totalMeasuredLines != totalLines;

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
      var invalidLines = 0;
      var measuredLines = 0;
      var comparableLines = 0.0;
      var comparableMeasuredLines = 0.0;
      var worked = Duration.zero;
      final dayEarned = MoneyTotal();

      for (final s in sessions) {
        final owner = _projectOf(projects, project, s.projectId);
        final theseLines = switch (owner?.type) {
          ProjectType.mezuza => ProductionCalculator.mezuzaLinesInSession(s),
          ProjectType.tefillin =>
            ProductionCalculator.tefillinPhysicalLinesInSession(s),
          _ => ProductionCalculator.seferLinesInSession(s),
        };
        final attemptedLines = switch (owner?.type) {
          ProjectType.mezuza =>
            ProductionCalculator.mezuzaLinesInSession(s, includeInvalid: true),
          ProjectType.tefillin =>
            ProductionCalculator.tefillinPhysicalLinesInSession(s,
                includeInvalid: true),
          _ =>
            ProductionCalculator.seferLinesInSession(s, includeInvalid: true),
        };
        lines += theseLines;
        if (s.isInvalid) invalidLines += attemptedLines;
        comparableLines += owner == null
            ? theseLines.toDouble()
            : owner.type == ProjectType.tefillin
                ? ProductionCalculator.tefillinSeferLines(s,
                    includeInvalid: true)
                : ProductionCalculator.comparableLinesInSession(owner, s,
                    includeInvalid: true);

        // Both halves of the ratio, from the same records. Only the time was
        // filtered before, so measured minutes were divided by every line —
        // including lines that carried no time at all.
        if (MeasuredWork.countsForTime(s)) {
          measuredLines += theseLines;
          if (owner != null) {
            comparableMeasuredLines += owner.type == ProjectType.tefillin
                ? ProductionCalculator.tefillinSeferLines(s,
                    includeInvalid: true)
                : ProductionCalculator.comparableLinesInSession(owner, s,
                    includeInvalid: true);
          }
          worked += s.duration;
        }

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
        invalidLines: invalidLines,
        comparableLines: comparableLines,
        measuredLines: measuredLines,
        comparableMeasuredLines: comparableMeasuredLines,
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
    bool english = false,
  }) {
    final name = project?.name ?? (english ? 'All projects' : 'כל הפרויקטים');
    final monthName = formatDisplayDateMonth(
        days.isEmpty ? DateTime.now() : days.first.date, useGregorianDates,
        english: english);

    final average = minutesPerLine;
    final totalLineText = project?.type == ProjectType.tefillin
        ? _formatLineCounts(totalLines, totalComparableLines)
        : '$totalLines';
    final totalLineWithInvalid = totalInvalidLines > 0
        ? '$totalLineText · $totalInvalidLines ${english ? 'invalid' : 'פסולות'}'
        : totalLineText;
    return ExportTable(
      title: '$name · $monthName',
      rtl: !english,
      summary: [
        english ? '$totalLineWithInvalid lines' : '$totalLineWithInvalid שורות',
        formatSpan(totalTime, english: english),
        if (average != null)
          english
              ? '${average.toStringAsFixed(1)} min/line'
              : '${average.toStringAsFixed(1)} דק׳ לשורה',
        earned.format(currency),
      ].join(' · '),
      headings: english
          ? const ['Date', 'Sessions', 'Lines', 'Time', 'Min/line', 'Profit']
          : const ['תאריך', 'ישיבות', 'שורות', 'זמן', 'דק׳ לשורה', 'רווח'],
      note: english
          ? 'Days without writing are blank. "Min/line" uses only records with measured time; a record without time is not a zero-minute session.'
          : 'ימים ללא כתיבה מופיעים ריקים. "דק׳ לשורה" מחושב רק מרשומות שנמדד בהן זמן — רשומה בלי זמן אינה ישיבה של אפס דקות.',
      rows: [
        for (final d in days)
          ExportRow(
            [
              english
                  ? '${d.hebrewDay} (${d.date.day}/${d.date.month})'
                  : '${formatHebrewNumber(d.hebrewDay)} (${d.date.day}/${d.date.month})',
              d.hasWork ? '${d.sittings}' : '',
              d.hasWork
                  ? _linesForDisplay(d,
                      showComparable: project?.type == ProjectType.tefillin,
                      english: english)
                  : '',
              d.worked > Duration.zero
                  ? formatSpan(d.worked, english: english)
                  : '',
              d.minutesPerLine?.toStringAsFixed(1) ?? '',
              d.earned.isEmpty ? '' : d.earned.format(currency),
            ],
            muted: !d.hasWork,
          ),
        ExportRow(
          [
            english ? 'Total' : 'סה״כ',
            '${worked.fold(0, (n, d) => n + d.sittings)}',
            totalLineWithInvalid,
            formatSpan(totalTime, english: english),
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

  /// Physical lines in invalid work, kept out of [lines] so the printed
  /// output cannot be mistaken for billable writing.
  final int invalidLines;

  /// Cross-type equivalent lines. For a tefillin report this is shown in
  /// parentheses beside the physical ruled-line count.
  final double comparableLines;

  /// Of [lines], how many came from records that carried time.
  final int measuredLines;

  /// Weighted comparison lines used for a cross-type time average. The
  /// physical [measuredLines] remains available for printed output.
  final double comparableMeasuredLines;

  final Duration worked;
  final MoneyTotal earned;

  const ReportDay({
    required this.date,
    required this.hebrewDay,
    required this.sittings,
    required this.lines,
    this.invalidLines = 0,
    this.comparableLines = 0,
    required this.measuredLines,
    this.comparableMeasuredLines = 0,
    required this.worked,
    required this.earned,
  });

  bool get hasWork => sittings > 0;

  /// Minutes per line on this day, or null when nothing here was timed.
  double? get minutesPerLine {
    if (comparableMeasuredLinesForAverage <= 0 || worked <= Duration.zero) {
      return null;
    }
    return minutesWithSeconds(worked) / comparableMeasuredLinesForAverage;
  }

  double get comparableMeasuredLinesForAverage => comparableMeasuredLines > 0
      ? comparableMeasuredLines
      : measuredLines.toDouble();
}

String _linesForDisplay(ReportDay day,
    {required bool showComparable, required bool english}) {
  final output = _formatLineCounts(day.lines, day.comparableLines,
      showComparable: showComparable);
  if (day.invalidLines <= 0) return output;
  return english
      ? '$output · ${day.invalidLines} invalid'
      : '$output · ${day.invalidLines} פסולות';
}

String _formatLineCounts(int physical, double comparable,
    {bool showComparable = true}) {
  if (!showComparable || comparable <= 0 || comparable == physical) {
    return '$physical';
  }
  final rounded = comparable.roundToDouble() == comparable
      ? comparable.toInt().toString()
      : comparable.toStringAsFixed(1);
  return '$physical ($rounded)';
}
