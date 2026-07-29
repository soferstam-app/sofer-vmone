import 'package:flutter/material.dart';

import 'hebrew_utils.dart';
import 'logic/project_analytics.dart';
import 'logic/quote_calculator.dart';
import 'models.dart';
import 'storage_service.dart';

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
  final _expensesCtrl = TextEditingController(text: '0');

  bool _fridayMotzeiHalfDay = false;
  bool _useGregorianDates = false;

  @override
  void initState() {
    super.initState();
    _storage.getFridayMotzeiHalfDay().then((v) {
      if (mounted) setState(() => _fridayMotzeiHalfDay = v);
    });
    _storage.getUseGregorianDates().then((v) {
      if (mounted) setState(() => _useGregorianDates = v);
    });
  }

  @override
  void dispose() {
    _unitsCtrl.dispose();
    _rateCtrl.dispose();
    _unitPriceCtrl.dispose();
    _hoursCtrl.dispose();
    _expensesCtrl.dispose();
    super.dispose();
  }

  String get _unitLabel => switch (_type) {
        ProjectType.sefer => 'עמודים',
        ProjectType.mezuza => 'מזוזות',
        ProjectType.tefillin => 'סטים',
      };

  String get _singularLabel => switch (_type) {
        ProjectType.sefer => 'עמוד',
        ProjectType.mezuza => 'מזוזה',
        ProjectType.tefillin => 'סט',
      };

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final m = d.inMinutes.remainder(60);
      return m > 0 ? "${d.inHours} שע' $m דק'" : "${d.inHours} שע'";
    }
    return "${d.inMinutes} דק'";
  }

  @override
  Widget build(BuildContext context) {
    final pace = ProjectAnalytics.typicalTimePerUnit(
        _type, widget.projects, widget.history);

    final units = double.tryParse(_unitsCtrl.text) ?? 0;
    final expensesPerUnit = double.tryParse(_expensesCtrl.text) ?? 0;

    // When pricing per unit, the hourly rate that price implies is derived and
    // fed back through the same estimator, so both modes produce identical
    // timing figures and differ only in which number the writer supplies.
    final unitPrice = double.tryParse(_unitPriceCtrl.text) ?? 0;
    final derivedRate = (pace == null || _priceFromHourlyRate)
        ? null
        : QuoteCalculator.impliedHourlyRate(
            totalPrice: unitPrice * units,
            units: units,
            timePerUnit: pace,
            expensesPerUnit: expensesPerUnit,
          );

    final effectiveRate = _priceFromHourlyRate
        ? (double.tryParse(_rateCtrl.text) ?? 0)
        : (derivedRate ?? 0);

    final estimate = pace == null
        ? null
        : QuoteCalculator.estimate(
            units: units,
            timePerUnit: pace,
            targetHourlyRate: effectiveRate,
            hoursPerDay: double.tryParse(_hoursCtrl.text) ?? 0,
            expensesPerUnit: expensesPerUnit,
            fridayMotzeiHalfDay: _fridayMotzeiHalfDay,
          );

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
              color: Colors.orange.shade50,
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
              color: Colors.deepPurple.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.speed, color: Colors.deepPurple.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "הקצב שלך: ${_formatDuration(pace)} "
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
            const Text("על מה לבסס את המחיר:",
                style: TextStyle(fontSize: 13, color: Colors.black54)),
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
                  _rateCtrl, "שכר לשעה שאני רוצה (₪)", Icons.trending_up)
            else
              _numberField(_unitPriceCtrl, "מחיר ל$_singularLabel (₪)",
                  Icons.sell),
            _numberField(_hoursCtrl, "שעות כתיבה ביום עבודה", Icons.schedule),
            _numberField(
                _expensesCtrl, "עלות חומרים ליחידה (₪)", Icons.shopping_bag),
            const SizedBox(height: 16),
            if (estimate != null)
              _resultCard(estimate, derivedRate: derivedRate),
          ],
        ],
      ),
    );
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
            _row("זמן עבודה כולל:", _formatDuration(e.totalTime)),
            _row("ימי עבודה:", e.workDays.toStringAsFixed(1)),
            _row("צפי סיום:",
                formatDisplayDate(e.estimatedCompletion, _useGregorianDates)),
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
                      "₪${derivedRate.toStringAsFixed(0)}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: derivedRate >= 0
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            _row("מחיר ל$_singularLabel:",
                "₪${e.pricePerUnit.toStringAsFixed(2)}"),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_priceFromHourlyRate ? "מחיר מוצע:" : "סה\"כ:",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17)),
                  Text(
                    "₪${e.suggestedPrice.toStringAsFixed(0)}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _priceFromHourlyRate
                  ? "המחיר מחושב כך שתגיע לשכר השעה שביקשת, בתוספת עלות החומרים. "
                      "צפי הסיום מדלג על שבתות וחגים."
                  : "לפי המחיר שהזנת ובניכוי עלות החומרים – זה מה שהעבודה "
                      "משאירה לך לשעה. צפי הסיום מדלג על שבתות וחגים.",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
            Text(label, style: const TextStyle(color: Colors.black54)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
