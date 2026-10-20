import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/logic/client_update.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/reminder_plan.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const english = AppLocalizations(Locale('en', 'US'));
  const hebrew = AppLocalizations(Locale('he', 'IL'));

  test('the product name follows the selected interface language', () {
    expect(hebrew.appName, 'סופר ומונה');
    expect(english.appName, 'Sofer v’Mone');
  });

  group('stored Hebrew identifiers have a localized presentation', () {
    test('approved professional expense terms are translated for display', () {
      expect(english.expenseCategory('תיקון סופרים'), 'Tikkun Sofrim');
      expect(english.expenseCategory('דיו, מי קלף, ציוד'),
          'Ink, Mei Klaf, and Equipment');
      expect(english.expenseCategory('חדר סופרים'), 'Sofrim Workspace');
    });

    test('Hebrew and unknown user data are never rewritten', () {
      expect(hebrew.expenseCategory('תיקון סופרים'), 'תיקון סופרים');
      expect(english.expenseCategory('קטגוריה פרטית'), 'קטגוריה פרטית');
    });

    test('proofreading stages retain their identifiers', () {
      expect(english.proofreadingStage('אצל המגיה'), 'With the Proofreader');
      expect(english.proofreadingStage('חזר לתיקון'), 'Awaiting Correction');
      expect(hebrew.proofreadingStage('אצל המגיה'), 'אצל המגיה');
    });
  });

  group('legacy validation is translated only at presentation time', () {
    test('fixed and parameterized messages are covered', () {
      expect(english.businessMessage('יש להזין כמות'), 'Enter a quantity');
      expect(
        english.businessMessage('במזוזה יש רק 22 שורות'),
        'A Mezuzah has only 22 lines',
      );
      expect(
        english.businessMessage('פרשיית שמע בזוג 3 כבר התחילה'),
        'Parashah שמע in set 3 has already started',
      );
    });

    test('Hebrew behavior and an unknown message pass through unchanged', () {
      expect(hebrew.businessMessage('יש להזין כמות'), 'יש להזין כמות');
      expect(english.businessMessage('טקסט חדש'), 'טקסט חדש');
    });
  });

  test('English reminders never leak Hebrew business text', () {
    final project = Project(
      id: 'p',
      name: 'Commission',
      type: ProjectType.sefer,
      price: 0,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 0,
      linesPerPage: 10,
    );
    expect(
      ReminderPlan.todaysMessage(
        project: project,
        history: const [],
        day: DateTime(2026, 8, 23),
        dayStart: DayStart.midnight,
        english: true,
      ),
      'No writing has been recorded today. Ready to start?',
    );
    expect(ReminderPlan.generalMessageFor(english: true),
        isNot(contains(RegExp('[א-ת]'))));
  });

  test('an English client update uses English framing', () {
    final project = Project(
      id: 'p',
      name: 'Sefer Cohen',
      type: ProjectType.sefer,
      price: 0,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0,
      totalPages: 100,
      linesPerPage: 10,
    );
    final body = ClientUpdate.compose(
      project: project,
      totalWritten: '30 pages',
      estimatedEnd: '23 Av 5786',
      linesWritten: 300,
      soferName: 'Shaul',
      today: DateTime(2026, 8, 23),
      formatDate: (date) => '${date.month}/${date.day}/${date.year}',
      english: true,
    );

    expect(body, startsWith('Hello,'));
    expect(body, contains('• Progress: 30%'));
    expect(body, isNot(contains('בס״ד')));
  });
}
