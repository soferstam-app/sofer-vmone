import 'package:flutter/material.dart';

import 'expenses/expense_editor.dart';
import 'hebrew_utils.dart';
import 'logic/expense_logic.dart';
import 'logic/id_generator.dart';
import 'logic/money_input.dart';
import 'logic/hebrew_work_calendar.dart';
import 'logic/megillah_format.dart';
import 'logic/production_calculator.dart';
import 'logic/project_analytics.dart';
import 'logic/quote_calculator.dart';
import 'models.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'format.dart';
import 'logic/currency.dart';
import 'l10n/app_localizations.dart';

/// Works out what a job would take and what to charge for it, from the
/// writer's own measured pace rather than a guess.
class QuoteScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;
  final Future<void> Function(Project project)? onProjectCreated;

  const QuoteScreen({
    super.key,
    required this.projects,
    required this.history,
    this.onProjectCreated,
  });

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  final StorageService _storage = StorageService();

  ProjectType _type = ProjectType.sefer;
  String _megillahFormat = MegillahFormat.lines11;

  /// Two ways to arrive at a quote, depending on what the writer already knows:
  /// they can name the hourly rate they want and get a price, or name a price
  /// per unit and see what it actually pays per hour.
  bool _priceFromHourlyRate = true;

  final _unitsCtrl = TextEditingController(text: '245');
  final _rateCtrl = TextEditingController(text: '60');
  final _unitPriceCtrl = TextEditingController(text: '180');
  final _hoursCtrl = TextEditingController(text: '6');
  final _workShareCtrl = TextEditingController(text: '100');
  DateTime _quoteStart = DateUtils.dateOnly(DateTime.now());
  DateTime? _overheadThrough;

  /// Materials taken from the expenses screen rather than typed in — the
  /// default whenever there is anything recorded to take them from.
  bool _expensesFromRecords = true;

  /// Costs entered by hand for this quote, as lines rather than as one number.
  ///
  /// Not persisted: a quote is for work that does not exist yet, so there is no
  /// commission to charge them to and nothing to keep.
  final List<QuoteExpense> _quoteExpenses = [];
  bool _includeGeneralExpenses = false;

  WorkCalendarRules _rules = WorkCalendarRules.standard;

  /// A quote is for work that does not exist yet, so there is no record to take
  /// a currency from: it is priced in whatever the writer is currently working
  /// in. Once the job is booked, the commission stores its own.
  Currency _currency = Currency.ils;
  bool _useGregorianDates = false;
  List<Expense> _expenses = const [];

  @override
  void initState() {
    super.initState();
    _storage.getWorkCalendarRules().then((v) {
      if (mounted) setState(() => _rules = v);
    });
    _storage.getCurrency().then((v) {
      if (mounted) setState(() => _currency = v);
    });
    _storage.getUseGregorianDates().then((v) {
      if (mounted) setState(() => _useGregorianDates = v);
    });
    _storage.loadExpenses().then((v) {
      if (mounted) setState(() => _expenses = v);
    });
  }

  /// What materials have actually cost per unit on work of this type, or null
  /// when nothing has been recorded against a project yet.
  double? get _recordedExpensePerUnit => ExpenseLogic.averagePerUnit(
      _type, widget.projects, widget.history, _expenses);

  List<Expense> get _generalExpenses => _expenses
      .where((e) => !e.isDeleted && e.allocation != ExpenseAllocation.project)
      .toList();

  double _generalExpensesPerUnit(double units) {
    if (units <= 0) return 0;
    final shares = _allocatedOverheads(units);
    return _generalExpenses
            .where((e) => e.currency == _currency)
            .fold(0.0, (sum, e) => sum + (shares[e.id] ?? 0)) /
        units;
  }

  double? get _workShare {
    final percent = MoneyInput.parse(_workShareCtrl.text);
    return percent != null && percent.isFinite && percent > 0 && percent <= 100
        ? percent / 100
        : null;
  }

  double get _allocatedHoursPerDay =>
      (MoneyInput.parse(_hoursCtrl.text) ?? 0) *
      (_includeGeneralExpenses ? (_workShare ?? 0) : 1);

  Duration? get _timePerUnit {
    final comparable = ProjectAnalytics.typicalTimePerComparableLine(
        _type, widget.projects, widget.history);
    return comparable == null
        ? null
        : Duration(
            microseconds: (comparable.inMicroseconds *
                    ProductionCalculator.comparableLinesPerUnit(_type,
                        megillahFormat: _megillahFormat))
                .round());
  }

  DateTime _expenseThrough(double units) {
    if (_overheadThrough != null) return _overheadThrough!;
    final pace = _timePerUnit;
    final estimate = pace == null
        ? null
        : QuoteCalculator.estimate(
            units: units,
            timePerUnit: pace,
            targetHourlyRate: 0,
            hoursPerDay: _allocatedHoursPerDay,
            rules: _rules,
            startingFrom: _quoteStart,
          );
    return estimate?.estimatedCompletion ??
        DateTime(_quoteStart.year, _quoteStart.month + 1, 0);
  }

  Map<String, double> _allocatedOverheads(double units) {
    final through = _expenseThrough(units);
    return {
      for (final expense in _generalExpenses)
        expense.id: ExpenseLogic.overheadShareInRange(
            expense: expense,
            from: _quoteStart,
            through: through,
            workShare: _workShare ?? 0)
    };
  }

  Future<void> _pickOverheadDate(
      {required bool start, required double units}) async {
    final proposed = start ? _quoteStart : _expenseThrough(units);
    final first = start ? DateTime(2000) : _quoteStart;
    final last = proposed.isAfter(DateTime(2100))
        ? DateTime(proposed.year + 1)
        : DateTime(2100);
    final value = await showDatePicker(
      context: context,
      initialDate: proposed.isBefore(first) ? first : proposed,
      firstDate: first,
      lastDate: last,
    );
    if (value == null || !mounted) return;
    setState(() {
      if (start) {
        _quoteStart = DateUtils.dateOnly(value);
        if (_overheadThrough?.isBefore(_quoteStart) ?? false) {
          _overheadThrough = null;
        }
      } else {
        _overheadThrough = DateUtils.dateOnly(value);
      }
    });
  }

  @override
  void dispose() {
    _unitsCtrl.dispose();
    _rateCtrl.dispose();
    _unitPriceCtrl.dispose();
    _hoursCtrl.dispose();
    _workShareCtrl.dispose();
    super.dispose();
  }

  String get _unitLabel => switch (_type) {
        ProjectType.sefer => context.l10n.pick(he: 'עמודים', en: 'pages'),
        ProjectType.megillah =>
          context.l10n.pick(he: 'פרויקטים', en: 'projects'),
        ProjectType.mezuza => context.l10n.pick(he: 'מזוזות', en: 'Mezuzot'),
        ProjectType.tefillin => context.l10n.pick(he: 'זוגות', en: 'sets'),
      };

  String get _singularLabel => switch (_type) {
        ProjectType.sefer => context.l10n.pick(he: 'עמוד', en: 'page'),
        ProjectType.megillah => context.l10n.pick(he: 'פרויקט', en: 'project'),
        ProjectType.mezuza => context.l10n.pick(he: 'מזוזה', en: 'Mezuzah'),
        ProjectType.tefillin => context.l10n.pick(he: 'זוג', en: 'set'),
      };

  @override
  Widget build(BuildContext context) {
    final pace = _timePerUnit;

    final units = MoneyInput.parse(_unitsCtrl.text) ?? 0;

    final recorded = _recordedExpensePerUnit;
    final baseExpensesPerUnit = (_expensesFromRecords && recorded != null)
        ? recorded
        : _manualPerUnit(units);
    final expensesPerUnit = baseExpensesPerUnit +
        (_includeGeneralExpenses ? _generalExpensesPerUnit(units) : 0);

    // When pricing per unit, the hourly rate that price implies is derived and
    // fed back through the same estimator, so both modes produce identical
    // timing figures and differ only in which number the writer supplies.
    final unitPrice = MoneyInput.parse(_unitPriceCtrl.text) ?? 0;
    final derivedRate = (pace == null || _priceFromHourlyRate)
        ? null
        : QuoteCalculator.impliedHourlyRate(
            totalPrice: unitPrice * units,
            units: units,
            timePerUnit: pace,
            expensesPerUnit: expensesPerUnit,
          );

    final effectiveRate = _priceFromHourlyRate
        ? (MoneyInput.parse(_rateCtrl.text) ?? 0)
        : (derivedRate ?? 0);

    final estimate = pace == null
        ? null
        : QuoteCalculator.estimate(
            units: units,
            timePerUnit: pace,
            targetHourlyRate: effectiveRate,
            hoursPerDay: _allocatedHoursPerDay,
            startingFrom: _includeGeneralExpenses ? _quoteStart : null,
            expensesPerUnit: expensesPerUnit,
            rules: _rules,
          );

    if (SoferTokens.of(context).isRules) {
      return Scaffold(
        appBar: AppBar(
            title: Text(context.l10n.pick(he: "הצעת מחיר", en: "Quote"))),
        body: SoferPage(
          maxWidth: 720,
          child: _ruledQuote(
            pace: pace,
            estimate: estimate,
            recorded: recorded,
            derivedRate: derivedRate,
            expensesPerUnit: expensesPerUnit,
            units: units,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(context.l10n
              .pick(he: "מחשבון הצעת מחיר", en: "Quote calculator")),
          centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ProjectType>(
            segments: [
              ButtonSegment(
                  value: ProjectType.sefer,
                  label: Text(
                      context.l10n.pick(he: "ספר תורה", en: "Sefer Torah"))),
              ButtonSegment(
                  value: ProjectType.mezuza,
                  label: Text(context.l10n.pick(he: "מזוזות", en: "Mezuzot"))),
              ButtonSegment(
                  value: ProjectType.tefillin,
                  label: Text(context.l10n.pick(he: "תפילין", en: "Tefillin"))),
              ButtonSegment(
                  value: ProjectType.megillah,
                  label: Text(context.l10n.pick(he: "מגילה", en: "Megillah"))),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() {
              _type = v.first;
              _unitsCtrl.text = switch (_type) {
                ProjectType.sefer => '245',
                ProjectType.mezuza => '10',
                ProjectType.tefillin => '1',
                ProjectType.megillah => '1',
              };
            }),
          ),
          const SizedBox(height: 16),
          if (pace == null)
            Card(
              color: SoferTokens.of(context).paper,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.l10n.pick(
                    he: "עדיין אין מספיק נתונים על סוג עבודה זה.\n\nהמחשבון לומד את קצב הכתיבה שלך מהעבודה שכבר תיעדת. אחרי שתמדוד זמן על פרויקט מסוג זה, תוכל לקבל כאן הצעת מחיר מבוססת על הקצב האישי שלך.",
                    en: "There is not enough data for this type of work yet.\n\nThe calculator learns your writing pace from work you have recorded. After measuring time on this type of project, it can prepare a quote based on your own pace.",
                  ),
                  style: const TextStyle(height: 1.4),
                ),
              ),
            )
          else ...[
            Card(
              color: SoferTokens.of(context).paper,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.speed, color: SoferTokens.of(context).accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.pick(
                          he: "הקצב שלך: ${formatSpan(pace)} ל$_singularLabel",
                          en: "Your pace: ${formatSpan(pace, english: true)} per $_singularLabel",
                        ),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _numberField(
                _unitsCtrl,
                context.l10n.pick(
                    he: "כמות ($_unitLabel)", en: "Quantity ($_unitLabel)"),
                Icons.numbers),
            if (_type == ProjectType.megillah) _megillahFormatField(),
            const SizedBox(height: 4),
            Text(
                context.l10n
                    .pick(he: "על מה לבסס את המחיר:", en: "Base the price on:"),
                style: TextStyle(
                    fontSize: 13, color: SoferTokens.of(context).inkMuted)),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                    value: true,
                    label: Text(context.l10n
                        .pick(he: "שכר לשעה", en: "Hourly earnings")),
                    icon: const Icon(Icons.schedule, size: 16)),
                ButtonSegment(
                    value: false,
                    label: Text(context.l10n.pick(
                        he: "מחיר ל$_singularLabel",
                        en: "Price per $_singularLabel")),
                    icon: const Icon(Icons.sell, size: 16)),
              ],
              selected: {_priceFromHourlyRate},
              onSelectionChanged: (v) =>
                  setState(() => _priceFromHourlyRate = v.first),
            ),
            const SizedBox(height: 12),
            if (_priceFromHourlyRate)
              _numberField(
                  _rateCtrl,
                  context.l10n.pick(
                      he: "שכר לשעה שאני רוצה (${_currency.symbol})",
                      en: "Desired hourly earnings (${_currency.symbol})"),
                  Icons.trending_up)
            else
              _numberField(
                  _unitPriceCtrl,
                  context.l10n.pick(
                      he: "מחיר ל$_singularLabel (${_currency.symbol})",
                      en: "Price per $_singularLabel (${_currency.symbol})"),
                  Icons.sell),
            _numberField(
                _hoursCtrl,
                context.l10n.pick(
                    he: "שעות כתיבה ביום עבודה",
                    en: "Writing hours per workday"),
                Icons.schedule),
            _expensesSection(recorded, units),
            const SizedBox(height: 16),
            if (estimate != null)
              _resultCard(estimate, derivedRate: derivedRate),
          ],
        ],
      ),
    );
  }

  /// Materials cost, either read off the expenses screen or typed in.
  ///
  /// The recorded figure is preferred because it is the writer's real cost:
  /// the parchment expenses they already logged, divided by the units those
  /// projects produced.
  /// The quote with the answer first.
  ///
  /// The modern layout runs inputs down the screen and puts the result at the
  /// bottom, which means the number you are trying to influence scrolls out of
  /// sight exactly when you change something. Here the price sits at the top and
  /// the inputs sit under it, so it moves while you watch.
  Widget _ruledQuote({
    required Duration? pace,
    required QuoteEstimate? estimate,
    required double? recorded,
    required double? derivedRate,
    required double expensesPerUnit,
    required double units,
  }) {
    final t = SoferTokens.of(context);

    if (pace == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _typeChoice(),
            const SizedBox(height: 26),
            Text(
                context.l10n
                    .pick(he: "אין עוד ממה ללמוד", en: "Not enough data yet"),
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 23, color: t.ink)),
            const SizedBox(height: 8),
            Text(
              context.l10n.pick(
                he: "המחשבון לומד את קצב הכתיבה שלך מהעבודה שתיעדת. אחרי שתמדוד זמן על עבודה מסוג זה, תקבל כאן הצעה שמבוססת על הקצב שלך ולא על ניחוש.",
                en: "The calculator learns your writing pace from recorded work. After measuring time on this type of work, the quote will be based on your pace rather than a guess.",
              ),
              style: TextStyle(
                  fontFamily: t.labelFamily,
                  fontSize: 14,
                  height: 1.8,
                  color: t.inkMuted),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: _typeChoice(),
        ),
        const SoferRule(strong: true),

        // The answer.
        if (estimate != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _priceFromHourlyRate
                        ? context.l10n
                            .pick(he: "מחיר מוצע", en: "Suggested price")
                        : context.l10n.pick(
                            he: "מה שהעבודה משאירה לך",
                            en: "What the job earns you"),
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 12,
                        letterSpacing: 1.5,
                        color: t.inkMuted)),
                const SizedBox(height: 6),
                Text(
                  _priceFromHourlyRate
                      ? formatMoney(estimate.suggestedPrice, _currency)
                      : context.l10n.pick(
                          he: "${formatMoney((derivedRate ?? 0), _currency)} לשעה",
                          en: "${formatMoney((derivedRate ?? 0), _currency)} per hour"),
                  style: TextStyle(
                      fontFamily: t.numeralFamily,
                      fontSize: 44,
                      height: 1.1,
                      color: (derivedRate ?? 1) < 0 ? t.danger : t.ink),
                ),
                const SizedBox(height: 10),
                Text(
                  _quoteSentence(estimate, derivedRate, expensesPerUnit),
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 15,
                      height: 1.8,
                      color: t.inkMuted),
                ),
              ],
            ),
          ),
          const SoferRule(),
        ],

        // What it rests on.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SoferSectionTitle(context.l10n.pick(he: "הנתונים", en: "Inputs"),
                  padding: EdgeInsets.zero),
              const SizedBox(height: 4),
              SoferStatRow(
                  context.l10n.pick(he: "הקצב שלך", en: "Your pace"),
                  context.l10n.pick(
                      he: "${formatSpan(pace)} ל$_singularLabel",
                      en: "${formatSpan(pace, english: true)} per $_singularLabel")),
              _inlineField(
                  context.l10n
                      .pick(he: "כמה $_unitLabel", en: "Number of $_unitLabel"),
                  _unitsCtrl),
              if (_type == ProjectType.megillah) _megillahFormatField(),
              _inlineChoice(
                context.l10n.pick(he: "על מה לבסס", en: "Price basis"),
                [
                  (
                    value: true,
                    label:
                        context.l10n.pick(he: "שכר לשעה", en: "Hourly earnings")
                  ),
                  (
                    value: false,
                    label: context.l10n.pick(
                        he: "מחיר ל$_singularLabel",
                        en: "Price per $_singularLabel")
                  ),
                ],
                _priceFromHourlyRate,
                (v) => setState(() => _priceFromHourlyRate = v),
              ),
              if (_priceFromHourlyRate)
                _inlineField(
                    context.l10n.pick(
                        he: "שכר לשעה שאני רוצה (${_currency.symbol})",
                        en: "Desired hourly earnings (${_currency.symbol})"),
                    _rateCtrl)
              else
                _inlineField(
                    context.l10n.pick(
                        he: "מחיר ל$_singularLabel (${_currency.symbol})",
                        en: "Price per $_singularLabel (${_currency.symbol})"),
                    _unitPriceCtrl),
              _inlineField(
                  context.l10n
                      .pick(he: "שעות כתיבה ביום", en: "Writing hours per day"),
                  _hoursCtrl),
              if (recorded != null)
                _inlineChoice(
                  context.l10n.pick(he: "עלות החומרים", en: "Material costs"),
                  [
                    (
                      value: true,
                      label: context.l10n
                          .pick(he: "מההוצאות שלי", en: "From my expenses")
                    ),
                    (
                      value: false,
                      label: context.l10n.pick(he: "ידנית", en: "Manual")
                    ),
                  ],
                  _expensesFromRecords,
                  (v) => setState(() => _expensesFromRecords = v),
                ),
              if (recorded != null && _expensesFromRecords)
                SoferStatRow(
                    context.l10n.pick(
                        he: "${_currency.symbol} ל$_singularLabel",
                        en: "${_currency.symbol} per $_singularLabel"),
                    formatMoneyExact(recorded, _currency),
                    last: true)
              else ...[
                if (recorded == null) ...[
                  const SizedBox(height: 10),
                  SoferSectionTitle(
                      context.l10n
                          .pick(he: "עלות החומרים", en: "Material costs"),
                      padding: EdgeInsets.zero),
                ],
                _manualExpensesBlock(units),
              ],
              _generalExpensesBlock(units),
            ],
          ),
        ),

        if (estimate != null) ...[
          const SoferRule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoferSectionTitle(
                    context.l10n.pick(he: "הפירוט", en: "Breakdown"),
                    padding: EdgeInsets.zero),
                const SizedBox(height: 4),
                SoferStatRow(
                    context.l10n
                        .pick(he: "זמן עבודה כולל", en: "Total work time"),
                    formatSpan(estimate.totalTime,
                        english: context.l10n.isEnglish)),
                SoferStatRow(context.l10n.pick(he: "ימי עבודה", en: "Workdays"),
                    estimate.workDays.toStringAsFixed(1)),
                SoferStatRow(
                    context.l10n
                        .pick(he: "צפי סיום", en: "Estimated completion"),
                    formatDisplayDate(
                        estimate.estimatedCompletion, _useGregorianDates,
                        english: context.l10n.isEnglish)),
                SoferStatRow(context.l10n.pick(he: "עבודה", en: "Labour"),
                    formatMoney(estimate.labour, _currency)),
                SoferStatRow(context.l10n.pick(he: "חומרים", en: "Materials"),
                    formatMoney(estimate.materials, _currency)),
                SoferStatRow(
                    context.l10n.pick(
                        he: "מחיר ל$_singularLabel",
                        en: "Price per $_singularLabel"),
                    formatMoneyExact(estimate.pricePerUnit, _currency),
                    last: true),
                const SizedBox(height: 14),
                _createProjectButton(estimate),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The quote written out: how long, when, and what the calendar takes away.
  String _quoteSentence(
      QuoteEstimate e, double? derivedRate, double expensesPerUnit) {
    final parts = <String>[
      context.l10n.pick(
          he: 'ההצעה מוצגת לפני הוצאות כלליות נוספות',
          en: 'This quote is shown before additional general expenses'),
      context.l10n.pick(
          he: "${e.units.toStringAsFixed(0)} $_unitLabel בקצב שלך הם ${formatSpan(e.totalTime)}, כלומר ${e.workDays.toStringAsFixed(1)} ימי עבודה",
          en: "At your pace, ${e.units.toStringAsFixed(0)} $_unitLabel require ${formatSpan(e.totalTime, english: true)}, or ${e.workDays.toStringAsFixed(1)} workdays"),
      context.l10n.pick(
          he: "בהתחלה מהיום העבודה תסתיים ב-${formatDisplayDate(e.estimatedCompletion, _useGregorianDates)}, בעוד ${e.plan.calendarDays} ימים",
          en: "Starting today, the project will finish on ${formatDisplayDate(e.estimatedCompletion, _useGregorianDates, english: true)}, in ${e.plan.calendarDays} days"),
    ];
    if (e.plan.skippedTotal > 0) {
      parts.add(context.l10n.pick(
          he: "${e.plan.skippedTotal} מהם אינם ימי עבודה (${formatSkippedDays(e.plan, maxReasons: 2)})",
          en: "${e.plan.skippedTotal} of those are not workdays (${formatSkippedDays(e.plan, maxReasons: 2, english: true)})"));
    }
    if (expensesPerUnit > 0) {
      parts.add(context.l10n.pick(
          he: "החומרים — ${formatMoney(e.materials, _currency)} — כלולים במחיר",
          en: "Materials — ${formatMoney(e.materials, _currency)} — are included in the price"));
    }
    return "${parts.join('. ')}.";
  }

  Widget _typeChoice() => SoferChoice<ProjectType>(
        selected: _type,
        options: [
          (
            value: ProjectType.sefer,
            label: context.l10n.pick(he: "ספר תורה", en: "Sefer Torah")
          ),
          (
            value: ProjectType.mezuza,
            label: context.l10n.pick(he: "מזוזות", en: "Mezuzot")
          ),
          (
            value: ProjectType.tefillin,
            label: context.l10n.pick(he: "תפילין", en: "Tefillin")
          ),
          (
            value: ProjectType.megillah,
            label: context.l10n.pick(he: "מגילה", en: "Megillah")
          ),
        ],
        onChanged: (v) => setState(() {
          _type = v;
          _unitsCtrl.text = switch (_type) {
            ProjectType.sefer => '245',
            ProjectType.mezuza => '10',
            ProjectType.tefillin => '1',
            ProjectType.megillah => '1',
          };
        }),
      );

  Widget _megillahFormatField() {
    final options = MegillahFormat.values;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _megillahFormat,
        decoration: InputDecoration(
          labelText:
              context.l10n.pick(he: 'מבנה המגילה', en: 'Megillah layout'),
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final format in options)
            DropdownMenuItem(
              value: format,
              child: Text(context.l10n.pick(
                he: '${MegillahFormat.displayLines(format)} שורות · ${MegillahFormat.totalPages(format)} עמודים',
                en: '${MegillahFormat.displayLines(format)} lines · ${MegillahFormat.totalPages(format)} pages',
              )),
            ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _megillahFormat = value);
        },
      ),
    );
  }

  /// A field that reads as a ruled row: label on one side, the value editable in
  /// place on the other, instead of a boxed input with a floating label.
  Widget _inlineField(String label, TextEditingController controller) {
    final t = SoferTokens.of(context);
    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 13,
                    color: t.inkMuted)),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.end,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                  fontFamily: t.numeralFamily, fontSize: 20, color: t.ink),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inlineChoice<T>(
    String label,
    List<({T value, String label})> options,
    T selected,
    ValueChanged<T> onChanged,
  ) {
    final t = SoferTokens.of(context);
    final caption = Text(label,
        style: TextStyle(
            fontFamily: t.labelFamily, fontSize: 13, color: t.inkMuted));
    final choice = SoferChoice<T>(
        options: options, selected: selected, onChanged: onChanged);

    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          // Side by side needs room for both. On a phone the control alone is
          // nearly the width of the screen, so the label goes above it instead
          // of off the edge — and the control scrolls if even that is not
          // enough.
          if (box.maxWidth < 430) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                caption,
                const SizedBox(height: 7),
                SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: choice,
                  ),
                ),
              ],
            );
          }
          return Row(children: [Expanded(child: caption), choice]);
        },
      ),
    );
  }

  Widget _expensesSection(double? recorded, double units) {
    if (recorded == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.pick(he: "עלות החומרים:", en: "Material costs:"),
              style: TextStyle(
                  fontSize: 13, color: SoferTokens.of(context).inkMuted)),
          const SizedBox(height: 6),
          _manualExpensesBlock(units),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              context.l10n.pick(
                  he: "עדיין אין הוצאות משוייכות לפרויקטים מסוג זה במסך ההוצאות, לכן העלות מוזנת כאן ידנית.",
                  en: "There are no expenses allocated to projects of this type yet, so the cost is entered manually here."),
              style: TextStyle(
                  fontSize: 12, color: SoferTokens.of(context).inkMuted),
            ),
          ),
          _generalExpensesBlock(units),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.pick(he: "עלות החומרים:", en: "Material costs:"),
            style: TextStyle(
                fontSize: 13, color: SoferTokens.of(context).inkMuted)),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
                value: true,
                label: Text(context.l10n
                    .pick(he: "מההוצאות שלי", en: "From my expenses")),
                icon: const Icon(Icons.receipt_long, size: 16)),
            ButtonSegment(
                value: false,
                label: Text(context.l10n.pick(he: "ידנית", en: "Manual")),
                icon: const Icon(Icons.edit, size: 16)),
          ],
          selected: {_expensesFromRecords},
          onSelectionChanged: (v) =>
              setState(() => _expensesFromRecords = v.first),
        ),
        const SizedBox(height: 10),
        if (_expensesFromRecords)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: SoferTokens.of(context).paper,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.receipt_long,
                      color: SoferTokens.of(context).positive),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10n.pick(
                          he: "${formatMoneyExact(recorded, _currency)} ל$_singularLabel — לפי ההוצאות שרשמת על פרויקטים מסוג זה",
                          en: "${formatMoneyExact(recorded, _currency)} per $_singularLabel — based on expenses recorded for this type of project"),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          _manualExpensesBlock(units),
        _generalExpensesBlock(units),
      ],
    );
  }

  /// Only the portion of overheads assigned to this quote is charged.
  Widget _generalExpensesBlock(double units) {
    final shares = _allocatedOverheads(units);
    final general = _generalExpenses
        .where((e) => e.currency == _currency && (shares[e.id] ?? 0) > 0)
        .toList();
    final total = general.fold(0.0, (sum, e) => sum + (shares[e.id] ?? 0));
    final t = SoferTokens.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n
                      .pick(he: 'הוצאות כלליות', en: 'General expenses'),
                  style:
                      TextStyle(fontWeight: FontWeight.bold, color: t.inkMuted),
                ),
              ),
              Switch.adaptive(
                value: _includeGeneralExpenses,
                onChanged: _generalExpenses.isEmpty
                    ? null
                    : (value) =>
                        setState(() => _includeGeneralExpenses = value),
              ),
            ],
          ),
          Text(
            context.l10n.pick(
              he: 'בהפעלה נכלל רק חלק ההוצאות שחופף לתקופת ההצעה, לפי אחוז זמן העבודה שמוקצה לה. הוצאות חודשיות חלות על החודש שנרשם; אין חזרה אוטומטית לחודשים אחרים. נכללות רק הוצאות במטבע ההצעה.',
              en: 'When enabled, only expenses overlapping the quote period are included, weighted by its share of your working time. Monthly expenses apply to their recorded month and do not repeat automatically. Only expenses in the quote currency are included.',
            ),
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
          if (_includeGeneralExpenses) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _workShareCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: context.l10n.pick(
                    he: 'אחוז מזמן העבודה הכולל שמוקצה להצעה',
                    en: 'Share of total working time assigned to this quote'),
                suffixText: '%',
                helperText: context.l10n.pick(
                    he: '100% = כל זמן העבודה; אחוז קטן יותר מאריך את צפי הסיום.',
                    en: '100% = all working time; a smaller share extends the completion estimate.'),
                helperMaxLines: 3,
                errorText: _workShare == null
                    ? context.l10n.pick(
                        he: 'יש להזין אחוז גדול מ־0 ועד 100',
                        en: 'Enter a percentage greater than 0 and up to 100')
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton(
                  onPressed: () => _pickOverheadDate(start: true, units: units),
                  child: Text(context.l10n
                          .pick(he: 'תחילת ההצעה: ', en: 'Quote start: ') +
                      formatDisplayDate(_quoteStart, _useGregorianDates,
                          english: context.l10n.isEnglish))),
              OutlinedButton(
                  onPressed: () =>
                      _pickOverheadDate(start: false, units: units),
                  child: Text(context.l10n
                          .pick(he: 'הוצאות עד: ', en: 'Expenses through: ') +
                      formatDisplayDate(
                          _expenseThrough(units), _useGregorianDates,
                          english: context.l10n.isEnglish))),
              if (_overheadThrough != null)
                TextButton(
                    onPressed: () => setState(() => _overheadThrough = null),
                    child: Text(context.l10n.pick(
                        he: 'לפי צפי הסיום', en: 'Use estimated completion'))),
            ]),
          ],
          if (general.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(context.l10n.pick(
                  he: 'אין הוצאות כלליות מתאימות לתקופה ולמטבע שנבחרו',
                  en: 'No overheads match the selected period and currency')),
            )
          else ...[
            for (final expense in general)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(expense.product),
                subtitle: Text(expense.allocation == ExpenseAllocation.month
                    ? context.l10n.pick(he: 'לפי חודש', en: 'Monthly')
                    : context.l10n.pick(he: 'לפי תקופה', en: 'By period')),
                trailing: Text(formatMoneyExact(
                    shares[expense.id] ?? 0, expense.currency)),
                onTap: () => _editGeneralExpense(expense),
              ),
            if (_includeGeneralExpenses)
              Text(
                context.l10n.pick(
                    he: '${formatMoneyExact(total / (units <= 0 ? 1 : units), _currency)} ל$_singularLabel מתווספים להוצאות ההצעה',
                    en: '${formatMoneyExact(total / (units <= 0 ? 1 : units), _currency)} per $_singularLabel added to quote expenses'),
                style: TextStyle(fontWeight: FontWeight.bold, color: t.accent),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _editGeneralExpense(Expense expense) async {
    final edited = await showExpenseEditor(
      context: context,
      existing: expense,
      projects: widget.projects,
      currency: _currency,
    );
    if (edited == null || !mounted) return;
    final next = [..._expenses];
    final index = next.indexWhere((e) => e.id == expense.id);
    if (index < 0) return;
    next[index] = edited.deleted
        ? expense.withTombstone(deletedAt: DateTime.now())
        : edited.expense;
    await _storage.saveExpenses(next);
    if (mounted) setState(() => _expenses = next);
  }

  /// What the hand-entered lines come to per unit, over [units] of them.
  double _manualPerUnit(double units) =>
      _quoteExpenses.fold(0.0, (sum, e) => sum + e.perUnitOver(units));

  /// The hand-entered costs, as lines rather than as one number.
  ///
  /// A single "materials per unit" field cannot say that the parchment is per
  /// mezuza while the delivery is paid once, which is how a job is actually
  /// priced. Each line says which of the two it is and the per-unit total is
  /// worked out from the quantity. Rendered for both layouts from one place, so
  /// the quote can do the same thing in all three themes.
  Widget _manualExpensesBlock(double units) {
    final t = SoferTokens.of(context);
    final perUnit = _manualPerUnit(units);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _quoteExpenses.length; i++)
          _manualExpenseRow(i, units),
        if (_quoteExpenses.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
                context.l10n.pick(
                    he: "לא הוזנו הוצאות — ההצעה מחושבת בלי עלות חומרים",
                    en:
                        "No expenses entered — the quote excludes material costs"),
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12,
                    color: t.inkMuted)),
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: _addManualExpense,
              style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.add, size: 18),
              label: Text(context.l10n.pick(
                  he: _quoteExpenses.isEmpty ? "הוסף הוצאה" : "הוסף עוד",
                  en: _quoteExpenses.isEmpty ? "Add expense" : "Add another")),
            ),
            const Spacer(),
            if (_quoteExpenses.isNotEmpty)
              Flexible(
                child: Text(
                  context.l10n.pick(
                      he: "${formatMoneyExact(perUnit, _currency)} ל$_singularLabel",
                      en: "${formatMoneyExact(perUnit, _currency)} per $_singularLabel"),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontFamily: t.numeralFamily,
                      fontSize: 17,
                      color: t.accent),
                ),
              ),
          ],
        ),
      ],
    );

    if (t.isCards) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          color: t.paper,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: body,
          ),
        ),
      );
    }
    return body;
  }

  Widget _manualExpenseRow(int index, double units) {
    final t = SoferTokens.of(context);
    final e = _quoteExpenses[index];

    return Container(
      decoration: t.isRules
          ? BoxDecoration(border: Border(bottom: BorderSide(color: t.rule)))
          : null,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _editManualExpense(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.expenseCategory(e.label),
                        style: TextStyle(
                            fontFamily: t.numeralFamily,
                            fontSize: 15,
                            color: t.ink)),
                    const SizedBox(height: 1),
                    Text(
                      e.perUnit
                          ? context.l10n.pick(
                              he: "לכל $_singularLabel",
                              en: "Per $_singularLabel")
                          : context.l10n.pick(
                              he: "לכל העבודה · ${formatMoneyExact(e.perUnitOver(units), _currency)} ל$_singularLabel",
                              en: "Entire job · ${formatMoneyExact(e.perUnitOver(units), _currency)} per $_singularLabel"),
                      style: TextStyle(
                          fontFamily: t.labelFamily,
                          fontSize: 11,
                          color: t.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(formatMoney(e.amount, _currency),
              style: TextStyle(
                  fontFamily: t.numeralFamily, fontSize: 17, color: t.ink)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: t.inkMuted),
            tooltip: context.l10n.pick(he: "הסר", en: "Remove"),
            onPressed: () => setState(() => _quoteExpenses.removeAt(index)),
          ),
        ],
      ),
    );
  }

  Future<void> _addManualExpense() async {
    final added = await showQuoteExpenseEditor(
        context: context, unitSingular: _singularLabel);
    if (added != null && mounted) setState(() => _quoteExpenses.add(added));
  }

  Future<void> _editManualExpense(int index) async {
    final edited = await showQuoteExpenseEditor(
      context: context,
      unitSingular: _singularLabel,
      existing: _quoteExpenses[index],
    );
    if (edited != null && mounted) {
      setState(() => _quoteExpenses[index] = edited);
    }
  }

  Widget _numberField(TextEditingController c, String label, IconData icon) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
      );

  Widget _resultCard(QuoteEstimate e, {double? derivedRate}) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.pick(he: "ההצעה", en: "Quote"),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(),
            _row(
                context.l10n
                    .pick(he: "זמן עבודה כולל:", en: "Total work time:"),
                formatSpan(e.totalTime, english: context.l10n.isEnglish)),
            _row(context.l10n.pick(he: "ימי עבודה:", en: "Workdays:"),
                e.workDays.toStringAsFixed(1)),
            _row(
                context.l10n.pick(he: "צפי סיום:", en: "Estimated completion:"),
                formatDisplayDateWithWeekday(
                    e.estimatedCompletion, _useGregorianDates,
                    english: context.l10n.isEnglish)),
            _row(
                _includeGeneralExpenses
                    ? context.l10n
                        .pick(he: 'מתחילת ההצעה:', en: 'From quote start:')
                    : context.l10n.pick(he: "מהיום:", en: "From today:"),
                context.l10n.pick(
                    he: "${e.plan.calendarDays} ימים",
                    en: "${e.plan.calendarDays} days")),
            if (e.plan.skippedTotal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  context.l10n.pick(
                      he: "כולל ${e.plan.skippedTotal} ימים שאינם ימי עבודה: ${formatSkippedDays(e.plan)}",
                      en: "Includes ${e.plan.skippedTotal} non-workdays: ${formatSkippedDays(e.plan, english: true)}"),
                  style: TextStyle(
                      fontSize: 12, color: SoferTokens.of(context).inkMuted),
                ),
              ),
            const Divider(),
            // In per-unit mode the interesting result is the reverse: what the
            // price the writer named actually pays them per hour.
            if (!_priceFromHourlyRate && derivedRate != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        context.l10n
                            .pick(he: "יוצא לך לשעה:", en: "Hourly earnings:"),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17)),
                    Text(
                      formatMoney(derivedRate, _currency),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: derivedRate >= 0
                            ? SoferTokens.of(context).positive
                            : SoferTokens.of(context).danger,
                      ),
                    ),
                  ],
                ),
              ),
            _row(
                context.l10n.pick(
                    he: "מחיר ל$_singularLabel:",
                    en: "Price per $_singularLabel:"),
                formatMoneyExact(e.pricePerUnit, _currency)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      _priceFromHourlyRate
                          ? context.l10n
                              .pick(he: "מחיר מוצע:", en: "Suggested price:")
                          : context.l10n.pick(he: "סה\"כ:", en: "Total:"),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17)),
                  Text(
                    formatMoney(e.suggestedPrice, _currency),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: SoferTokens.of(context).positive,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              context.l10n.pick(
                  he: _priceFromHourlyRate
                      ? "המחיר מחושב כך שתגיע לשכר השעה שביקשת, בתוספת עלות החומרים. צפי הסיום מחושב בלוח העברי ומדלג על שבתות, חגים, חול המועד וצומות – לפי ההגדרות שלך במסך ימי עבודה."
                      : "לפי המחיר שהזנת ובניכוי עלות החומרים – זה מה שהעבודה משאירה לך לשעה. צפי הסיום מחושב בלוח העברי ומדלג על שבתות, חגים, חול המועד וצומות – לפי ההגדרות שלך במסך ימי עבודה.",
                  en: _priceFromHourlyRate
                      ? "The price is calculated to reach your desired hourly earnings, plus material costs. The estimated completion uses the Hebrew calendar and skips Shabbat, festivals, Chol HaMoed, and fasts according to your Workdays settings."
                      : "After deducting material costs, this is what the entered price earns you per hour. The estimated completion uses the Hebrew calendar and skips Shabbat, festivals, Chol HaMoed, and fasts according to your Workdays settings."),
              style: TextStyle(
                  fontSize: 12, color: SoferTokens.of(context).inkMuted),
            ),
            const SizedBox(height: 12),
            _createProjectButton(e),
          ],
        ),
      ),
    );
  }

  Widget _createProjectButton(QuoteEstimate estimate) => OutlinedButton.icon(
        onPressed: () => _createProjectFromQuote(estimate),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: Text(context.l10n
            .pick(he: 'צור פרויקט מההצעה', en: 'Create project from quote')),
      );

  Future<void> _createProjectFromQuote(QuoteEstimate estimate) async {
    final nameCtrl = TextEditingController(
      text: context.l10n.pick(
        he: 'הצעת $_singularLabel',
        en: 'Quoted $_singularLabel',
      ),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n
            .pick(he: 'יצירת פרויקט מהצעה', en: 'Create project from quote')),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: ctx.l10n.pick(he: 'שם הפרויקט', en: 'Project name'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.l10n.cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: Text(ctx.l10n.confirm)),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    final units = estimate.units.round().clamp(1, 100000);
    final isMegillah = _type == ProjectType.megillah;
    final unitExpenses =
        estimate.units <= 0 ? 0.0 : estimate.materials / estimate.units;
    final project = Project(
      id: IdGenerator.generate(),
      name: name,
      type: _type,
      price: isMegillah ? estimate.suggestedPrice : estimate.pricePerUnit,
      expenses: isMegillah ? estimate.materials : unitExpenses,
      currency: _currency,
      targetDaily: 0,
      targetMonthly: 0,
      totalPages: switch (_type) {
        ProjectType.sefer => units,
        ProjectType.megillah =>
          MegillahFormat.totalPages(_megillahFormat) * units,
        _ => null,
      },
      linesPerPage: switch (_type) {
        ProjectType.sefer => ProductionCalculator.defaultLinesPerPage,
        ProjectType.megillah =>
          MegillahFormat.storedLinesPerPage(_megillahFormat),
        _ => null,
      },
      megillahFormat: isMegillah ? _megillahFormat : null,
      targetUnits: switch (_type) {
        ProjectType.mezuza || ProjectType.tefillin => units,
        _ => null,
      },
    );
    await _storage.saveProjects([...widget.projects, project]);
    await widget.onProjectCreated?.call(project);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.l10n.pick(
          he: 'הפרויקט נוצר וניתן לערוך אותו במסך הפרויקטים',
          en: 'The project was created and can be edited in Projects')),
    ));
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(color: SoferTokens.of(context).inkMuted)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
