import 'package:flutter/material.dart';

import 'expenses/expense_editor.dart';
import 'hebrew_utils.dart';
import 'logic/expense_logic.dart';
import 'logic/money_input.dart';
import 'logic/hebrew_work_calendar.dart';
import 'logic/project_analytics.dart';
import 'logic/quote_calculator.dart';
import 'models.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'format.dart';
import 'logic/currency.dart';

/// Works out what a job would take and what to charge for it, from the
/// writer's own measured pace rather than a guess.
class QuoteScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;

  const QuoteScreen({
    super.key,
    required this.projects,
    required this.history,
  });

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
  final StorageService _storage = StorageService();

  ProjectType _type = ProjectType.sefer;

  /// Two ways to arrive at a quote, depending on what the writer already knows:
  /// they can name the hourly rate they want and get a price, or name a price
  /// per unit and see what it actually pays per hour.
  bool _priceFromHourlyRate = true;

  final _unitsCtrl = TextEditingController(text: '245');
  final _rateCtrl = TextEditingController(text: '60');
  final _unitPriceCtrl = TextEditingController(text: '180');
  final _hoursCtrl = TextEditingController(text: '6');

  /// Materials taken from the expenses screen rather than typed in — the
  /// default whenever there is anything recorded to take them from.
  bool _expensesFromRecords = true;

  /// Costs entered by hand for this quote, as lines rather than as one number.
  ///
  /// Not persisted: a quote is for work that does not exist yet, so there is no
  /// commission to charge them to and nothing to keep.
  final List<QuoteExpense> _quoteExpenses = [];

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

  @override
  void dispose() {
    _unitsCtrl.dispose();
    _rateCtrl.dispose();
    _unitPriceCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  String get _unitLabel => switch (_type) {
        ProjectType.sefer => 'עמודים',
        ProjectType.mezuza => 'מזוזות',
        ProjectType.tefillin => 'זוגות',
      };

  String get _singularLabel => switch (_type) {
        ProjectType.sefer => 'עמוד',
        ProjectType.mezuza => 'מזוזה',
        ProjectType.tefillin => 'זוג',
      };

  @override
  Widget build(BuildContext context) {
    final pace = ProjectAnalytics.typicalTimePerUnit(
        _type, widget.projects, widget.history);

    final units = MoneyInput.parse(_unitsCtrl.text) ?? 0;

    final recorded = _recordedExpensePerUnit;
    final expensesPerUnit = (_expensesFromRecords && recorded != null)
        ? recorded
        : _manualPerUnit(units);

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
            hoursPerDay: MoneyInput.parse(_hoursCtrl.text) ?? 0,
            expensesPerUnit: expensesPerUnit,
            rules: _rules,
          );

    if (SoferTokens.of(context).isRules) {
      return Scaffold(
        appBar: AppBar(title: const Text("הצעת מחיר")),
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
      appBar: AppBar(title: const Text("מחשבון הצעת מחיר"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ProjectType>(
            segments: const [
              ButtonSegment(value: ProjectType.sefer, label: Text("ספר תורה")),
              ButtonSegment(value: ProjectType.mezuza, label: Text("מזוזות")),
              ButtonSegment(value: ProjectType.tefillin, label: Text("תפילין")),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() {
              _type = v.first;
              _unitsCtrl.text = switch (_type) {
                ProjectType.sefer => '245',
                ProjectType.mezuza => '10',
                ProjectType.tefillin => '1',
              };
            }),
          ),
          const SizedBox(height: 16),

          if (pace == null)
            Card(
              color: SoferTokens.of(context).paper,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  "עדיין אין מספיק נתונים על סוג עבודה זה.\n\n"
                  "המחשבון לומד את קצב הכתיבה שלך מהעבודה שכבר תיעדת. "
                  "אחרי שתמדוד זמן על פרויקט מסוג זה, תוכל לקבל כאן הצעת מחיר "
                  "מבוססת על הקצב האישי שלך.",
                  style: TextStyle(height: 1.4),
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
                        "הקצב שלך: ${formatSpan(pace)} "
                        "ל${_type == ProjectType.sefer ? 'עמוד' : _type == ProjectType.mezuza ? 'מזוזה' : 'סט'}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _numberField(_unitsCtrl, "כמות ($_unitLabel)", Icons.numbers),
            const SizedBox(height: 4),
            Text("על מה לבסס את המחיר:",
                style: TextStyle(fontSize: 13, color: SoferTokens.of(context).inkMuted)),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              segments: [
                const ButtonSegment(
                    value: true,
                    label: Text("שכר לשעה"),
                    icon: Icon(Icons.schedule, size: 16)),
                ButtonSegment(
                    value: false,
                    label: Text("מחיר ל$_singularLabel"),
                    icon: const Icon(Icons.sell, size: 16)),
              ],
              selected: {_priceFromHourlyRate},
              onSelectionChanged: (v) =>
                  setState(() => _priceFromHourlyRate = v.first),
            ),
            const SizedBox(height: 12),
            if (_priceFromHourlyRate)
              _numberField(
                  _rateCtrl, "שכר לשעה שאני רוצה (${_currency.symbol})", Icons.trending_up)
            else
              _numberField(_unitPriceCtrl, "מחיר ל$_singularLabel (${_currency.symbol})",
                  Icons.sell),
            _numberField(_hoursCtrl, "שעות כתיבה ביום עבודה", Icons.schedule),
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
            Text("אין עוד ממה ללמוד",
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 23, color: t.ink)),
            const SizedBox(height: 8),
            Text(
              "המחשבון לומד את קצב הכתיבה שלך מהעבודה שתיעדת. אחרי שתמדוד זמן "
              "על עבודה מסוג זה, תקבל כאן הצעה שמבוססת על הקצב שלך ולא על ניחוש.",
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
                        ? "מחיר מוצע"
                        : "מה שהעבודה משאירה לך",
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 12,
                        letterSpacing: 1.5,
                        color: t.inkMuted)),
                const SizedBox(height: 6),
                Text(
                  _priceFromHourlyRate
                      ? formatMoney(estimate.suggestedPrice, _currency)
                      : "${formatMoney((derivedRate ?? 0), _currency)} לשעה",
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
              const SoferSectionTitle("הנתונים", padding: EdgeInsets.zero),
              const SizedBox(height: 4),
              SoferStatRow("הקצב שלך", "${formatSpan(pace)} ל$_singularLabel"),
              _inlineField("כמה $_unitLabel", _unitsCtrl),
              _inlineChoice(
                "על מה לבסס",
                [
                  (value: true, label: "שכר לשעה"),
                  (value: false, label: "מחיר ל$_singularLabel"),
                ],
                _priceFromHourlyRate,
                (v) => setState(() => _priceFromHourlyRate = v),
              ),
              if (_priceFromHourlyRate)
                _inlineField("שכר לשעה שאני רוצה (${_currency.symbol})", _rateCtrl)
              else
                _inlineField("מחיר ל$_singularLabel (${_currency.symbol})", _unitPriceCtrl),
              _inlineField("שעות כתיבה ביום", _hoursCtrl),
              if (recorded != null)
                _inlineChoice(
                  "עלות החומרים",
                  const [
                    (value: true, label: "מההוצאות שלי"),
                    (value: false, label: "ידנית"),
                  ],
                  _expensesFromRecords,
                  (v) => setState(() => _expensesFromRecords = v),
                ),
              if (recorded != null && _expensesFromRecords)
                SoferStatRow("${_currency.symbol} ל$_singularLabel",
                    formatMoneyExact(recorded, _currency), last: true)
              else ...[
                if (recorded == null) ...[
                  const SizedBox(height: 10),
                  const SoferSectionTitle("עלות החומרים",
                      padding: EdgeInsets.zero),
                ],
                _manualExpensesBlock(units),
              ],
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
                const SoferSectionTitle("הפירוט", padding: EdgeInsets.zero),
                const SizedBox(height: 4),
                SoferStatRow("זמן עבודה כולל", formatSpan(estimate.totalTime)),
                SoferStatRow("ימי עבודה", estimate.workDays.toStringAsFixed(1)),
                SoferStatRow("צפי סיום",
                    formatDisplayDate(estimate.estimatedCompletion, _useGregorianDates)),
                SoferStatRow("עבודה", formatMoney(estimate.labour, _currency)),
                SoferStatRow("חומרים", formatMoney(estimate.materials, _currency)),
                SoferStatRow("מחיר ל$_singularLabel",
                    formatMoneyExact(estimate.pricePerUnit, _currency),
                    last: true),
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
      "${e.units.toStringAsFixed(0)} $_unitLabel בקצב שלך הם "
          "${formatSpan(e.totalTime)}, כלומר ${e.workDays.toStringAsFixed(1)} ימי עבודה",
      "בהתחלה מהיום העבודה תסתיים ב-"
          "${formatDisplayDate(e.estimatedCompletion, _useGregorianDates)}, "
          "בעוד ${e.plan.calendarDays} ימים",
    ];
    if (e.plan.skippedTotal > 0) {
      parts.add("${e.plan.skippedTotal} מהם אינם ימי עבודה "
          "(${formatSkippedDays(e.plan, maxReasons: 2)})");
    }
    if (expensesPerUnit > 0) {
      parts.add("החומרים — ${formatMoney(e.materials, _currency)} — כלולים במחיר");
    }
    return "${parts.join('. ')}.";
  }

  Widget _typeChoice() => SoferChoice<ProjectType>(
        selected: _type,
        options: const [
          (value: ProjectType.sefer, label: "ספר תורה"),
          (value: ProjectType.mezuza, label: "מזוזות"),
          (value: ProjectType.tefillin, label: "תפילין"),
        ],
        onChanged: (v) => setState(() {
          _type = v;
          _unitsCtrl.text = switch (_type) {
            ProjectType.sefer => '245',
            ProjectType.mezuza => '10',
            ProjectType.tefillin => '1',
          };
        }),
      );

  /// A field that reads as a ruled row: label on one side, the value editable in
  /// place on the other, instead of a boxed input with a floating label.
  Widget _inlineField(String label, TextEditingController controller) {
    final t = SoferTokens.of(context);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontFamily: t.labelFamily, fontSize: 13, color: t.inkMuted)),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
          Text("עלות החומרים:",
              style: TextStyle(
                  fontSize: 13, color: SoferTokens.of(context).inkMuted)),
          const SizedBox(height: 6),
          _manualExpensesBlock(units),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              "עדיין אין הוצאות משוייכות לפרויקטים מסוג זה במסך ההוצאות, "
              "לכן העלות מוזנת כאן ידנית.",
              style: TextStyle(fontSize: 12, color: SoferTokens.of(context).inkMuted),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("עלות החומרים:",
            style: TextStyle(fontSize: 13, color: SoferTokens.of(context).inkMuted)),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
                value: true,
                label: Text("מההוצאות שלי"),
                icon: Icon(Icons.receipt_long, size: 16)),
            ButtonSegment(
                value: false,
                label: Text("ידנית"),
                icon: Icon(Icons.edit, size: 16)),
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
                  Icon(Icons.receipt_long, color: SoferTokens.of(context).positive),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "${formatMoneyExact(recorded, _currency)} ל$_singularLabel — "
                      "לפי ההוצאות שרשמת על פרויקטים מסוג זה",
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          _manualExpensesBlock(units),
      ],
    );
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
            child: Text("לא הוזנו הוצאות — ההצעה מחושבת בלי עלות חומרים",
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
              label: Text(_quoteExpenses.isEmpty ? "הוסף הוצאה" : "הוסף עוד"),
            ),
            const Spacer(),
            if (_quoteExpenses.isNotEmpty)
              Flexible(
                child: Text(
                  "${formatMoneyExact(perUnit, _currency)} ל$_singularLabel",
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
                    Text(e.label,
                        style: TextStyle(
                            fontFamily: t.numeralFamily,
                            fontSize: 15,
                            color: t.ink)),
                    const SizedBox(height: 1),
                    Text(
                      e.perUnit
                          ? "לכל $_singularLabel"
                          : "לכל העבודה · ${formatMoneyExact(e.perUnitOver(units), _currency)} ל$_singularLabel",
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
            tooltip: "הסר",
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

  Widget _numberField(
          TextEditingController c, String label, IconData icon) =>
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
            const Text("ההצעה",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(),
            _row("זמן עבודה כולל:", formatSpan(e.totalTime)),
            _row("ימי עבודה:", e.workDays.toStringAsFixed(1)),
            _row(
                "צפי סיום:",
                formatDisplayDateWithWeekday(
                    e.estimatedCompletion, _useGregorianDates)),
            _row("מהיום:", "${e.plan.calendarDays} ימים"),
            if (e.plan.skippedTotal > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  "כולל ${e.plan.skippedTotal} ימים שאינם ימי עבודה: "
                  "${formatSkippedDays(e.plan)}",
                  style: TextStyle(fontSize: 12, color: SoferTokens.of(context).inkMuted),
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
                    const Text("יוצא לך לשעה:",
                        style: TextStyle(
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
            _row("מחיר ל$_singularLabel:",
                formatMoneyExact(e.pricePerUnit, _currency)),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_priceFromHourlyRate ? "מחיר מוצע:" : "סה\"כ:",
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
              _priceFromHourlyRate
                  ? "המחיר מחושב כך שתגיע לשכר השעה שביקשת, בתוספת עלות החומרים. "
                      "צפי הסיום מחושב בלוח העברי ומדלג על שבתות, חגים, חול "
                      "המועד וצומות – לפי ההגדרות שלך במסך ימי עבודה."
                  : "לפי המחיר שהזנת ובניכוי עלות החומרים – זה מה שהעבודה "
                      "משאירה לך לשעה. צפי הסיום מחושב בלוח העברי ומדלג על "
                      "שבתות, חגים, חול המועד וצומות – לפי ההגדרות שלך במסך "
                      "ימי עבודה.",
              style: TextStyle(fontSize: 12, color: SoferTokens.of(context).inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: SoferTokens.of(context).inkMuted)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
