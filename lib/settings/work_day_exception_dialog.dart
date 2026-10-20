import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';

import '../hebrew_utils.dart';
import '../l10n/app_localizations.dart';
import '../logic/hebrew_work_calendar.dart';

typedef WorkDayExceptionChoice = ({DateTime date, WorkDayException exception});

class WorkDayExceptionDialog extends StatefulWidget {
  final DateTime date;
  final WorkDayException? existing;
  final bool gregorian;
  final Set<String> takenDates;

  const WorkDayExceptionDialog({
    super.key,
    required this.date,
    this.existing,
    required this.gregorian,
    required this.takenDates,
  });

  @override
  State<WorkDayExceptionDialog> createState() => _WorkDayExceptionDialogState();
}

class _WorkDayExceptionDialogState extends State<WorkDayExceptionDialog> {
  late DateTime _date = widget.date;
  late bool _gregorian = widget.gregorian;
  late DayWeight _weight = widget.existing?.weight ?? DayWeight.none;
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _setHebrew(int year, int month, int day) {
    final probe = JewishDate.initDate(
        jewishYear: year, jewishMonth: 1, jewishDayOfMonth: 1);
    final validMonth = month == 13 && !probe.isJewishLeapYear() ? 12 : month;
    probe.setJewishDate(year, validMonth, 1);
    probe.setJewishDate(
        year, validMonth, day.clamp(1, probe.getDaysInJewishMonth()));
    setState(() {
      _date = probe.getGregorianCalendar();
      _error = null;
    });
  }

  List<Widget> _hebrewFields() {
    final jd = JewishDate.fromDateTime(_date);
    final year = jd.getJewishYear();
    final month = jd.getJewishMonth();
    final day = jd.getJewishDayOfMonth();
    final currentYear = JewishDate.fromDateTime(DateTime.now()).getJewishYear();
    final firstYear = year < currentYear - 100 ? year : currentYear - 100;
    final lastYear = year > currentYear + 100 ? year : currentYear + 100;
    final months = [
      7,
      8,
      9,
      10,
      11,
      12,
      if (jd.isJewishLeapYear()) 13,
      1,
      2,
      3,
      4,
      5,
      6
    ];
    String monthName(int value) {
      if (!context.l10n.isEnglish) {
        return getHebrewMonthName(value, jd.isJewishLeapYear());
      }
      final date = JewishDate.initDate(
          jewishYear: year, jewishMonth: value, jewishDayOfMonth: 1);
      return (HebrewDateFormatter()..hebrewFormat = false)
          .format(date, pattern: 'MM');
    }

    return [
      DropdownButtonFormField<int>(
        key: ValueKey('exception-year-$year'),
        initialValue: year,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: context.l10n.pick(he: 'שנה', en: 'Year')),
        items: [
          for (var value = firstYear; value <= lastYear; value++)
            DropdownMenuItem(
                value: value,
                child: Text(context.l10n.isEnglish
                    ? '$value'
                    : formatHebrewYear(value)))
        ],
        onChanged: (value) {
          if (value != null) _setHebrew(value, month, day);
        },
      ),
      DropdownButtonFormField<int>(
        key: ValueKey('exception-month-$year-$month'),
        initialValue: month,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: context.l10n.pick(he: 'חודש', en: 'Month')),
        items: [
          for (final value in months)
            DropdownMenuItem(value: value, child: Text(monthName(value)))
        ],
        onChanged: (value) {
          if (value != null) _setHebrew(year, value, day);
        },
      ),
      DropdownButtonFormField<int>(
        key: ValueKey('exception-day-$year-$month-$day'),
        initialValue: day,
        isExpanded: true,
        decoration:
            InputDecoration(labelText: context.l10n.pick(he: 'יום', en: 'Day')),
        items: [
          for (var value = 1; value <= jd.getDaysInJewishMonth(); value++)
            DropdownMenuItem(
                value: value,
                child: Text(context.l10n.isEnglish
                    ? '$value'
                    : formatHebrewNumber(value)))
        ],
        onChanged: (value) {
          if (value != null) _setHebrew(year, month, value);
        },
      ),
    ];
  }

  Future<void> _pickGregorian() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year < 1900 ? _date.year : 1900),
      lastDate: DateTime(_date.year > 2200 ? _date.year : 2200, 12, 31),
    );
    if (selected != null && mounted) {
      setState(() {
        _date = selected;
        _error = null;
      });
    }
  }

  void _save() {
    final key = WorkCalendarRules.dateKey(_date);
    final originalKey =
        widget.existing == null ? null : WorkCalendarRules.dateKey(widget.date);
    if (key != originalKey && widget.takenDates.contains(key)) {
      setState(() => _error = context.l10n.pick(
            he: 'התאריך כבר מופיע ברשימה. יש לערוך את החריגה הקיימת.',
            en: 'This date is already listed. Edit the existing exception.',
          ));
      return;
    }
    Navigator.pop<WorkDayExceptionChoice>(context, (
      date: DateTime(_date.year, _date.month, _date.day),
      exception: WorkDayException(weight: _weight, note: _note.text.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(context.l10n.pick(
          he: widget.existing == null
              ? 'הוספת חריגה אישית'
              : 'עריכת חריגה אישית',
          en: widget.existing == null
              ? 'Add personal exception'
              : 'Edit personal exception',
        )),
        content: SizedBox(
            width: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.l10n.pick(
                  he: 'החריגה חלה על התאריך והשנה שנבחרו, בכל הפרויקטים.',
                  en: 'Applies to the selected date and year, across all projects.',
                )),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final gregorian in [false, true])
                    ChoiceChip(
                      label: Text(gregorian
                          ? context.l10n.pick(he: 'לועזי', en: 'Gregorian')
                          : context.l10n.pick(he: 'עברי', en: 'Hebrew')),
                      selected: _gregorian == gregorian,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _gregorian = gregorian),
                    ),
                ]),
                if (_gregorian)
                  OutlinedButton.icon(
                      onPressed: _pickGregorian,
                      icon: const Icon(Icons.calendar_today),
                      label: Text(formatDisplayDate(_date, true,
                          english: context.l10n.isEnglish)))
                else
                  ..._hebrewFields(),
                const SizedBox(height: 8),
                Text(
                    '${formatDisplayDate(_date, false, english: context.l10n.isEnglish)} · ${formatDisplayDate(_date, true, english: context.l10n.isEnglish)}'),
                const SizedBox(height: 12),
                DropdownButtonFormField<DayWeight>(
                  initialValue: _weight,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: context.l10n.pick(
                          he: 'זמינות לכתיבה', en: 'Writing availability')),
                  items: [
                    DropdownMenuItem(
                        value: DayWeight.none,
                        child: Text(
                            context.l10n.pick(he: 'יום חופש', en: 'Day off'))),
                    DropdownMenuItem(
                        value: DayWeight.half,
                        child: Text(
                            context.l10n.pick(he: 'חצי יום', en: 'Half day'))),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _weight = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: _note,
                    maxLines: 2,
                    decoration: InputDecoration(
                        labelText: context.l10n
                            .pick(he: 'הערה (רשות)', en: 'Note (optional)'),
                        hintText: context.l10n.pick(
                            he: 'חתונה, שבע ברכות…',
                            en: 'Wedding, Sheva Berachot…'))),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ],
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel)),
          FilledButton(
              onPressed: _save,
              child: Text(context.l10n.pick(he: 'שמור', en: 'Save'))),
        ],
      );
}
