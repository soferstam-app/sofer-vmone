import '../hebrew_utils.dart';
import '../models.dart';
import 'export_table.dart';
import 'production_plan.dart';

/// The plan as rows and columns, before anything decides how to draw it.
///
/// A PDF, a spreadsheet and a printed page are three renderings of one table.
/// Building it once means they cannot drift apart — and it means the thing
/// worth checking, which is what each cell says, can be checked without
/// rendering anything.
class PlanTable {
  final String title;
  final List<String> headings;
  final List<PlanRow> rows;

  /// A closing line — where the stretch ends up.
  final String summary;

  const PlanTable({
    required this.title,
    required this.headings,
    required this.rows,
    required this.summary,
  });

  static const List<String> _weekdays = [
    'ראשון',
    'שני',
    'שלישי',
    'רביעי',
    'חמישי',
    'שישי',
    'שבת',
  ];

  /// A position as a sofer says it — "עמוד יד", "מזוזה 3".
  ///
  /// Rounded up: reaching a target means finishing the unit it lands in, and
  /// "be at page 13.4" is not an instruction anyone can follow.
  static String position(Project project, double units) {
    final n = units <= 0 ? 0 : units.ceil();
    if (n <= 0) return '—';
    return switch (project.type) {
      ProjectType.sefer => 'עמוד ${formatHebrewNumber(n)}',
      ProjectType.mezuza => 'מזוזה $n',
      ProjectType.tefillin => 'סט $n',
    };
  }

  static PlanTable of({
    required Project project,
    required ProductionPlan plan,
    required String periodLabel,
    required bool useGregorianDates,
  }) {
    final rows = <PlanRow>[];

    for (final day in plan.days) {
      final weekday = _weekdays[day.date.weekday % 7];
      final hebrew = formatHebrewNumber(day.hebrewDay);
      final gregorian = '${day.date.day}/${day.date.month}';

      rows.add(PlanRow(
        date: day.date,
        // Both calendars on a printed page: the sofer reads the Hebrew date and
        // hangs the sheet where anyone else reads the other one.
        day: useGregorianDates ? '$gregorian ($hebrew)' : '$hebrew ($gregorian)',
        weekday: weekday,
        // What the day asks for. A day off says why instead of a number.
        target: day.isWorkingDay
            ? position(project, day.shownTarget)
            : (day.closedReason?.label ?? 'לא עובד'),
        // Only for days gone by. A blank is where the writer fills it in
        // himself on a printed sheet, which is half the point of printing one.
        actual: day.actual == null || day.isFuture
            ? ''
            : position(project, day.actual!),
        isWorkingDay: day.isWorkingDay,
        isHalfDay: day.isHalfDay,
        isOverridden: day.isOverridden,
        isBehind: day.isBehind,
        isToday: day.isToday,
      ));
    }

    final behind = plan.behindBy;
    return PlanTable(
      title: '${project.name} · $periodLabel',
      headings: const ['תאריך', 'יום', 'להגיע עד', 'בפועל'],
      rows: rows,
      summary: behind == null
          ? 'עד הסוף: ${position(project, plan.closingTarget)}'
          : 'פיגור של ${behind.ceil()} · '
              'עד הסוף: ${position(project, plan.closingTarget)}',
    );
  }

  /// The same table, flattened for anything that leaves the app.
  ///
  /// The rich rows above are for the grid on screen, which colours a day off
  /// differently from a day fallen short of. A file keeps that distinction as a
  /// flag rather than a colour, so a spreadsheet can ignore it and a printed
  /// page can draw it.
  ExportTable toExportTable() => ExportTable(
        title: title,
        summary: summary,
        headings: headings,
        note: 'עמודת "בפועל" ריקה בימים שטרם הגיעו — למילוי ביד.',
        rows: [
          for (final r in rows)
            ExportRow(
              [r.day, r.weekday, r.target, r.actual],
              muted: !r.isWorkingDay,
              warn: r.isBehind,
            ),
        ],
      );

  String toCsv() => toExportTable().toCsv();
}

/// One day, as a row.
class PlanRow {
  final DateTime date;
  final String day;
  final String weekday;
  final String target;
  final String actual;

  final bool isWorkingDay;
  final bool isHalfDay;
  final bool isOverridden;
  final bool isBehind;
  final bool isToday;

  const PlanRow({
    required this.date,
    required this.day,
    required this.weekday,
    required this.target,
    required this.actual,
    required this.isWorkingDay,
    required this.isHalfDay,
    required this.isOverridden,
    required this.isBehind,
    required this.isToday,
  });
}
