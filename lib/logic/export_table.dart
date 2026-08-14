/// A table on its way out of the app.
///
/// The plan and the monthly report are different questions with the same
/// answer shape: a title, some columns, some rows, and a closing line. Sharing
/// this means one PDF renderer and one spreadsheet writer, which is the only
/// way two exports stay looking like they came from the same program.
class ExportTable {
  final String title;

  /// A line under the title. What the table comes to, in a sentence.
  final String summary;

  final List<String> headings;
  final List<ExportRow> rows;

  /// Printed small at the foot of the page. What a reader needs in order not to
  /// misread the columns — where a figure comes from, or why one is blank.
  final String? note;

  const ExportTable({
    required this.title,
    required this.summary,
    required this.headings,
    required this.rows,
    this.note,
  });

  /// The table as comma-separated text.
  ///
  /// Kept beside the workbook rather than instead of it: it is the one format
  /// that cannot fail to open, and a writer who only wants the numbers
  /// somewhere else is served by it.
  String toCsv() {
    String cell(String v) =>
        v.contains(',') || v.contains('"') || v.contains('\n')
            ? '"${v.replaceAll('"', '""')}"'
            : v;

    final lines = <String>[
      cell(title),
      cell(summary),
      '',
      headings.map(cell).join(','),
      for (final r in rows) r.cells.map(cell).join(','),
    ];
    // A byte order mark, or Excel reads UTF-8 Hebrew as mojibake — which is
    // what every "the export is broken" report about a CSV turns out to be.
    return '﻿${lines.join('\r\n')}\r\n';
  }
}

/// One row, and how it should be read.
class ExportRow {
  final List<String> cells;

  /// A row that is not really an entry — a day nobody worked, a month with
  /// nothing in it. Drawn faintly rather than left to look like an oversight.
  final bool muted;

  /// A row worth the eye stopping on: a day that fell short of its target.
  final bool warn;

  /// A total or a subtotal, set apart from the entries it sums.
  final bool strong;

  const ExportRow(
    this.cells, {
    this.muted = false,
    this.warn = false,
    this.strong = false,
  });
}
