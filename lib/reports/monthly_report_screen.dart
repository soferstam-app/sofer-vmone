import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:printing/printing.dart';

import '../format.dart';
import '../hebrew_utils.dart';
import '../logic/currency.dart';
import '../logic/export_table.dart';
import '../logic/hebrew_clock.dart';
import '../logic/monthly_report.dart';
import '../models.dart';
import '../plan/plan_export.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/sofer_widgets.dart';

/// A month, day by day, to print.
///
/// Asked for so a sofer can take the month away from the screen: what he wrote
/// each day, how long it took, what a line cost him in minutes, and what it
/// came to. The figures existed one at a time on the monthly summary; laid
/// beside each other they say something none of them says alone.
class MonthlyReportScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;

  const MonthlyReportScreen({
    super.key,
    required this.projects,
    required this.history,
  });

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  final StorageService _storage = StorageService();

  /// Null means every commission together. A sofer with one job wants it
  /// named; one juggling three wants the month.
  Project? _project;
  DateTime _anchor = DateTime.now();
  DayStart _dayStart = DayStart.midnight;
  Currency _currency = Currency.ils;
  bool _useGregorianDates = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dayStart = await _storage.getDayStart();
    final currency = await _storage.getCurrency();
    final gregorian = await _storage.getUseGregorianDates();
    if (!mounted) return;
    setState(() {
      _dayStart = dayStart;
      _currency = currency;
      _useGregorianDates = gregorian;
      _loaded = true;
    });
  }

  /// One Hebrew month back or forward, walked through the Hebrew calendar
  /// rather than by adding thirty days, which drifts.
  void _shift(int by) {
    final jd = JewishDate.fromDateTime(_anchor);
    var year = jd.getJewishYear();
    var month = jd.getJewishMonth();
    final monthsInYear = jd.isJewishLeapYear() ? 13 : 12;

    for (var i = 0; i < by.abs(); i++) {
      if (by > 0) {
        month++;
        if (month > monthsInYear) {
          month = 1;
          year++;
        }
      } else {
        month--;
        if (month < 1) {
          month = monthsInYear;
          year--;
        }
      }
    }
    setState(() => _anchor = JewishDate.initDate(
          jewishYear: year,
          jewishMonth: month,
          jewishDayOfMonth: 1,
        ).getGregorianCalendar());
  }

  MonthlyReport _report() => MonthlyReport.forMonth(
        project: _project,
        history: widget.history,
        projects: widget.projects,
        anyDayInMonth: _anchor,
        dayStart: _dayStart,
      );

  ExportTable _table() => _report().toExportTable(
        currency: _currency,
        useGregorianDates: _useGregorianDates,
      );

  Future<void> _print() async {
    final table = _table();
    try {
      await Printing.layoutPdf(
        name: PlanExport.fileName(table, 'pdf'),
        onLayout: (_) => PlanExport.toPdf(table),
      );
    } catch (e) {
      if (mounted) showAppError(context, 'ההדפסה נכשלה: $e');
    }
  }

  Future<void> _exportXlsx() async {
    final table = _table();
    try {
      final bytes = await PlanExport.toXlsx(table);
      if (!mounted) return;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'שמירת הדוח החודשי',
        fileName: PlanExport.fileName(table, 'xlsx'),
        bytes: bytes,
      );
      if (!mounted || path == null) return;
      // Desktop hands back a path and expects the caller to write; mobile has
      // already written the bytes itself.
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (mounted) showAppSuccess(context, 'נשמר: $path');
    } catch (e) {
      if (mounted) showAppError(context, 'הייצוא נכשל: $e');
    }
  }

  Widget _row(BuildContext context, ReportDay day) {
    final t = SoferTokens.of(context);
    final average = day.minutesPerLine;

    TextStyle figure() => TextStyle(
        fontFamily: t.numeralFamily,
        fontSize: 13,
        color: day.hasWork ? t.ink : t.inkFaint);

    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              '${formatHebrewNumber(day.hebrewDay)} · ${day.date.day}/${day.date.month}',
              style: TextStyle(
                  fontFamily: t.labelFamily,
                  fontSize: 11,
                  color: day.hasWork ? t.ink : t.inkFaint),
            ),
          ),
          // Blank rather than zero on a day nobody wrote. A column of zeros
          // reads as a claim; a blank is the absence of one.
          Expanded(
              child: Text(day.hasWork ? '${day.lines}' : '',
                  textAlign: TextAlign.end, style: figure())),
          Expanded(
              flex: 2,
              child: Text(
                  day.worked > Duration.zero ? formatSpan(day.worked) : '',
                  textAlign: TextAlign.end,
                  style: figure())),
          Expanded(
              child: Text(average?.toStringAsFixed(1) ?? '',
                  textAlign: TextAlign.end, style: figure())),
          Expanded(
              flex: 2,
              child: Text(
                  day.earned.isEmpty ? '' : day.earned.format(_currency),
                  textAlign: TextAlign.end,
                  style: figure())),
        ],
      ),
    );
  }

  Widget _headings(BuildContext context) {
    final t = SoferTokens.of(context);
    TextStyle style() => TextStyle(
        fontFamily: t.labelFamily,
        fontSize: 10,
        letterSpacing: 1.1,
        color: t.inkMuted);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          SizedBox(width: 62, child: Text('תאריך', style: style())),
          Expanded(
              child:
                  Text('שורות', textAlign: TextAlign.end, style: style())),
          Expanded(
              flex: 2,
              child: Text('זמן', textAlign: TextAlign.end, style: style())),
          Expanded(
              child: Text('דק׳/שורה',
                  textAlign: TextAlign.end, style: style())),
          Expanded(
              flex: 2,
              child: Text('רווח', textAlign: TextAlign.end, style: style())),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('דוח חודשי'),
        actions: [
          if (_loaded) ...[
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'הדפסה או שמירה כ-PDF',
              onPressed: _print,
            ),
            IconButton(
              icon: const Icon(Icons.table_view),
              tooltip: 'ייצוא לאקסל',
              onPressed: _exportXlsx,
            ),
          ],
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              final report = _report();
              final average = report.minutesPerLine;

              return SoferPage(
                maxWidth: 760,
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: DropdownButtonFormField<String>(
                        initialValue: _project?.id ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'פרויקט',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: Text('כל הפרויקטים')),
                          ...widget.projects.map((p) =>
                              DropdownMenuItem(value: p.id, child: Text(p.name))),
                        ],
                        onChanged: (id) => setState(() => _project = id == null ||
                                id.isEmpty
                            ? null
                            : widget.projects.firstWhere((p) => p.id == id)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => _shift(-1),
                            icon: const Icon(Icons.chevron_right),
                            tooltip: 'חודש קודם',
                          ),
                          Expanded(
                            child: Text(
                              formatDisplayDateMonth(_anchor, _useGregorianDates),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: t.numeralFamily,
                                  fontSize: 18,
                                  color: t.ink),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _shift(1),
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'חודש הבא',
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Text(
                        [
                          '${report.totalLines} שורות',
                          formatSpan(report.totalTime),
                          if (average != null)
                            '${average.toStringAsFixed(1)} דק׳ לשורה',
                          report.earned.format(_currency),
                        ].join(' · '),
                        style: TextStyle(
                            fontFamily: t.labelFamily,
                            fontSize: 14,
                            height: 1.6,
                            color: t.inkMuted),
                      ),
                    ),
                    const SoferRule(strong: true),
                    _headings(context),
                    const SoferRule(),
                    for (final day in report.days) _row(context, day),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      child: Text(
                        'ימים ללא כתיבה מופיעים ריקים. "דק׳ לשורה" מחושב רק '
                        'מרשומות שנמדד בהן זמן — רשומה בלי זמן אינה ישיבה של '
                        'אפס דקות, וספירתה ככזו הייתה מציגה אותך מהיר ממה שאתה.',
                        style: TextStyle(
                            fontFamily: t.labelFamily,
                            fontSize: 11,
                            height: 1.7,
                            color: t.inkFaint),
                      ),
                    ),
                  ],
                ),
              );
            }),
    );
  }
}
