import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../logic/writing_conditions.dart';

class WritingConditionsController {
  late final TextEditingController company;
  late final TextEditingController height;
  late final TextEditingController temperature;
  late final TextEditingController humidity;
  String processing;
  WritingConditionsController(WritingConditions value)
      : processing = value.processing {
    company = TextEditingController(text: value.company);
    height = TextEditingController(text: value.heightMm?.toString() ?? '');
    temperature =
        TextEditingController(text: value.temperatureC?.toString() ?? '');
    humidity = TextEditingController(text: value.humidity?.toString() ?? '');
  }
  factory WritingConditionsController.draft(
      Object? raw, WritingConditions fallback) {
    final c = WritingConditionsController(
        raw is Map ? WritingConditions.fromJson(raw) : fallback);
    final text = raw is Map ? raw['_text'] : null;
    if (text is Map) {
      if (text['company'] is String) c.company.text = text['company'] as String;
      if (text['height'] is String) c.height.text = text['height'] as String;
      if (text['temperature'] is String) {
        c.temperature.text = text['temperature'] as String;
      }
      if (text['humidity'] is String) {
        c.humidity.text = text['humidity'] as String;
      }
    }
    return c;
  }
  Map<String, dynamic> get draftJson => {
        ...value.toJson(),
        '_text': {
          'company': company.text,
          'height': height.text,
          'temperature': temperature.text,
          'humidity': humidity.text
        }
      };
  static double? number(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));
  String? error() {
    for (final field in [
      (height, 0.1, 100.0),
      (temperature, -40.0, 80.0),
      (humidity, 0.0, 100.0)
    ]) {
      if (field.$1.text.trim().isEmpty) continue;
      final n = number(field.$1.text);
      if (n == null || !n.isFinite || n < field.$2 || n > field.$3) {
        return 'range';
      }
    }
    return null;
  }

  WritingConditions get value => WritingConditions.fromJson({
        'company': company.text.trim(),
        'processing': processing,
        'heightMm': number(height.text),
        'temperatureC': number(temperature.text),
        'humidity': number(humidity.text),
      });
  void dispose() {
    company.dispose();
    height.dispose();
    temperature.dispose();
    humidity.dispose();
  }
}

class WritingConditionsFields extends StatefulWidget {
  final WritingConditionsController controller;
  final bool environment;
  final bool enabled;
  const WritingConditionsFields(
      {super.key,
      required this.controller,
      this.environment = true,
      this.enabled = true});
  @override
  State<WritingConditionsFields> createState() =>
      _WritingConditionsFieldsState();
}

class _WritingConditionsFieldsState extends State<WritingConditionsFields> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    Widget numeric(TextEditingController controller, String he, String en,
            String yi, double min, double max) =>
        TextFormField(
            controller: controller,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: InputDecoration(
                labelText: context.l10n.pick(he: he, en: en, yi: yi)),
            validator: (text) {
              if (text == null || text.trim().isEmpty) return null;
              final n = WritingConditionsController.number(text);
              return n == null || !n.isFinite || n < min || n > max
                  ? context.l10n.pick(
                      he: 'יש להזין ערך בין $min ל־$max',
                      en: 'Enter a value between $min and $max')
                  : null;
            });
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(
          controller: c.company,
          enabled: widget.enabled,
          decoration: InputDecoration(
              labelText: context.l10n.pick(
                  he: 'חברת הקלף (רשות)', en: 'Parchment company (optional)'))),
      DropdownButtonFormField<String>(
          initialValue: c.processing,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: context.l10n
                  .pick(he: 'עיבוד הקלף', en: 'Parchment processing')),
          items: [
            for (final item in [
              ('', 'לא צוין', 'Not specified', 'נישט אנגעגעבן'),
              ('hand', 'עבודת יד', 'Hand processed', 'עבודת יד'),
              ('machine', 'מכונה', 'Machine processed', 'מיט א מאשין')
            ])
              DropdownMenuItem(
                  value: item.$1,
                  child: Text(
                      context.l10n.pick(he: item.$2, en: item.$3, yi: item.$4)))
          ],
          onChanged: widget.enabled
              ? (value) => setState(() => c.processing = value ?? '')
              : null),
      numeric(
          c.height,
          'גובה הכתב במ״מ (רשות)',
          'Letter height in mm (optional)',
          'די הייך פונעם כתב אין מ״מ (אויב איר ווילט)',
          0.1,
          100),
      if (widget.environment) ...[
        numeric(
            c.temperature,
            'טמפרטורה בחדר °C (רשות)',
            'Room temperature °C (optional)',
            'טעמפעראטור אין צימער °C (אויב איר ווילט)',
            -40,
            80),
        numeric(c.humidity, 'לחות בחדר % (רשות)', 'Room humidity % (optional)',
            'פייכטקייט אין צימער % (אויב איר ווילט)', 0, 100),
      ],
    ]);
  }
}

Future<WritingConditions?> showWritingConditions(
        BuildContext context, WritingConditions initial,
        {bool readOnly = false}) =>
    showDialog<WritingConditions>(
        context: context,
        builder: (_) =>
            _WritingConditionsDialog(initial: initial, readOnly: readOnly));

class _WritingConditionsDialog extends StatefulWidget {
  final WritingConditions initial;
  final bool readOnly;
  const _WritingConditionsDialog(
      {required this.initial, required this.readOnly});
  @override
  State<_WritingConditionsDialog> createState() =>
      _WritingConditionsDialogState();
}

class _WritingConditionsDialogState extends State<_WritingConditionsDialog> {
  late final WritingConditionsController _controller =
      WritingConditionsController(widget.initial);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            context.l10n.pick(he: 'תנאי הישיבה', en: 'Session conditions')),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(context.l10n.pick(
                          he: widget.readOnly
                              ? 'הנתונים נלכדו בתחילת הישיבה. לשינוי, סיים את הישיבה והגדר את הבאה.'
                              : 'כל השדות הם רשות. תנאי החדר חלים על הישיבה הבאה בלבד.',
                          en: widget.readOnly
                              ? 'These values were captured at the start. Finish this session to change the next one.'
                              : 'All fields are optional. Room conditions apply to the next session only.')),
                      WritingConditionsFields(
                          controller: _controller, enabled: !widget.readOnly),
                    ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel)),
          if (!widget.readOnly)
            FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(context, _controller.value);
                  }
                },
                child: Text(context.l10n
                    .pick(he: 'שמור לישיבה הבאה', en: 'Save for next session')))
        ],
      );
}
