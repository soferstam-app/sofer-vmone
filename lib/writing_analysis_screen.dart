import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'format.dart';
import 'hebrew_utils.dart';
import 'l10n/app_localizations.dart';
import 'logic/hebrew_clock.dart';
import 'logic/writing_analysis.dart';
import 'logic/writing_conditions.dart';
import 'models.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';

class WritingAnalysisScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;
  final String? initialProjectId;
  const WritingAnalysisScreen(
      {super.key,
      required this.projects,
      required this.history,
      this.initialProjectId});
  @override
  State<WritingAnalysisScreen> createState() => _WritingAnalysisScreenState();
}

class _WritingAnalysisScreenState extends State<WritingAnalysisScreen> {
  String? _project, _company, _processing, _side;
  ProjectType? _type;
  double? _height;
  int? _parshiya;
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  int _hourFrom = 0, _hourTo = 24;
  DateTimeRange? _period;
  WritingGroup _group = WritingGroup.weekday;
  DayStart _dayStart = DayStart.midnight;
  bool _loaded = false, _penOnly = false;
  final _temperatureMin = TextEditingController(),
      _temperatureMax = TextEditingController();
  final _humidityMin = TextEditingController(),
      _humidityMax = TextEditingController();
  @override
  void initState() {
    super.initState();
    _project = widget.initialProjectId;
    StorageService().getDayStart().then((value) {
      if (mounted) {
        setState(() {
          _dayStart = value;
          _loaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _temperatureMin.dispose();
    _temperatureMax.dispose();
    _humidityMin.dispose();
    _humidityMax.dispose();
    super.dispose();
  }

  static const _yiddishLabels = <String, String>{
    'Weekday': 'טאג אין דער וואך',
    'Hour of day': 'שעה פון טאג',
    'Work type': 'סארט כתיבה',
    'Parchment company': 'קלף־פירמע',
    'Parchment processing': 'עיבוד פונעם קלף',
    'Letter height': 'הייך פונעם כתב',
    'Temperature and humidity': 'טעמפעראטור און פייכטקייט',
    'Enter temperature from -40 to 80 and humidity from 0 to 100.':
        'גיט אריין טעמפעראטור פון ‎-40 ביז 80 און פייכטקייט פון 0 ביז 100.',
    'Minimum must be no greater than maximum.':
        'דער קלענסטער ווערט קען נישט זיין העכער פונעם גרעסטן.',
    'From hour (inclusive)': 'פון דער שעה (אריינגערעכנט)',
    'Until hour (exclusive)': 'ביז דער שעה (אויסגערעכנט)',
    'Not recorded': 'נישט פארשריבן',
    'Hand processed': 'עבודת יד',
    'Machine processed': 'מיט א מאשין',
    'Letter height in mm': 'הייך פונעם כתב אין מ״מ',
    'Shel Rosh / Shel Yad': 'של ראש / של יד',
    'Temperature from °C': 'טעמפעראטור פון °C',
    'Temperature to °C': 'טעמפעראטור ביז °C',
    'Humidity from %': 'פייכטקייט פון %',
    'Humidity to %': 'פייכטקייט ביז %',
    'Filter and compare': 'אויסקלויבן און פארגלייכן',
    'All dates': 'אלע תקופות',
    'Reset filters': 'אויסוואל צוריקשטעלן',
    'The hour range crosses midnight; equal hours mean a full day.':
        'די שעה׳ן גייען אריבער חצות. צוויי גלייכע שעה׳ן מיינען א גאנצן טאג.',
    'Compare by': 'פארגלייכן לויט',
    'Pace using pen time only': 'קצב לויט דער שרייבצייט אליין',
    'The default includes reading and correction in professional work.':
        'געווענליך רעכנט מען אויך אריין לייענען און פארריכטן אין דער ארבעטסצייט.',
    'Measure: equivalent Sefer Torah lines per hour. Compare within the same work type and letter height.':
        'די מאָס איז שורות לויט דעם חשבון פון א ספר תורה אויף א שעה. פארגלייכט דעם זעלבן סארט כתיבה מיט דער זעלבער הייך פונעם כתב.',
    'No data matches these filters. Record conditions in the project or session conditions.':
        'קיין רישומים שטימען נישט מיט דעם אויסוואל. גיט אריין די שרייב־באדינגונגען אינעם פראיעקט אדער אין דער ישיבה.',
    'Limited data: fewer than 3 identified sessions or 30 measured minutes.':
        'ווייניג דאטן. ווייניגער ווי 3 דערקענטע ישיבות אדער 30 געמאסטענע מינוט.',
    'Comparisons show associations, not causes. Historical missing values stay missing. Humidity and temperature are recorded manually per session. Output across hours is apportioned by pen time in each interval.':
        'די פארגלייכונגען ווייזן קשרים צווישן די דאטן. פריערדיגע דאטן וואס פעלן בלייבן אויסגעלאזט. פייכטקייט און טעמפעראטור ווערן אריינגעגעבן מיט דער האנט פאר יעדער ישיבה. שורות וואס גייען אריבער מערערע שעה׳ן ווערן צעטיילט לויט דער שרייבצייט אין יעדן טייל.',
    'Writing conditions and pace': 'שרייב־באדינגונגען און קצב',
    'lines/hour': 'שורות אויף א שעה',
  };

  String t(String he, String en, [String? yi]) =>
      context.l10n.pick(he: he, en: en, yi: yi ?? _yiddishLabels[en]);
  String typeName(ProjectType type) => switch (type) {
        ProjectType.sefer => t('ספר תורה', 'Sefer Torah'),
        ProjectType.tefillin => t('תפילין', 'Tefillin'),
        ProjectType.mezuza => t('מזוזות', 'Mezuzot'),
        ProjectType.megillah => t('מגילה', 'Megillah')
      };
  String weekday(int day) => context.l10n.isEnglish
      ? const [
          'Sunday',
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Shabbat'
        ][day - 1]
      : const [
          'ראשון',
          'שני',
          'שלישי',
          'רביעי',
          'חמישי',
          'שישי',
          'שבת'
        ][day - 1];
  String groupName(WritingGroup group) => switch (group) {
        WritingGroup.weekday => t('יום בשבוע', 'Weekday'),
        WritingGroup.hour => t('שעה ביום', 'Hour of day'),
        WritingGroup.type => t('סוג כתיבה', 'Work type'),
        WritingGroup.company => t('חברת קלף', 'Parchment company'),
        WritingGroup.processing => t('עיבוד קלף', 'Parchment processing'),
        WritingGroup.height => t('גובה כתב', 'Letter height'),
        WritingGroup.climate => t('טמפרטורה ולחות', 'Temperature and humidity')
      };
  double? number(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));
  String? get climateError {
    for (final pair in [
      (_temperatureMin, _temperatureMax, -40.0, 80.0),
      (_humidityMin, _humidityMax, 0.0, 100.0)
    ]) {
      for (final c in [pair.$1, pair.$2]) {
        final n = number(c);
        if (c.text.trim().isNotEmpty &&
            (n == null || !n.isFinite || n < pair.$3 || n > pair.$4)) {
          return t('יש להזין טמפרטורה בין ‎-40 ל־80 ולחות בין 0 ל־100.',
              'Enter temperature from -40 to 80 and humidity from 0 to 100.');
        }
      }
      if (number(pair.$1) != null &&
          number(pair.$2) != null &&
          number(pair.$1)! > number(pair.$2)!) {
        return t('ערך המינימום חייב להיות קטן מהמקסימום או שווה לו.',
            'Minimum must be no greater than maximum.');
      }
    }
    return null;
  }

  Widget choice(String label, String value, List<(String, String)> items,
          void Function(String) changed) =>
      DropdownButtonFormField<String>(
          key: ValueKey('$label:$value:${items.length}'),
          initialValue: items.any((item) => item.$1 == value) ? value : '*',
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final item in items)
              DropdownMenuItem(
                  value: item.$1,
                  child: Text(item.$2, overflow: TextOverflow.ellipsis))
          ],
          onChanged: (v) {
            if (v != null) setState(() => changed(v));
          });
  List<(String, String)> get all => [('*', t('הכול', 'All'))];
  String? optional(String v) => v == '*' ? null : v;
  Future<void> pickPeriod() async {
    final now = DateTime.now();
    final years = [now.year, for (final s in widget.history) s.startTime.year];
    final first = years.reduce(math.min), last = years.reduce(math.max);
    final value = await showDateRangePicker(
        context: context,
        initialDateRange: _period,
        firstDate: DateTime(math.min(first, 1900)),
        lastDate: DateTime(math.max(last, now.year + 1), 12, 31));
    if (value != null && mounted) setState(() => _period = value);
  }

  void reset() => setState(() {
        _project = null;
        _company = null;
        _processing = null;
        _side = null;
        _type = null;
        _height = null;
        _parshiya = null;
        _period = null;
        _weekdays = {1, 2, 3, 4, 5, 6, 7};
        _hourFrom = 0;
        _hourTo = 24;
        _temperatureMin.clear();
        _temperatureMax.clear();
        _humidityMin.clear();
        _humidityMax.clear();
      });
  Widget filters() {
    final conditions = widget.history
        .where((s) => !s.isDeleted)
        .map(WritingConditions.session)
        .toList();
    final companies = conditions
        .map((c) => c.company)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final heights = conditions
        .map((c) => c.heightMm)
        .whereType<double>()
        .toSet()
        .toList()
      ..sort();
    Widget numeric(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}));
    final fields = [
      choice(
          t('פרויקט', 'Project'),
          _project ?? '*',
          [...all, for (final p in widget.projects) (p.id, p.name)],
          (v) => _project = optional(v)),
      choice(t('סוג כתיבה', 'Work type'), _type?.name ?? '*', [
        ...all,
        for (final type in ProjectType.values) (type.name, typeName(type))
      ], (v) {
        _type = v == '*' ? null : ProjectType.values.byName(v);
        _side = null;
        _parshiya = null;
      }),
      choice(
          t('משעה (כולל)', 'From hour (inclusive)'),
          '$_hourFrom',
          [
            for (var h = 0; h < 24; h++)
              ('$h', '${h.toString().padLeft(2, '0')}:00')
          ],
          (v) => _hourFrom = int.parse(v)),
      choice(
          t('עד שעה (לא כולל)', 'Until hour (exclusive)'),
          '$_hourTo',
          [
            for (var h = 1; h <= 24; h++)
              ('$h', '${h.toString().padLeft(2, '0')}:00')
          ],
          (v) => _hourTo = int.parse(v)),
      choice(
          t('חברת קלף', 'Parchment company'),
          _company ?? '*',
          [
            ...all,
            ('', t('לא צוין', 'Not recorded')),
            for (final c in companies) (c, c)
          ],
          (v) => _company = optional(v)),
      choice(
          t('עיבוד קלף', 'Parchment processing'),
          _processing ?? '*',
          [
            ...all,
            ('', t('לא צוין', 'Not recorded')),
            ('hand', t('עבודת יד', 'Hand processed')),
            ('machine', t('מכונה', 'Machine processed'))
          ],
          (v) => _processing = optional(v)),
      choice(
          t('גובה כתב במ״מ', 'Letter height in mm'),
          _height?.toString() ?? '*',
          [
            ...all,
            ('-1.0', t('לא צוין', 'Not recorded')),
            for (final h in heights) ('$h', '$h')
          ],
          (v) => _height = v == '*' ? null : double.parse(v)),
      if (_type == ProjectType.tefillin) ...[
        choice(
            t('פרשייה', 'Parashah'),
            _parshiya?.toString() ?? '*',
            [
              ...all,
              ('1', 'קדש'),
              ('2', 'והיה כי יביאך'),
              ('3', 'שמע'),
              ('4', 'והיה אם שמע')
            ],
            (v) => _parshiya = v == '*' ? null : int.parse(v)),
        choice(
            t('ראש / יד', 'Shel Rosh / Shel Yad'),
            _side ?? '*',
            [
              ...all,
              ('head', t('של ראש', 'Shel Rosh')),
              ('hand', t('של יד', 'Shel Yad'))
            ],
            (v) => _side = optional(v)),
      ],
      numeric(_temperatureMin, t('טמפרטורה מ־ °C', 'Temperature from °C')),
      numeric(_temperatureMax, t('טמפרטורה עד °C', 'Temperature to °C')),
      numeric(_humidityMin, t('לחות מ־ %', 'Humidity from %')),
      numeric(_humidityMax, t('לחות עד %', 'Humidity to %')),
    ];
    return ExpansionTile(
        initiallyExpanded: true,
        maintainState: true,
        title: Text(t('סינון והשוואה', 'Filter and compare')),
        children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed: pickPeriod,
                          icon: const Icon(Icons.date_range),
                          label: Text(_period == null
                              ? t('כל התקופות', 'All dates')
                              : '${formatDisplayDate(_period!.start, true)} – ${formatDisplayDate(_period!.end, true)}')),
                      TextButton(
                          onPressed: reset,
                          child: Text(t('איפוס מסננים', 'Reset filters')))
                    ]),
                    Wrap(spacing: 6, children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                            label: Text(weekday(day)),
                            selected: _weekdays.contains(day),
                            onSelected: (selected) => setState(() {
                                  if (selected) {
                                    _weekdays.add(day);
                                  } else {
                                    _weekdays.remove(day);
                                  }
                                }))
                    ]),
                    if (_hourFrom >= _hourTo)
                      Text(t(
                          'טווח השעות חוצה חצות; שעות זהות מייצגות יממה מלאה.',
                          'The hour range crosses midnight; equal hours mean a full day.')),
                    LayoutBuilder(builder: (context, box) {
                      final wide = box.maxWidth >
                          680 * MediaQuery.textScalerOf(context).scale(1);
                      return Wrap(spacing: 16, runSpacing: 12, children: [
                        for (final field in fields)
                          SizedBox(
                              width:
                                  wide ? (box.maxWidth - 16) / 2 : box.maxWidth,
                              child: field)
                      ]);
                    }),
                  ]))
        ]);
  }

  String bucketName(String key) {
    if (key == '?') return t('לא צוין', 'Not recorded');
    return switch (_group) {
      WritingGroup.weekday => weekday(int.parse(key)),
      WritingGroup.hour =>
        '${int.parse(key).toString().padLeft(2, '0')}:00–${(int.parse(key) + 1).toString().padLeft(2, '0')}:00',
      WritingGroup.type => typeName(ProjectType.values.byName(key)),
      WritingGroup.processing => key == 'hand'
          ? t('עבודת יד', 'Hand processed')
          : t('מכונה', 'Machine processed'),
      WritingGroup.height => '$key ${t('מ״מ', 'mm')}',
      WritingGroup.climate => (() {
          final parts = key.split(':').map(int.parse).toList();
          return '${parts[0]}–${parts[0] + 2}°C · ${parts[1]}–${math.min(parts[1] + 10, 100)}%';
        })(),
      WritingGroup.company => key,
    };
  }

  double? rate(WritingBucket b) =>
      _penOnly ? b.penLinesPerHour : b.linesPerHour;
  Widget results() {
    if (climateError != null) {
      return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(climateError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)));
    }
    final result = WritingAnalysis.build(
        projects: widget.projects,
        history: widget.history,
        group: _group,
        dayStart: _dayStart,
        filter: WritingFilter(
            projectId: _project,
            type: _type,
            from: _period?.start,
            to: _period?.end,
            weekdays: _weekdays,
            hourFrom: _hourFrom,
            hourTo: _hourTo,
            company: _company,
            processing: _processing,
            height: _height,
            parshiya: _parshiya,
            side: _side,
            minTemperature: number(_temperatureMin),
            maxTemperature: number(_temperatureMax),
            minHumidity: number(_humidityMin),
            maxHumidity: number(_humidityMax)));
    final total = result.total;
    final maxRate =
        result.buckets.fold<double>(0, (n, b) => math.max(n, rate(b) ?? 0));
    final tokens = SoferTokens.of(context);
    return Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          choice(
              t('השוואה לפי', 'Compare by'),
              _group.name,
              [for (final g in WritingGroup.values) (g.name, groupName(g))],
              (v) => _group = WritingGroup.values.byName(v)),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title:
                  Text(t('קצב לפי זמן כתיבה בלבד', 'Pace using pen time only')),
              subtitle: Text(t('ברירת המחדל כוללת קריאה ותיקון בזמן העבודה.',
                  'The default includes reading and correction in professional work.')),
              value: _penOnly,
              onChanged: (value) => setState(() => _penOnly = value)),
          Text(t(
              'המדד: שורות שקולות לס״ת לשעה. מומלץ להשוות בתוך אותו סוג כתיבה וגובה כתב.',
              'Measure: equivalent Sefer Torah lines per hour. Compare within the same work type and letter height.')),
          const SizedBox(height: 12),
          Text(
              t(
                  'סך הכול: ${total.lines.toStringAsFixed(1)} שורות שקולות · ${formatClock(Duration(milliseconds: total.workMs.round()))} עבודה · ${total.sittings} ישיבות מזוהות',
                  'Total: ${total.lines.toStringAsFixed(1)} equivalent lines · ${formatClock(Duration(milliseconds: total.workMs.round()))} work · ${total.sittings} identified sessions',
                  'סך־הכל: ${total.lines.toStringAsFixed(1)} שורות לויטן חשבון פון א ספר תורה · ${formatClock(Duration(milliseconds: total.workMs.round()))} ארבעט · ${total.sittings} דערקענטע ישיבות'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(t(
              'מתוכן קריאה / תיקון: ${formatClock(Duration(milliseconds: total.readingMs.round()))}',
              'Reading / correction within work: ${formatClock(Duration(milliseconds: total.readingMs.round()))}',
              'דערפון לייענען / פארריכטן: ${formatClock(Duration(milliseconds: total.readingMs.round()))}')),
          if (total.unknownVisits.isNotEmpty)
            Text(t(
                '${total.unknownVisits.length} רשומות ללא שיוך לישיבה; הן אינן מגדילות את מספר הישיבות.',
                '${total.unknownVisits.length} records lack a session identity and do not increase the session count.',
                '${total.unknownVisits.length} רישומים האבן נישט קיין באשטימטע ישיבה און גייען נישט אריין אין דער צאל ישיבות.')),
          if (result.excludedWithoutTime > 0)
            Text(t(
                '${result.excludedWithoutTime} רשומות ללא זמן מדוד הושמטו.',
                '${result.excludedWithoutTime} records without measured time were excluded.',
                '${result.excludedWithoutTime} רישומים אן געמאסטענע צייט זענען אויסגעלאזט.')),
          if (result.excludedUnknownHour > 0)
            Text(t(
                '${result.excludedUnknownHour} רשומות הושמטו מהסינון לפי שעות כי אין להן מקטעי זמן ידועים.',
                '${result.excludedUnknownHour} records were excluded from hour analysis because their actual intervals are unknown.',
                '${result.excludedUnknownHour} רישומים זענען אויסגעלאזט פון דעם חשבון לויט שעה׳ן ווייל די צייט־טיילן זענען נישט באקאנט.')),
          const SizedBox(height: 12),
          if (result.buckets.isEmpty)
            Text(t(
                'אין נתונים המתאימים למסננים. ניתן להזין תנאי כתיבה בפרויקט או בתנאי הישיבה.',
                'No data matches these filters. Record conditions in the project or session conditions.')),
          for (final bucket in result.buckets)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          children: [
                            Text(bucketName(bucket.key),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text(rate(bucket) == null
                                ? '—'
                                : '${rate(bucket)!.toStringAsFixed(1)} ${t('שורות לשעה', 'lines/hour')}')
                          ]),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                          value: maxRate <= 0
                              ? 0
                              : ((rate(bucket) ?? 0) / maxRate).clamp(0, 1),
                          minHeight: 8,
                          color: bucket.enoughData
                              ? tokens.accent
                              : tokens.inkMuted),
                      Text(t(
                          '${bucket.sittings} ישיבות מזוהות · ${formatClock(Duration(milliseconds: bucket.workMs.round()))} עבודה · ${bucket.lines.toStringAsFixed(1)} שורות שקולות',
                          '${bucket.sittings} identified sessions · ${formatClock(Duration(milliseconds: bucket.workMs.round()))} work · ${bucket.lines.toStringAsFixed(1)} equivalent lines',
                          '${bucket.sittings} דערקענטע ישיבות · ${formatClock(Duration(milliseconds: bucket.workMs.round()))} ארבעט · ${bucket.lines.toStringAsFixed(1)} שורות לויטן חשבון פון א ספר תורה')),
                      if (!bucket.enoughData)
                        Text(t(
                            'מעט נתונים: פחות מ־3 ישיבות מזוהות או חצי שעת מדידה.',
                            'Limited data: fewer than 3 identified sessions or 30 measured minutes.')),
                    ])),
          const SizedBox(height: 12),
          Text(t(
              'ההשוואה מציגה קשרים בנתונים, ואינה מוכיחה מה גרם לשינוי בקצב. נתונים שלא תועדו בעבר נשארים חסרים. לחות וטמפרטורה נרשמות ידנית לכל ישיבה. הספק שחוצה שעות מחולק לפי זמן הכתיבה במקטעים.',
              'Comparisons show associations, not causes. Historical missing values stay missing. Humidity and temperature are recorded manually per session. Output across hours is apportioned by pen time in each interval.')),
        ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(t('תנאי כתיבה וקצב', 'Writing conditions and pace'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SoferPage(
              maxWidth: 1100,
              child: ListView(children: [filters(), results()])));
}
