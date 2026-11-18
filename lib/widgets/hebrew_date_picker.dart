import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';

import '../hebrew_utils.dart';
import '../l10n/app_localizations.dart';

Future<DateTime?> showHebrewDatePicker(BuildContext context,
    {required DateTime initialDate, bool monthOnly = false}) {
  final selected = JewishDate.fromDateTime(initialDate);

  return showDialog<DateTime>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      final l10n = context.l10n;
      final year = selected.getJewishYear();
      final firstYear = year - 10;
      final month = selected.getJewishMonth();
      final day = selected.getJewishDayOfMonth();
      final leap = selected.isJewishLeapYear();
      final months = [7, 8, 9, 10, 11, 12, if (leap) 13, 1, 2, 3, 4, 5, 6];

      void changeMonth(int newYear, int newMonth) {
        selected.setJewishDate(newYear, newMonth, 1);
        selected.setJewishDayOfMonth(
            math.min(day, selected.getDaysInJewishMonth()));
      }

      return AlertDialog(
        scrollable: true,
        title: Text(monthOnly
            ? l10n.pick(
                he: 'בחר חודש עברי',
                en: 'Choose a Hebrew month',
                yi: 'קלײַבט אַ ייִדישן חודש')
            : l10n.pick(
                he: 'בחר תאריך עברי',
                en: 'Choose a Hebrew date',
                yi: 'קלײַבט אַ ייִדישן דאַטע')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButton<int>(
            value: year,
            items: [
              for (var y = firstYear; y <= firstYear + 20; y++)
                DropdownMenuItem(
                    value: y,
                    child: Text(l10n.isEnglish ? '$y' : formatHebrewYear(y)))
            ],
            onChanged: (value) {
              if (value == null) return;
              final probe = JewishDate()..setJewishDate(value, 1, 1);
              setState(() => changeMonth(value,
                  !probe.isJewishLeapYear() && month == 13 ? 12 : month));
            },
          ),
          DropdownButton<int>(
            value: month,
            items: [
              for (final m in months)
                DropdownMenuItem(
                    value: m,
                    child: Text(l10n.isEnglish
                        ? (HebrewDateFormatter()..hebrewFormat = false).format(
                            JewishDate.initDate(
                                jewishYear: year,
                                jewishMonth: m,
                                jewishDayOfMonth: 1),
                            pattern: 'MM')
                        : getHebrewMonthName(m, leap)))
            ],
            onChanged: (value) {
              if (value != null) setState(() => changeMonth(year, value));
            },
          ),
          if (!monthOnly)
            DropdownButton<int>(
              value: day,
              items: [
                for (var d = 1; d <= selected.getDaysInJewishMonth(); d++)
                  DropdownMenuItem(
                      value: d,
                      child:
                          Text(l10n.isEnglish ? '$d' : formatHebrewNumber(d)))
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => selected.setJewishDayOfMonth(value));
                }
              },
            ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () {
                if (monthOnly) {
                  selected.setJewishDayOfMonth(selected.getDaysInJewishMonth());
                }
                Navigator.pop(context,
                    DateUtils.dateOnly(selected.getGregorianCalendar()));
              },
              child:
                  Text(l10n.pick(he: 'בחר', en: 'Select', yi: 'אויסקלײַבן'))),
        ],
      );
    }),
  );
}
