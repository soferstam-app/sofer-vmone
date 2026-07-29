// Unit tests for the pure logic of the app.
//
// The previous file here was the default Flutter counter smoke test, which did
// not compile and tested nothing relevant to this project.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/hebrew_utils.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/profit_calculator.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatHebrewNumber', () {
    test('single letters get a geresh', () {
      expect(formatHebrewNumber(1), "א'");
      expect(formatHebrewNumber(10), "י'");
      expect(formatHebrewNumber(100), "ק'");
    });

    test('15 and 16 avoid spelling divine names', () {
      expect(formatHebrewNumber(15), 'טו');
      expect(formatHebrewNumber(16), 'טז');
    });

    test('composite numbers', () {
      expect(formatHebrewNumber(11), 'יא');
      expect(formatHebrewNumber(245), 'רמה');
    });

    test('non-positive values render empty', () {
      expect(formatHebrewNumber(0), '');
      expect(formatHebrewNumber(-5), '');
    });
  });

  group('parseHebrewPageToNumber', () {
    test('accepts plain digits', () {
      expect(parseHebrewPageToNumber('15'), 15);
      expect(parseHebrewPageToNumber('245'), 245);
    });

    test('accepts Hebrew letters, with or without geresh', () {
      expect(parseHebrewPageToNumber('יא'), 11);
      expect(parseHebrewPageToNumber("א'"), 1);
      expect(parseHebrewPageToNumber('טו'), 15);
      expect(parseHebrewPageToNumber('טז'), 16);
    });

    test('accepts final letter forms', () {
      expect(parseHebrewPageToNumber('ך'), 20);
      expect(parseHebrewPageToNumber('ם'), 40);
    });

    test('empty input is zero', () {
      expect(parseHebrewPageToNumber(''), 0);
    });

    test('round-trips against formatHebrewNumber', () {
      for (var n = 1; n <= 250; n++) {
        expect(parseHebrewPageToNumber(formatHebrewNumber(n)), n,
            reason: 'failed round-trip for $n');
      }
    });
  });

  group('Expense serialization', () {
    test('round-trips lastUpdated and isDeleted', () {
      final original = Expense(
        id: 'e1',
        product: 'קלף מזוזות',
        date: DateTime(2026, 3, 1),
        amount: 120.5,
        lastUpdated: DateTime(2026, 3, 2, 10, 30),
        isDeleted: true,
      );

      final restored = Expense.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.product, original.product);
      expect(restored.amount, original.amount);
      expect(restored.date, original.date);
      expect(restored.lastUpdated, original.lastUpdated);
      expect(restored.isDeleted, isTrue);
    });

    test('older backups without the new fields still load', () {
      final restored = Expense.fromJson({
        'id': 'legacy',
        'product': 'דיו',
        'date': DateTime(2025, 12, 25).toIso8601String(),
        'amount': 40,
      });

      expect(restored.isDeleted, isFalse);
      // Falls back to the expense date so merging stays deterministic.
      expect(restored.lastUpdated, DateTime(2025, 12, 25));
    });

    test('copyWith marks a deletion and refreshes lastUpdated', () {
      final original = Expense(
        id: 'e2',
        product: 'הגהות',
        date: DateTime(2026, 1, 1),
        amount: 10,
        lastUpdated: DateTime(2026, 1, 1),
      );

      final deleted = original.copyWith(isDeleted: true);

      expect(deleted.id, original.id);
      expect(deleted.isDeleted, isTrue);
      expect(deleted.lastUpdated.isAfter(original.lastUpdated), isTrue);
    });
  });

  group('ProductionCalculator – mezuza', () {
    WorkSession session({required int amount, required int endLine}) =>
        WorkSession(
          id: 'x',
          projectId: 'p',
          startTime: DateTime(2026, 1, 1, 9),
          endTime: DateTime(2026, 1, 1, 10),
          amount: amount,
          startLine: 0,
          endLine: endLine,
          description: '',
          isManual: false,
        );

    test('whole mezuzot when no partial line is recorded', () {
      expect(
          ProductionCalculator.mezuzaLinesInSession(
              session(amount: 3, endLine: 0)),
          66);
      expect(
          ProductionCalculator.mezuzaLinesInSession(
              session(amount: 1, endLine: 0)),
          22);
    });

    test('partial last mezuza counts completed ones plus the lines', () {
      // 2 complete (44) + 10 lines into the third
      expect(
          ProductionCalculator.mezuzaLinesInSession(
              session(amount: 3, endLine: 10)),
          54);
      // First mezuza, 10 lines in
      expect(
          ProductionCalculator.mezuzaLinesInSession(
              session(amount: 1, endLine: 10)),
          10);
    });

    test('edge cases behave exactly as the original inline formula', () {
      // amount 0 with a line recorded: the guard keeps this from going negative
      expect(
          ProductionCalculator.mezuzaLinesInSession(
              session(amount: 0, endLine: 5)),
          5);
      expect(
          ProductionCalculator.mezuzaLinesInSession(
              session(amount: 0, endLine: 0)),
          0);
      // A full last mezuza expressed as a partial
      expect(
          ProductionCalculator.mezuzaLinesInSession(
              session(amount: 2, endLine: 22)),
          44);
    });

    test('totals sum across sessions', () {
      final sessions = [
        session(amount: 3, endLine: 0), // 66
        session(amount: 1, endLine: 11), // 11
      ];
      expect(ProductionCalculator.mezuzaLinesTotal(sessions), 77);
      expect(ProductionCalculator.mezuzotTotal(sessions), 3.5);
    });

    test('empty input is zero, not an error', () {
      expect(ProductionCalculator.mezuzaLinesTotal(const []), 0);
      expect(ProductionCalculator.mezuzotTotal(const []), 0.0);
    });
  });

  group('ProductionCalculator – sefer', () {
    WorkSession session({required int startLine, required int endLine}) =>
        WorkSession(
          id: 'x',
          projectId: 'p',
          startTime: DateTime(2026, 1, 1, 9),
          endTime: DateTime(2026, 1, 1, 10),
          amount: 1,
          startLine: startLine,
          endLine: endLine,
          description: '',
          isManual: false,
        );

    Project project({int? linesPerPage}) => Project(
          id: 'p',
          name: 'ספר',
          type: ProjectType.sefer,
          price: 100,
          expenses: 0,
          targetDaily: 1,
          targetMonthly: 20,
          linesPerPage: linesPerPage,
        );

    test('line range is inclusive on both ends', () {
      expect(
          ProductionCalculator.seferLinesInSession(
              session(startLine: 1, endLine: 42)),
          42);
      // A single line written
      expect(
          ProductionCalculator.seferLinesInSession(
              session(startLine: 5, endLine: 5)),
          1);
    });

    test('totals sum across sessions', () {
      expect(
          ProductionCalculator.seferLinesTotal([
            session(startLine: 1, endLine: 10), // 10
            session(startLine: 11, endLine: 42), // 32
          ]),
          42);
    });

    test('linesPerPage falls back when unset', () {
      expect(ProductionCalculator.linesPerPageOf(project()), 42);
      expect(
          ProductionCalculator.linesPerPageOf(project(linesPerPage: 30)), 30);
    });

    test('a stored zero does not cause a division by zero', () {
      expect(ProductionCalculator.linesPerPageOf(project(linesPerPage: 0)), 42);
      expect(
          ProductionCalculator.seferPages(
              [session(startLine: 1, endLine: 42)], project(linesPerPage: 0)),
          1.0);
    });

    test('pages can be fractional', () {
      expect(
          ProductionCalculator.seferPages(
              [session(startLine: 1, endLine: 21)], project(linesPerPage: 42)),
          0.5);
    });
  });

  group('ProductionCalculator – tefillin', () {
    WorkSession session({
      required int amount,
      String? tefillinType,
      int? parshiya,
      int endLine = 0,
    }) =>
        WorkSession(
          id: 'x',
          projectId: 'p',
          startTime: DateTime(2026, 1, 1, 9),
          endTime: DateTime(2026, 1, 1, 10),
          amount: amount,
          startLine: 0,
          endLine: endLine,
          tefillinType: tefillinType,
          parshiya: parshiya,
          description: '',
          isManual: false,
        );

    test('a whole set is eight parshiyot', () {
      expect(ProductionCalculator.parshiyotInSession(session(amount: 2)), 16);
    });

    test('head or hand alone is four parshiyot', () {
      expect(
          ProductionCalculator.parshiyotInSession(
              session(amount: 3, tefillinType: 'head')),
          12);
      expect(
          ProductionCalculator.parshiyotInSession(
              session(amount: 1, tefillinType: 'hand')),
          4);
    });

    test('an individual parshiya counts as itself', () {
      expect(
          ProductionCalculator.parshiyotInSession(
              session(amount: 1, tefillinType: 'head', parshiya: 2)),
          1);
    });

    test('completed-only variant excludes a partial parshiya', () {
      // Head parshiya has 4 lines; stopping at line 2 is unfinished.
      expect(
          ProductionCalculator.completedParshiyotInSession(
              session(amount: 1, tefillinType: 'head', parshiya: 1, endLine: 2)),
          isNull);
      // Reaching the last line counts.
      expect(
          ProductionCalculator.completedParshiyotInSession(
              session(amount: 1, tefillinType: 'head', parshiya: 1, endLine: 4)),
          1);
      // Hand parshiya has 7 lines, so line 4 is still partial there.
      expect(
          ProductionCalculator.completedParshiyotInSession(
              session(amount: 1, tefillinType: 'hand', parshiya: 1, endLine: 4)),
          isNull);
      // No partial line recorded at all means finished.
      expect(
          ProductionCalculator.completedParshiyotInSession(
              session(amount: 1, tefillinType: 'hand', parshiya: 1)),
          1);
    });

    test('whole sets and units are always complete', () {
      expect(
          ProductionCalculator.completedParshiyotInSession(session(amount: 2)),
          16);
      expect(
          ProductionCalculator.completedParshiyotInSession(
              session(amount: 1, tefillinType: 'head')),
          4);
    });

    test('totals sum across sessions', () {
      expect(
          ProductionCalculator.parshiyotTotal([
            session(amount: 1), // 8
            session(amount: 1, tefillinType: 'hand'), // 4
            session(amount: 1, tefillinType: 'head', parshiya: 3), // 1
          ]),
          13);
    });
  });

  group('ProfitCalculator', () {
    Project project(ProjectType type, {double price = 100, double exp = 20}) =>
        Project(
          id: 'p',
          name: 'x',
          type: type,
          price: price,
          expenses: exp,
          targetDaily: 1,
          targetMonthly: 20,
          linesPerPage: type == ProjectType.sefer ? 42 : null,
        );

    WorkSession s({
      int amount = 1,
      int startLine = 0,
      int endLine = 0,
      String? tefillinType,
      int? parshiya,
    }) =>
        WorkSession(
          id: 'x',
          projectId: 'p',
          startTime: DateTime(2026, 1, 1, 9),
          endTime: DateTime(2026, 1, 1, 11),
          amount: amount,
          startLine: startLine,
          endLine: endLine,
          tefillinType: tefillinType,
          parshiya: parshiya,
          description: '',
          isManual: false,
        );

    test('sefer is priced per page', () {
      // One full page of 42 lines, net 80 per page
      expect(
          ProfitCalculator.profit(
              project(ProjectType.sefer), [s(startLine: 1, endLine: 42)]),
          80);
      // Half a page
      expect(
          ProfitCalculator.profit(
              project(ProjectType.sefer), [s(startLine: 1, endLine: 21)]),
          40);
    });

    test('mezuza is priced per mezuza', () {
      expect(
          ProfitCalculator.profit(project(ProjectType.mezuza), [s(amount: 3)]),
          240);
    });

    test('tefillin is priced per full set, not per session amount', () {
      // A whole set
      expect(
          ProfitCalculator.profit(project(ProjectType.tefillin), [s(amount: 1)]),
          80);
      // Head only is 4 of 8 parshiyot — half a set, not a whole one.
      // The summary screen used to bill this as a full unit.
      expect(
          ProfitCalculator.profit(project(ProjectType.tefillin),
              [s(amount: 1, tefillinType: 'head')]),
          40);
      // A single parshiya is an eighth of a set
      expect(
          ProfitCalculator.profit(project(ProjectType.tefillin),
              [s(amount: 1, tefillinType: 'head', parshiya: 1)]),
          10);
    });

    test('expenses are deducted per unit', () {
      expect(
          ProfitCalculator.profit(
              project(ProjectType.mezuza, price: 50, exp: 50), [s(amount: 4)]),
          0);
    });

    test('hourly rate divides profit by time worked', () {
      // 3 mezuzot at net 80 = 240, over 2 hours
      expect(
          ProfitCalculator.profitPerHour(project(ProjectType.mezuza),
              [s(amount: 3)], const Duration(hours: 2)),
          120);
    });

    test('hourly rate is null rather than infinite when no time is recorded', () {
      expect(
          ProfitCalculator.profitPerHour(
              project(ProjectType.mezuza), [s(amount: 3)], Duration.zero),
          isNull);
    });
  });

  group('BackupService', () {
    test('backup file carries every data list and the settings', () async {
      SharedPreferences.setMockInitialValues({
        'projects': jsonEncode([
          Project(
            id: 'p1',
            name: 'ספר תורה',
            type: ProjectType.sefer,
            price: 100,
            expenses: 10,
            targetDaily: 2,
            targetMonthly: 40,
            totalPages: 245,
            linesPerPage: 42,
          ).toJson()
        ]),
        'history': jsonEncode([]),
        'expenses': jsonEncode([
          Expense(
            id: 'e1',
            product: 'קלף',
            date: DateTime(2026, 5, 1),
            amount: 300,
          ).toJson()
        ]),
        'day_rollover_hour': 2,
        'use_gregorian_dates': true,
      });

      final json = await BackupService.instance.buildBackupJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['app'], 'sofer_vmone');
      expect(decoded['formatVersion'], BackupService.formatVersion);
      expect(decoded['exportedAt'], isNotNull);

      // All three data lists travel in one document.
      expect((decoded['projects'] as List), hasLength(1));
      expect((decoded['history'] as List), isEmpty);
      expect((decoded['expenses'] as List), hasLength(1));

      // Settings ride along so a restore rebuilds the user's setup.
      final settings = decoded['settings'] as Map<String, dynamic>;
      expect(settings['day_rollover_hour'], 2);
      expect(settings['use_gregorian_dates'], isTrue);

      expect((decoded['counts'] as Map)['projects'], 1);
    });

    test('suggested file name is timestamped and json', () {
      final name = BackupService.instance.suggestedFileName();
      expect(name, startsWith('sofer-vmone-backup-'));
      expect(name, endsWith('.json'));
    });

    test('survives corrupt stored data instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        'projects': 'not-json-at-all',
        'expenses': '{"unexpected":"shape"}',
      });

      final json = await BackupService.instance.buildBackupJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect((decoded['projects'] as List), isEmpty);
      expect((decoded['expenses'] as List), isEmpty);
    });
  });
}
