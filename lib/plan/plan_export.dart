import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../logic/export_table.dart';

/// Turning a table into something that leaves the app.
///
/// Three renderings of one [ExportTable], so a plan and a monthly report cannot
/// come out looking like they were made by different programs. What each cell
/// contains is settled before any of this runs and tested there; here is only
/// how it is drawn.
class PlanExport {
  const PlanExport._();

  /// Hebrew needs an embedded font — a PDF viewer cannot be assumed to have
  /// one, and without it the page comes out as empty boxes. These are the same
  /// two the app draws with, so a printed sheet looks like the screen it came
  /// from. Loaded once and kept.
  static pw.Font? _serif;
  static pw.Font? _sans;

  static Future<void> _loadFonts() async {
    if (_serif != null && _sans != null) return;
    _serif ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/FrankRuhlLibre-var.ttf'));
    _sans ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Heebo-var.ttf'));
  }

  /// The table as a page to print or keep.
  static Future<Uint8List> toPdf(ExportTable table) async {
    await _loadFonts();
    final serif = _serif!;
    final sans = _sans!;

    final doc = pw.Document(title: table.title);

    pw.Widget cell(String text,
            {bool heading = false, bool muted = false, bool strong = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              font: heading ? sans : serif,
              fontSize: heading ? 9 : 10,
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: muted ? PdfColors.grey600 : PdfColors.black,
            ),
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        // Every page, not only the first: a table that breaks across two sheets
        // and loses its direction on the second is worse than one long page.
        textDirection: pw.TextDirection.rtl,
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Text(table.title,
                    style: pw.TextStyle(font: sans, fontSize: 9,
                        color: PdfColors.grey600)),
              ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text('${context.pageNumber} / ${context.pagesCount}',
              style: pw.TextStyle(
                  font: sans, fontSize: 9, color: PdfColors.grey600)),
        ),
        build: (context) => [
          pw.Text(table.title,
              style: pw.TextStyle(font: serif, fontSize: 17)),
          pw.SizedBox(height: 4),
          pw.Text(table.summary,
              style: pw.TextStyle(
                  font: sans, fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerRight,
            headers: table.headings,
            headerStyle: pw.TextStyle(font: sans, fontSize: 9),
            cellStyle: pw.TextStyle(font: serif, fontSize: 10),
            // A day off is greyed rather than left to look like an oversight,
            // and a day already fallen short of is shaded so the eye finds it.
            rowDecoration: const pw.BoxDecoration(),
            data: [for (final row in table.rows) row.cells],
            cellDecoration: (index, data, row) {
              if (row == 0 || row > table.rows.length) {
                return const pw.BoxDecoration();
              }
              final r = table.rows[row - 1];
              if (r.muted) {
                return const pw.BoxDecoration(color: PdfColors.grey100);
              }
              if (r.warn) return const pw.BoxDecoration(color: PdfColors.red50);
              if (r.strong) {
                return const pw.BoxDecoration(color: PdfColors.grey200);
              }
              return const pw.BoxDecoration();
            },
          ),
          pw.SizedBox(height: 10),
          if (table.note != null)
            cell(table.note!, heading: true, muted: true),
        ],
      ),
    );

    return doc.save();
  }

  /// The table as a spreadsheet.
  ///
  /// A real workbook rather than a CSV renamed, so it opens with its columns
  /// already the right way round and its Hebrew intact — no import dialog, no
  /// encoding to choose.
  static Future<Uint8List> toXlsx(ExportTable table) async {
    final book = xl.Excel.createExcel();
    final sheet = book[book.getDefaultSheet() ?? 'Sheet1'];

    sheet.appendRow([xl.TextCellValue(table.title)]);
    sheet.appendRow([xl.TextCellValue(table.summary)]);
    sheet.appendRow([]);
    sheet.appendRow(
        [for (final h in table.headings) xl.TextCellValue(h)]);

    for (final row in table.rows) {
      sheet.appendRow([
        // An empty cell rather than a blank string, so it is genuinely empty
        // for whoever fills the column in or sums beside it.
        for (final c in row.cells) c.isEmpty ? null : xl.TextCellValue(c),
      ]);
    }

    final bytes = book.encode();
    if (bytes == null) {
      throw StateError('could not encode the workbook');
    }
    return Uint8List.fromList(bytes);
  }

  /// A file name that says what the file is without being opened.
  static String fileName(ExportTable table, String extension) {
    final safe = table.title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$safe.$extension';
  }
}
