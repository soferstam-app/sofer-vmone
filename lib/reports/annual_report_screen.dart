import 'package:flutter/material.dart';

import '../logic/annual_report.dart';
import '../logic/currency.dart';
import '../logic/hebrew_clock.dart';
import '../models.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sofer_widgets.dart';

/// A year's income and costs, month by month.
///
/// What a self-employed sofer is asked for once a year, and the one screen in
/// the app that counts in **Gregorian** months: a tax year is January to
/// December, set by an authority that does not care how the writer counts his
/// days.
class AnnualReportScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;

  const AnnualReportScreen({
    super.key,
    required this.projects,
    required this.history,
  });

  @override
  State<AnnualReportScreen> createState() => _AnnualReportScreenState();
}

class _AnnualReportScreenState extends State<AnnualReportScreen> {
  final StorageService _storage = StorageService();

  int _year = DateTime.now().year;
  List<Expense> _expenses = const [];
  DayStart _dayStart = DayStart.midnight;
  Currency _currency = Currency.ils;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final expenses = await _storage.loadExpenses();
    final dayStart = await _storage.getDayStart();
    final currency = await _storage.getCurrency();
    if (!mounted) return;
    setState(() {
      _expenses = expenses;
      _dayStart = dayStart;
      _currency = currency;
      _loaded = true;
    });
  }

  Widget _row(BuildContext context, ReportMonth month) {
    final t = SoferTokens.of(context);
    final net = month.net(_currency);

    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
      padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(month.name,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 13,
                    color: month.isEmpty ? t.inkFaint : t.ink)),
          ),
          Expanded(
            child: Text(
              month.income.isEmpty ? '—' : month.income.format(_currency),
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontFamily: t.numeralFamily, fontSize: 14, color: t.ink),
            ),
          ),
          Expanded(
            child: Text(
              month.expenses.isEmpty ? '—' : month.expenses.format(_currency),
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontFamily: t.numeralFamily,
                  fontSize: 14,
                  color: t.inkMuted),
            ),
          ),
          Expanded(
            child: Text(
              // A mixed month has no single net, and the two lines above have
              // already said everything that is true about it.
              net == null ? '—' : net.format(decimals: 0),
              textAlign: TextAlign.end,
              style: TextStyle(
                fontFamily: t.numeralFamily,
                fontSize: 14,
                color: net == null
                    ? t.caution
                    : (net.amount >= 0 ? t.positive : t.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headings(BuildContext context) {
    final t = SoferTokens.of(context);
    TextStyle style() => TextStyle(
        fontFamily: t.labelFamily,
        fontSize: 11,
        letterSpacing: 1.2,
        color: t.inkMuted);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
      child: Row(
        children: [
          SizedBox(width: 74, child: Text('חודש', style: style())),
          Expanded(
              child: Text('הכנסות',
                  textAlign: TextAlign.end, style: style())),
          Expanded(
              child: Text('הוצאות',
                  textAlign: TextAlign.end, style: style())),
          Expanded(
              child: Text('נטו', textAlign: TextAlign.end, style: style())),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('דוח שנתי')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              final report = AnnualReport.forYear(
                year: _year,
                projects: widget.projects,
                history: widget.history,
                expenses: _expenses,
                dayStart: _dayStart,
              );
              final net = report.net(_currency);

              return SoferPage(
                maxWidth: 720,
                child: ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => setState(() => _year--),
                            icon: const Icon(Icons.chevron_right),
                            tooltip: 'שנה קודמת',
                          ),
                          Expanded(
                            child: Text('$_year',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontFamily: t.numeralFamily,
                                    fontSize: 22,
                                    color: t.ink)),
                          ),
                          IconButton(
                            onPressed: _year >= DateTime.now().year
                                ? null
                                : () => setState(() => _year++),
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'שנה הבאה',
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Text(
                        'שנת מס נספרת בלוח הלועזי, ינואר עד דצמבר — להבדיל '
                        'משאר האפליקציה, שסופרת בחודשים עבריים.',
                        style: TextStyle(
                            fontFamily: t.labelFamily,
                            fontSize: 11,
                            height: 1.7,
                            color: t.inkFaint),
                      ),
                    ),
                    const SoferRule(strong: true),
                    _headings(context),
                    const SoferRule(),
                    for (final month in report.months) _row(context, month),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SoferStatRow(
                              'הכנסות $_year', report.income.format(_currency)),
                          SoferStatRow('הוצאות $_year',
                              report.expenses.format(_currency)),
                          SoferStatRow(
                            'נטו',
                            net == null
                                ? 'לא ניתן לחשב — יותר ממטבע אחד'
                                : net.format(decimals: 2),
                            last: true,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text(
                        'הכנסות הן המחיר של מה שנכתב; הוצאות הן חומרי הגלם '
                        'ליחידה בתוספת ההוצאות שנרשמו. עבודה שסומנה כהשלמת עבר '
                        'אינה נספרת — היא לא שולמה השנה.',
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
