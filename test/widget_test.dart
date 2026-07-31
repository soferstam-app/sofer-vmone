// Unit tests for the pure logic of the app.
//
// The previous file here was the default Flutter counter smoke test, which did
// not compile and tested nothing relevant to this project.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/expenses/expense_editor.dart';
import 'package:sofer_vmone/hebrew_utils.dart';
import 'package:sofer_vmone/logic/date_logic.dart';
import 'package:sofer_vmone/logic/completion_estimator.dart';
import 'package:sofer_vmone/logic/expense_logic.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/logic/id_generator.dart';
import 'package:sofer_vmone/logic/merge_service.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/profit_calculator.dart';
import 'package:sofer_vmone/logic/project_analytics.dart';
import 'package:sofer_vmone/logic/quote_calculator.dart';
import 'package:sofer_vmone/logic/session_logic.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/project/scroll_map.dart';
import 'package:sofer_vmone/storage_service.dart';

/// Every configurable category set to a full working day, so arithmetic tests
/// depend only on the fixed days — Shabbat, Yom Tov and the rest — and not on
/// wherever in the year the sample dates happen to fall.
const shabbatOnly = WorkCalendarRules(
  friday: DayWeight.half,
  motzeiShabbat: DayWeight.none,
  chanukah: DayWeight.full,
  fastSeventeenTammuz: DayWeight.full,
  fastGedalya: DayWeight.full,
  fastTenthTevet: DayWeight.full,
  fastEsther: DayWeight.full,
  lagBaomer: DayWeight.full,
  isruChag: DayWeight.full,
  daysBeforePesach: 0,
  beforePesach: DayWeight.full,
  betweenYomKippurAndSukkot: DayWeight.full,
);

/// The same, but with Friday off as well — the shape most of the app runs with.
const shabbatAndFriday = WorkCalendarRules(
  friday: DayWeight.none,
  chanukah: DayWeight.full,
  fastSeventeenTammuz: DayWeight.full,
  fastGedalya: DayWeight.full,
  fastTenthTevet: DayWeight.full,
  fastEsther: DayWeight.full,
  lagBaomer: DayWeight.full,
  isruChag: DayWeight.full,
  daysBeforePesach: 0,
  beforePesach: DayWeight.full,
  betweenYomKippurAndSukkot: DayWeight.full,
);

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

    test('a session uses the page size snapshotted when it was recorded', () {
      final oldSession = WorkSession(
        id: 'old',
        projectId: 'p',
        startTime: DateTime(2026, 1, 1),
        endTime: DateTime(2026, 1, 1),
        amount: 1,
        startLine: 1,
        endLine: 30,
        description: '',
        isManual: false,
        linesPerPageAtEntry: 30, // written when pages held 30 lines
      );
      // Project has since been changed to 42 lines per page.
      final p = project(linesPerPage: 42);

      expect(ProductionCalculator.linesPerPageForSession(p, oldSession), 30);
      // A full page then, and still a full page now — not 30/42 of one.
      expect(ProductionCalculator.seferPages([oldSession], p), 1.0);
    });

    test('sessions without a snapshot fall back to the project setting', () {
      final legacy = session(startLine: 1, endLine: 42);
      expect(legacy.linesPerPageAtEntry, isNull);
      expect(
          ProductionCalculator.linesPerPageForSession(
              project(linesPerPage: 30), legacy),
          30);
      // Which is the behaviour that existed before the snapshot field.
      expect(
          ProductionCalculator.linesPerPageForSession(project(), legacy), 42);
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

  group('IdGenerator', () {
    test('ids created in the same millisecond are still distinct', () {
      // The old scheme was a bare millisecond timestamp, so a tight loop
      // produced duplicates — and so did two devices writing at once.
      final ids = <String>{};
      for (var i = 0; i < 10000; i++) {
        ids.add(IdGenerator.generate());
      }
      expect(ids.length, 10000);
    });

    test('a suffix distinguishes records from one operation', () {
      final a = IdGenerator.generate(suffix: '5');
      final b = IdGenerator.generate(suffix: '6');
      expect(a, endsWith('-5'));
      expect(b, endsWith('-6'));
      expect(a, isNot(b));
    });

    test('ids stay roughly sortable by creation time', () {
      final first = IdGenerator.generate();
      final firstMillis = int.parse(first.split('-').first);
      expect(firstMillis,
          closeTo(DateTime.now().millisecondsSinceEpoch, 5000));
    });
  });

  group('SessionLogic – time range', () {
    test('a normal session keeps both times on the same day', () {
      final r = SessionLogic.buildTimeRange(
        date: DateTime(2026, 5, 10),
        startHour: 9,
        startMinute: 0,
        endHour: 12,
        endMinute: 30,
      );
      expect(r.start, DateTime(2026, 5, 10, 9, 0));
      expect(r.end, DateTime(2026, 5, 10, 12, 30));
      expect(r.end.difference(r.start), const Duration(hours: 3, minutes: 30));
    });

    test('a session past midnight ends on the next day, never negative', () {
      final r = SessionLogic.buildTimeRange(
        date: DateTime(2026, 5, 10),
        startHour: 23,
        startMinute: 0,
        endHour: 1,
        endMinute: 0,
      );
      expect(r.end, DateTime(2026, 5, 11, 1, 0));
      expect(r.end.difference(r.start), const Duration(hours: 2));
      expect(r.end.isAfter(r.start), isTrue);
    });

    test('parses HH:MM and rejects nonsense', () {
      expect(SessionLogic.parseTimeString('09:30'), (hour: 9, minute: 30));
      expect(SessionLogic.parseTimeString(' 9 : 5 '), (hour: 9, minute: 5));
      expect(SessionLogic.parseTimeString('nope'), isNull);
      expect(SessionLogic.parseTimeString('12'), isNull);
      expect(SessionLogic.parseTimeString('25:00'), isNull);
      expect(SessionLogic.parseTimeString('10:99'), isNull);
    });
  });

  group('SessionLogic – validation', () {
    test('accepts a valid sefer range', () {
      expect(
          SessionLogic.validateSeferLines(
              startLine: 1, endLine: 42, linesPerPage: 42),
          isNull);
    });

    test('rejects zero, out-of-page and reversed ranges', () {
      expect(
          SessionLogic.validateSeferLines(
              startLine: 0, endLine: 10, linesPerPage: 42),
          isNotNull);
      expect(
          SessionLogic.validateSeferLines(
              startLine: 1, endLine: 100, linesPerPage: 42),
          isNotNull);
      expect(
          SessionLogic.validateSeferLines(
              startLine: 30, endLine: 10, linesPerPage: 42),
          isNotNull);
    });

    test('mezuza and tefillin line limits', () {
      expect(SessionLogic.validateMezuzaLine(22), isNull);
      expect(SessionLogic.validateMezuzaLine(23), isNotNull);
      expect(
          SessionLogic.validateTefillinLine(tefillinType: 'head', line: 4),
          isNull);
      expect(
          SessionLogic.validateTefillinLine(tefillinType: 'head', line: 5),
          isNotNull);
      // Hand parshiyot allow more lines than head
      expect(
          SessionLogic.validateTefillinLine(tefillinType: 'hand', line: 7),
          isNull);
    });
  });

  group('SessionLogic – overlap', () {
    WorkSession s(String id, int page, int from, int to,
            {bool deleted = false}) =>
        WorkSession(
          id: id,
          projectId: 'p1',
          startTime: DateTime(2026, 1, 1),
          endTime: DateTime(2026, 1, 1),
          amount: page,
          startLine: from,
          endLine: to,
          description: '',
          isManual: false,
          isDeleted: deleted,
        );

    final history = [s('a', 5, 1, 20), s('b', 6, 1, 42)];

    test('detects an overlapping range on the same page', () {
      expect(
          SessionLogic.hasSeferOverlap(
              history: history,
              projectId: 'p1',
              page: 5,
              startLine: 15,
              endLine: 30),
          isTrue);
    });

    test('a range after existing work on the same page is free', () {
      expect(
          SessionLogic.hasSeferOverlap(
              history: history,
              projectId: 'p1',
              page: 5,
              startLine: 21,
              endLine: 42),
          isFalse);
    });

    test('another page and another project do not collide', () {
      expect(
          SessionLogic.hasSeferOverlap(
              history: history,
              projectId: 'p1',
              page: 7,
              startLine: 1,
              endLine: 42),
          isFalse);
      expect(
          SessionLogic.hasSeferOverlap(
              history: history,
              projectId: 'other',
              page: 5,
              startLine: 1,
              endLine: 20),
          isFalse);
    });

    test('a session does not overlap itself when being edited', () {
      // Without the exclusion, editing session "a" would always report a clash
      expect(
          SessionLogic.hasSeferOverlap(
              history: history,
              projectId: 'p1',
              page: 5,
              startLine: 1,
              endLine: 20,
              excludeSessionId: 'a'),
          isFalse);
    });

    test('deleted sessions are ignored', () {
      expect(
          SessionLogic.hasSeferOverlap(
              history: [s('x', 5, 1, 42, deleted: true)],
              projectId: 'p1',
              page: 5,
              startLine: 1,
              endLine: 42),
          isFalse);
    });
  });

  group('DateLogic', () {
    DayStart at(int hour) =>
        DayStart(boundary: DayBoundary.fixedHour, hour: hour);

    test('rollover 0 behaves as the plain calendar date', () {
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 10, 1, 30), DayStart.midnight),
          DateTime(2026, 5, 10));
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 10, 23, 0), DayStart.midnight),
          DateTime(2026, 5, 10));
    });

    test('before the rollover hour belongs to the previous day', () {
      // 01:00 with rollover at 02:00 is still "yesterday"
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 10, 1, 0), at(2)),
          DateTime(2026, 5, 9));
      // 02:00 exactly starts the new day
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 10, 2, 0), at(2)),
          DateTime(2026, 5, 10));
    });

    test('crosses a month boundary correctly', () {
      // 01:00 on the 1st, rollover 3 → belongs to the last day of April
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 1, 1, 0), at(3)),
          DateTime(2026, 4, 30));
    });

    test('crosses a year boundary correctly', () {
      expect(DateLogic.effectiveDate(DateTime(2026, 1, 1, 0, 30), at(2)),
          DateTime(2025, 12, 31));
    });

    test('a late-night session and the day it belongs to agree', () {
      final lateNight = DateTime(2026, 5, 10, 1, 15);
      final theWorkingDay = DateTime(2026, 5, 9, 20, 0);
      expect(DateLogic.isSameWorkingDay(lateNight, theWorkingDay, at(2)), isTrue);
      // Without the rollover they would be different days
      expect(DateLogic.isSameWorkingDay(lateNight, theWorkingDay, DayStart.midnight), isFalse);
    });

    test('month grouping honours the rollover at a boundary', () {
      final lateNight = DateTime(2026, 5, 1, 1, 0);
      expect(
          DateLogic.isSameWorkingMonth(lateNight, DateTime(2026, 4), at(3)), isTrue);
      expect(DateLogic.isSameWorkingMonth(lateNight, DateTime(2026, 5), at(3)),
          isFalse);
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

  group('ProjectAnalytics', () {
    Project proj(String id, ProjectType type,
            {double price = 100, double exp = 0}) =>
        Project(
          id: id,
          name: id,
          type: type,
          price: price,
          expenses: exp,
          targetDaily: 1,
          targetMonthly: 20,
          linesPerPage: type == ProjectType.sefer ? 42 : null,
        );

    WorkSession sess(String projectId,
            {required int hours,
            int startLine = 1,
            int endLine = 42,
            int amount = 1,
            bool backlog = false}) =>
        WorkSession(
          id: '$projectId-$startLine-$endLine-$amount-$hours',
          projectId: projectId,
          startTime: DateTime(2026, 5, 1, 8),
          endTime: DateTime(2026, 5, 1, 8 + hours),
          amount: amount,
          startLine: startLine,
          endLine: endLine,
          description: '',
          isManual: false,
          backlogOnly: backlog,
        );

    test('measures rate and pay for a project', () {
      // One full 42-line page in 2 hours, net 100 per page
      final perf = ProjectAnalytics.measure(
          proj('a', ProjectType.sefer), [sess('a', hours: 2)]);

      expect(perf.units, 1.0);
      expect(perf.profit, 100);
      expect(perf.profitPerHour, 50);
      expect(perf.timePerUnit, const Duration(hours: 2));
      expect(perf.hasEnoughData, isTrue);
    });

    test('backlog work is excluded from the rate', () {
      // The backlog session would otherwise add units with placeholder time
      final perf = ProjectAnalytics.measure(proj('a', ProjectType.sefer),
          [sess('a', hours: 2), sess('a', hours: 0, amount: 9, backlog: true)]);
      expect(perf.units, 1.0);
      expect(perf.profitPerHour, 50);
    });

    test('a project with no timed work is flagged, not ranked', () {
      final perf = ProjectAnalytics.measure(
          proj('a', ProjectType.mezuza), [sess('a', hours: 0, amount: 3)]);
      expect(perf.hasEnoughData, isFalse);
      expect(perf.profitPerHour, isNull);
    });

    test('ranking puts the best payer first and unmeasured projects last', () {
      final projects = [
        proj('slow', ProjectType.sefer, price: 100), // 100 over 4h = 25/h
        proj('fast', ProjectType.mezuza, price: 80), // 80 over 1h  = 80/h
        proj('untimed', ProjectType.mezuza),
      ];
      final history = [
        sess('slow', hours: 4),
        sess('fast', hours: 1, amount: 1, startLine: 0, endLine: 22),
        sess('untimed', hours: 0, amount: 5),
      ];

      final ranked = ProjectAnalytics.rankByHourlyRate(projects, history);
      expect(ranked.first.project.id, 'fast');
      expect(ranked.last.project.id, 'untimed');
      expect(ranked.last.hasEnoughData, isFalse);
    });

    test('typical pace averages across projects of the same type', () {
      final projects = [
        proj('a', ProjectType.sefer),
        proj('b', ProjectType.sefer),
      ];
      // One page in 2h and one page in 4h → 3h per page
      final history = [sess('a', hours: 2), sess('b', hours: 4)];
      expect(ProjectAnalytics.typicalTimePerUnit(
              ProjectType.sefer, projects, history),
          const Duration(hours: 3));
    });

    test('typical pace is null for a type never worked on', () {
      expect(
          ProjectAnalytics.typicalTimePerUnit(
              ProjectType.tefillin, [proj('a', ProjectType.sefer)], const []),
          isNull);
    });
  });

  group('QuoteCalculator', () {
    test('prices a job to reach the target hourly rate', () {
      final q = QuoteCalculator.estimate(
        units: 10,
        timePerUnit: const Duration(hours: 2), // 20 hours total
        targetHourlyRate: 50,
        hoursPerDay: 5, // 4 working days
        rules: shabbatOnly,
      )!;

      expect(q.totalTime, const Duration(hours: 20));
      expect(q.workDays, 4);
      expect(q.suggestedPrice, 1000); // 20h x 50
      expect(q.pricePerUnit, 100);
    });

    test('materials are added on top of the labour rate', () {
      final q = QuoteCalculator.estimate(
        units: 10,
        timePerUnit: const Duration(hours: 1),
        targetHourlyRate: 50,
        hoursPerDay: 5,
        expensesPerUnit: 30,
        rules: shabbatOnly,
      )!;
      // 10h x 50 = 500 labour, plus 10 x 30 = 300 materials
      expect(q.suggestedPrice, 800);
    });

    test('the completion date never lands on Shabbat', () {
      // Try every starting weekday: no amount of work should finish on a day
      // that is not a working day.
      for (var offset = 0; offset < 14; offset++) {
        final start = DateTime(2026, 5, 4).add(Duration(days: offset));
        final q = QuoteCalculator.estimate(
          units: 6,
          timePerUnit: const Duration(hours: 5),
          targetHourlyRate: 50,
          hoursPerDay: 5,
          rules: shabbatOnly,
          startingFrom: start,
        )!;
        expect(q.estimatedCompletion.weekday, isNot(DateTime.saturday),
            reason: 'finished on Shabbat starting from $start');
      }
    });

    test('non-working days push the completion date out', () {
      // Six working days cannot fit into six calendar days when a Shabbat
      // falls inside the span.
      final q = QuoteCalculator.estimate(
        units: 6,
        timePerUnit: const Duration(hours: 5),
        targetHourlyRate: 50,
        hoursPerDay: 5, // exactly 6 working days
        rules: shabbatOnly,
        startingFrom: DateTime(2026, 5, 4),
      )!;
      expect(q.workDays, 6);
      expect(
          q.estimatedCompletion
              .difference(DateTime(2026, 5, 4))
              .inDays,
          greaterThanOrEqualTo(6));
    });

    test('nonsense input yields no estimate rather than a wrong one', () {
      expect(
          QuoteCalculator.estimate(
              units: 0,
              timePerUnit: const Duration(hours: 1),
              targetHourlyRate: 50,
              hoursPerDay: 5,
              rules: shabbatOnly),
          isNull);
      expect(
          QuoteCalculator.estimate(
              units: 10,
              timePerUnit: Duration.zero,
              targetHourlyRate: 50,
              hoursPerDay: 5,
              rules: shabbatOnly),
          isNull);
      expect(
          QuoteCalculator.estimate(
              units: 10,
              timePerUnit: const Duration(hours: 1),
              targetHourlyRate: 50,
              hoursPerDay: 0,
              rules: shabbatOnly),
          isNull);
    });

    test('implied rate checks an offer a client already made', () {
      // 1000 for 20 hours of work
      expect(
          QuoteCalculator.impliedHourlyRate(
              totalPrice: 1000, units: 10, timePerUnit: const Duration(hours: 2)),
          50);
      // The same offer with 300 of materials pays less per hour
      expect(
          QuoteCalculator.impliedHourlyRate(
              totalPrice: 1000,
              units: 10,
              timePerUnit: const Duration(hours: 2),
              expensesPerUnit: 30),
          35);
    });
  });

  group('ExpenseLogic', () {
    Expense exp({
      required double amount,
      ExpenseAllocation allocation = ExpenseAllocation.month,
      List<String> projectIds = const [],
      DateTime? date,
      DateTime? start,
      DateTime? end,
    }) =>
        Expense(
          id: 'e${amount}_${allocation.index}',
          product: 'x',
          date: date ?? DateTime(2026, 5, 10),
          amount: amount,
          allocation: allocation,
          projectIds: projectIds,
          periodStart: start,
          periodEnd: end,
        );

    test('categories carry sensible default allocations', () {
      expect(ExpenseLogic.defaultAllocationFor('קלף מזוזות'),
          ExpenseAllocation.project);
      expect(ExpenseLogic.defaultAllocationFor('תיקון סופרים'),
          ExpenseAllocation.project);
      expect(ExpenseLogic.defaultAllocationFor('דיו, מי קלף, ציוד'),
          ExpenseAllocation.period);
      expect(ExpenseLogic.defaultAllocationFor('חדר סופרים'),
          ExpenseAllocation.month);
      expect(ExpenseLogic.defaultAllocationFor('שונות'),
          ExpenseAllocation.month);
      // Anything typed freehand falls back to monthly
      expect(ExpenseLogic.defaultAllocationFor('משהו אחר'),
          ExpenseAllocation.month);
    });

    test('a project expense is charged to that project', () {
      final expenses = [
        exp(amount: 300, allocation: ExpenseAllocation.project, projectIds: ['p1']),
        exp(amount: 500, allocation: ExpenseAllocation.project, projectIds: ['p2']),
      ];
      expect(ExpenseLogic.totalForProject('p1', expenses), 300);
      expect(ExpenseLogic.totalForProject('p2', expenses), 500);
      expect(ExpenseLogic.totalForProject('p3', expenses), 0);
    });

    test('an expense split across projects divides evenly', () {
      // One delivery serving three projects
      final expenses = [
        exp(
            amount: 300,
            allocation: ExpenseAllocation.project,
            projectIds: ['p1', 'p2', 'p3']),
      ];
      expect(ExpenseLogic.totalForProject('p1', expenses), 100);
      expect(ExpenseLogic.totalForProject('p2', expenses), 100);
    });

    test('project expenses do not also land in the monthly total', () {
      // Otherwise the same money would be counted twice.
      final expenses = [
        exp(amount: 300, allocation: ExpenseAllocation.project, projectIds: ['p1']),
      ];
      expect(ExpenseLogic.totalForMonth(DateTime(2026, 5), expenses), 0);
    });

    test('a monthly expense counts in its own month only', () {
      final expenses = [exp(amount: 800, date: DateTime(2026, 5, 3))];
      expect(ExpenseLogic.totalForMonth(DateTime(2026, 5), expenses), 800);
      expect(ExpenseLogic.totalForMonth(DateTime(2026, 6), expenses), 0);
    });

    test('a period expense is spread across the months it covers', () {
      // 1200 over roughly four months, bought on 1 May
      final expenses = [
        exp(
          amount: 1200,
          allocation: ExpenseAllocation.period,
          date: DateTime(2026, 5, 1),
          start: DateTime(2026, 5, 1),
          end: DateTime(2026, 8, 31),
        ),
      ];
      final may = ExpenseLogic.totalForMonth(DateTime(2026, 5), expenses);
      final june = ExpenseLogic.totalForMonth(DateTime(2026, 6), expenses);
      final october = ExpenseLogic.totalForMonth(DateTime(2026, 10), expenses);

      expect(may, greaterThan(0));
      expect(may, lessThan(1200)); // not charged entirely to the first month
      expect(june, greaterThan(0));
      expect(october, 0); // outside the range

      // The whole cost is accounted for across the range it covers
      final total = [5, 6, 7, 8]
          .map((m) => ExpenseLogic.totalForMonth(DateTime(2026, m), expenses))
          .reduce((a, b) => a + b);
      expect(total, closeTo(1200, 0.01));
    });

    test('deleted expenses are ignored everywhere', () {
      final deleted = Expense(
        id: 'd',
        product: 'x',
        date: DateTime(2026, 5, 1),
        amount: 999,
        allocation: ExpenseAllocation.project,
        projectIds: const ['p1'],
        isDeleted: true,
      );
      expect(ExpenseLogic.totalForProject('p1', [deleted]), 0);
      expect(ExpenseLogic.totalForMonth(DateTime(2026, 5), [deleted]), 0);
    });

    test('project expenses with no project chosen are flagged', () {
      final orphan =
          exp(amount: 100, allocation: ExpenseAllocation.project);
      expect(ExpenseLogic.unassigned([orphan]), hasLength(1));
      // One that is assigned is not flagged
      expect(
          ExpenseLogic.unassigned([
            exp(
                amount: 100,
                allocation: ExpenseAllocation.project,
                projectIds: ['p1'])
          ]),
          isEmpty);
    });

    test('older expenses load as monthly, preserving previous behaviour', () {
      final legacy = Expense.fromJson({
        'id': 'old',
        'product': 'דיו',
        'date': DateTime(2026, 5, 5).toIso8601String(),
        'amount': 200,
      });
      expect(legacy.allocation, ExpenseAllocation.month);
      expect(legacy.projectIds, isEmpty);
      expect(ExpenseLogic.totalForMonth(DateTime(2026, 5), [legacy]), 200);
    });
  });

  group('MergeService', () {
    Project project(String id, {DateTime? updated, bool deleted = false}) =>
        Project(
          id: id,
          name: 'p$id',
          type: ProjectType.sefer,
          price: 100,
          expenses: 0,
          targetDaily: 1,
          targetMonthly: 20,
          lastUpdated: updated ?? DateTime(2026, 1, 1),
          isDeleted: deleted,
        );

    test('records present on only one side are all kept', () {
      final r = MergeService.mergeById<Project>(
        [project('a')],
        [project('b')],
        (p) => p.id,
        (p) => p.lastUpdated,
      );
      expect(r.merged.map((p) => p.id).toSet(), {'a', 'b'});
      expect(r.stats.added, 1);
    });

    test('local data is never dropped for being absent from the import', () {
      // This is the guarantee that makes import a merge, not a replacement.
      final r = MergeService.mergeById<Project>(
        [project('a'), project('b'), project('c')],
        [], // an empty backup
        (p) => p.id,
        (p) => p.lastUpdated,
      );
      expect(r.merged.length, 3);
      expect(r.stats.added, 0);
    });

    test('the more recently edited copy wins a conflict', () {
      final older = project('a', updated: DateTime(2026, 1, 1));
      final newer = project('a', updated: DateTime(2026, 6, 1));

      final incomingNewer = MergeService.mergeById<Project>(
          [older], [newer], (p) => p.id, (p) => p.lastUpdated);
      expect(incomingNewer.merged.single.lastUpdated, DateTime(2026, 6, 1));
      expect(incomingNewer.stats.updated, 1);

      // And the other way round: a stale backup must not overwrite newer work
      final incomingOlder = MergeService.mergeById<Project>(
          [newer], [older], (p) => p.id, (p) => p.lastUpdated);
      expect(incomingOlder.merged.single.lastUpdated, DateTime(2026, 6, 1));
      expect(incomingOlder.stats.updated, 0);
      expect(incomingOlder.stats.unchanged, 1);
    });

    test('a recent deletion survives so it can propagate', () {
      final justDeleted = project('a', updated: DateTime.now(), deleted: true);
      final kept = MergeService.purgeOldDeleted(
          [justDeleted], (p) => p.isDeleted, (p) => p.lastUpdated);
      expect(kept, hasLength(1));
    });

    test('a deletion older than the retention window is dropped', () {
      final longGone = project('a',
          updated: DateTime.now().subtract(const Duration(days: 40)),
          deleted: true);
      final kept = MergeService.purgeOldDeleted(
          [longGone], (p) => p.isDeleted, (p) => p.lastUpdated);
      expect(kept, isEmpty);
    });

    test('live records are never purged regardless of age', () {
      final ancient =
          project('a', updated: DateTime(2020, 1, 1), deleted: false);
      final kept = MergeService.purgeOldDeleted(
          [ancient], (p) => p.isDeleted, (p) => p.lastUpdated);
      expect(kept, hasLength(1));
    });

    test('mergeBackup reports what happened per list', () {
      final outcome = MergeService.mergeBackup(
        localProjects: [project('a')],
        localHistory: const [],
        localExpenses: const [],
        incomingProjects: [project('a'), project('b')],
        incomingHistory: const [],
        incomingExpenses: const [],
      );
      expect(outcome.projects.length, 2);
      expect(outcome.projectStats.added, 1);
      expect(outcome.projectStats.unchanged, 1);
      expect(outcome.changedAnything, isTrue);
    });

    test('re-importing the same file changes nothing', () {
      final data = [project('a'), project('b')];
      final outcome = MergeService.mergeBackup(
        localProjects: data,
        localHistory: const [],
        localExpenses: const [],
        incomingProjects: data,
        incomingHistory: const [],
        incomingExpenses: const [],
      );
      expect(outcome.projects.length, 2);
      expect(outcome.changedAnything, isFalse);
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

    test('a backup survives a full export and re-import', () async {
      final project = Project(
        id: 'p1',
        name: 'ספר תורה',
        type: ProjectType.sefer,
        price: 100,
        expenses: 10,
        targetDaily: 2,
        targetMonthly: 40,
        totalPages: 245,
        linesPerPage: 42,
      );
      final session = WorkSession(
        id: 's1',
        projectId: 'p1',
        startTime: DateTime(2026, 5, 1, 9),
        endTime: DateTime(2026, 5, 1, 12),
        amount: 7,
        startLine: 1,
        endLine: 42,
        description: 'עמוד ז',
        isManual: false,
        linesPerPageAtEntry: 42,
      );
      final expense = Expense(
        id: 'e1',
        product: 'קלף',
        date: DateTime(2026, 5, 1),
        amount: 300,
      );

      SharedPreferences.setMockInitialValues({
        'projects': jsonEncode([project.toJson()]),
        'history': jsonEncode([session.toJson()]),
        'expenses': jsonEncode([expense.toJson()]),
      });

      // Export, then read it back the way the importer would.
      final exported = await BackupService.instance.buildBackupJson();
      final decoded = jsonDecode(exported) as Map<String, dynamic>;

      final reProjects = (decoded['projects'] as List)
          .map((e) => Project.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final reHistory = (decoded['history'] as List)
          .map((e) => WorkSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      final reExpenses = (decoded['expenses'] as List)
          .map((e) => Expense.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      // Importing into an empty device restores everything.
      final ontoEmpty = MergeService.mergeBackup(
        localProjects: const [],
        localHistory: const [],
        localExpenses: const [],
        incomingProjects: reProjects,
        incomingHistory: reHistory,
        incomingExpenses: reExpenses,
      );
      expect(ontoEmpty.projects.single.name, 'ספר תורה');
      expect(ontoEmpty.history.single.description, 'עמוד ז');
      expect(ontoEmpty.history.single.linesPerPageAtEntry, 42);
      expect(ontoEmpty.expenses.single.amount, 300);

      // Importing the same file again is a no-op, not a duplication.
      final twice = MergeService.mergeBackup(
        localProjects: ontoEmpty.projects,
        localHistory: ontoEmpty.history,
        localExpenses: ontoEmpty.expenses,
        incomingProjects: reProjects,
        incomingHistory: reHistory,
        incomingExpenses: reExpenses,
      );
      expect(twice.projects, hasLength(1));
      expect(twice.history, hasLength(1));
      expect(twice.changedAnything, isFalse);
    });

    test('importing onto a device with other work keeps both sides', () async {
      WorkSession s(String id, String projectId) => WorkSession(
            id: id,
            projectId: projectId,
            startTime: DateTime(2026, 5, 1),
            endTime: DateTime(2026, 5, 1, 1),
            amount: 1,
            startLine: 1,
            endLine: 10,
            description: id,
            isManual: false,
          );

      // The phone has work the computer does not, and vice versa.
      final outcome = MergeService.mergeBackup(
        localProjects: const [],
        localHistory: [s('phone-1', 'p1'), s('shared', 'p1')],
        localExpenses: const [],
        incomingProjects: const [],
        incomingHistory: [s('desktop-1', 'p1'), s('shared', 'p1')],
        incomingExpenses: const [],
      );

      expect(outcome.history.map((e) => e.id).toSet(),
          {'phone-1', 'desktop-1', 'shared'});
      expect(outcome.historyStats.added, 1);
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

  group('the working day is frozen when a session is recorded', () {
    WorkSession session(DateTime start, {DateTime? filedUnder}) => WorkSession(
          id: 's1',
          projectId: 'p1',
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
          amount: 1,
          startLine: 1,
          endLine: 42,
          description: '',
          isManual: false,
          workingDateAtEntry: filedUnder,
        );

    const oneAm = DayStart(boundary: DayBoundary.fixedHour, hour: 1);

    test('work just after midnight is filed under the previous day', () {
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 11, 0, 30), oneAm),
          DateTime(2026, 5, 10));
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 11, 1, 0), oneAm),
          DateTime(2026, 5, 11));
    });

    test('changing the boundary later does not re-file old work', () {
      // Written at 00:30 back when the day turned over at 01:00, and filed
      // under the 10th at the time.
      final old = session(DateTime(2026, 5, 11, 0, 30),
          filedUnder: DateTime(2026, 5, 10));

      // The writer now works to a different schedule.
      expect(DateLogic.workingDateOf(old, DayStart.midnight),
          DateTime(2026, 5, 10));
      expect(
          DateLogic.workingDateOf(
              old, const DayStart(boundary: DayBoundary.nightfall)),
          DateTime(2026, 5, 10));

      // And it still groups under the day it was counted on.
      expect(DateLogic.sessionIsOnDay(old, DateTime(2026, 5, 10), DayStart.midnight),
          isTrue);
      expect(
          DateLogic.sessionIsOnDay(old, DateTime(2026, 5, 11), DayStart.midnight),
          isFalse);
    });

    test('a session with no snapshot falls back to the current setting', () {
      // How every record written before this field existed behaves.
      final legacy = session(DateTime(2026, 5, 11, 0, 30));

      expect(DateLogic.workingDateOf(legacy, DayStart.midnight),
          DateTime(2026, 5, 11));
      expect(DateLogic.workingDateOf(legacy, oneAm), DateTime(2026, 5, 10));
    });

    test('month grouping follows the frozen day across a month boundary', () {
      // Written 00:30 on 1 June, filed under 31 May.
      final s = session(DateTime(2026, 6, 1, 0, 30),
          filedUnder: DateTime(2026, 5, 31));

      expect(DateLogic.sessionIsInMonth(s, DateTime(2026, 5), DayStart.midnight),
          isTrue);
      expect(DateLogic.sessionIsInMonth(s, DateTime(2026, 6), DayStart.midnight),
          isFalse);
    });

    test('the snapshot survives storage and an unrelated edit', () {
      final s = session(DateTime(2026, 5, 11, 0, 30),
          filedUnder: DateTime(2026, 5, 10));

      final restored = WorkSession.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(restored.workingDateAtEntry, DateTime(2026, 5, 10));

      // Editing the description must not disturb which day it belongs to.
      expect(restored.copyWith(description: 'x').workingDateAtEntry,
          DateTime(2026, 5, 10));

      // Restating the time does move it, when explicitly passed.
      expect(
          restored
              .copyWith(
                  startTime: DateTime(2026, 5, 11, 14),
                  workingDateAtEntry: DateTime(2026, 5, 11))
              .workingDateAtEntry,
          DateTime(2026, 5, 11));
    });
  });

  group('scroll map runs', () {
    test('work done in order collapses to two runs', () {
      final runs = unitRuns(245, {for (var i = 1; i <= 4; i++) i: 1.0});

      expect(runs.length, 2);
      expect(runs[0].from, 1);
      expect(runs[0].to, 4);
      expect(runs[0].isFull, isTrue);
      expect(runs[1].from, 5);
      expect(runs[1].to, 245);
      expect(runs[1].isEmpty, isTrue);
    });

    test('a part-written unit is a run of its own', () {
      final runs = unitRuns(10, {1: 1.0, 2: 1.0, 3: 0.5});

      expect(runs.length, 3);
      expect(runs[0].to, 2);
      expect(runs[1].from, 3);
      expect(runs[1].to, 3);
      expect(runs[1].isFull, isFalse);
      expect(runs[1].isEmpty, isFalse);
      expect(runs[2].from, 4);
    });

    test('a hole in the middle becomes findable', () {
      // Pages 1–3 and 6–8 written, 4–5 left for a correction.
      final runs = unitRuns(8, {
        1: 1.0,
        2: 1.0,
        3: 1.0,
        6: 1.0,
        7: 1.0,
        8: 1.0,
      });

      expect(runs.length, 3);
      expect(runs[1].from, 4);
      expect(runs[1].to, 5);
      expect(runs[1].isEmpty, isTrue);
      expect(runs[1].length, 2);
    });

    test('two adjacent partials do not merge into one run', () {
      // They are different amounts, and reporting them as one range would
      // claim a uniformity that is not there.
      final runs = unitRuns(3, {1: 0.25, 2: 0.75});

      expect(runs.length, 3);
      expect(runs[0].fill, 0.25);
      expect(runs[1].fill, 0.75);
      expect(runs[2].isEmpty, isTrue);
    });

    test('nothing written is one empty run, and no units is none', () {
      expect(unitRuns(5, const {}).length, 1);
      expect(unitRuns(5, const {}).single.isEmpty, isTrue);
      expect(unitRuns(0, const {}), isEmpty);
    });

    test('runs always cover every unit exactly once', () {
      final runs = unitRuns(50, {3: 1.0, 4: 0.5, 5: 1.0, 20: 1.0});
      var covered = 0;
      var expected = 1;
      for (final r in runs) {
        expect(r.from, expected);
        covered += r.length;
        expected = r.to + 1;
      }
      expect(covered, 50);
      expect(runs.last.to, 50);
    });
  });

  group('forward compatibility of saved records', () {
    test('a field from a newer version survives a round trip', () {
      // What an older build sees when it opens a file a newer one wrote.
      final fromTheFuture = <String, dynamic>{
        'id': 'p1',
        'name': 'ספר',
        'type': 0,
        'price': 100,
        'expenses': 0,
        'targetDaily': 0,
        'targetMonthly': 0,
        'somethingAddedLater': 'keep me',
        'nestedFutureField': {'a': 1, 'b': [2, 3]},
      };

      final project = Project.fromJson(fromTheFuture);
      expect(project.extraFields.keys,
          containsAll(['somethingAddedLater', 'nestedFutureField']));

      // Re-exporting must not drop them.
      final written = project.toJson();
      expect(written['somethingAddedLater'], 'keep me');
      expect(written['nestedFutureField'], {'a': 1, 'b': [2, 3]});
      // And editing must not either.
      expect(project.copyWith(name: 'אחר').toJson()['somethingAddedLater'],
          'keep me');
    });

    test('sessions and expenses keep unknown fields too', () {
      final session = WorkSession.fromJson(<String, dynamic>{
        'id': 's1',
        'projectId': 'p1',
        'startTime': '2026-05-03T09:00:00.000',
        'endTime': '2026-05-03T13:00:00.000',
        'amount': 1,
        'startLine': 1,
        'endLine': 42,
        'description': '',
        'isManual': false,
        'futureFlag': true,
      });
      expect(session.toJson()['futureFlag'], isTrue);

      final expense = Expense.fromJson(<String, dynamic>{
        'id': 'e1',
        'product': 'קלף',
        'date': '2026-05-01T00:00:00.000',
        'amount': 100,
        'futureCategory': 'x',
      });
      expect(expense.copyWith(amount: 120).toJson()['futureCategory'], 'x');
    });

    test('a missing field takes its default instead of throwing', () {
      // The minimum an older file might carry.
      final project = Project.fromJson(<String, dynamic>{'id': 'p1'});
      expect(project.type, ProjectType.sefer);
      expect(project.price, 0);
      expect(project.targetDaily, 0);
      expect(project.isDeleted, isFalse);

      // Numbers written as strings, which some producers do.
      final loose = Project.fromJson(<String, dynamic>{
        'id': 'p2',
        'price': '250',
        'totalPages': '245',
        'type': 1,
      });
      expect(loose.price, 250);
      expect(loose.totalPages, 245);
      expect(loose.type, ProjectType.mezuza);
    });

    test('an enum index from the future falls back rather than crashing', () {
      final project =
          Project.fromJson(<String, dynamic>{'id': 'p1', 'type': 99});
      expect(project.type, ProjectType.sefer);

      final expense = Expense.fromJson(
          <String, dynamic>{'id': 'e1', 'allocation': 99, 'amount': 5});
      expect(expense.allocation, ExpenseAllocation.month);
    });

    test('a record with no id is rejected, not silently half-read', () {
      expect(() => Project.fromJson(<String, dynamic>{'name': 'x'}),
          throwsA(isA<FormatException>()));
      expect(() => WorkSession.fromJson(<String, dynamic>{'amount': 1}),
          throwsA(isA<FormatException>()));
      expect(() => Expense.fromJson(<String, dynamic>{'amount': 1}),
          throwsA(isA<FormatException>()));
    });

    test('one bad record does not lose the rest of the list', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.projects': jsonEncode([
          {'id': 'good1', 'name': 'א', 'type': 0},
          {'name': 'no id at all'},
          'not even an object',
          {'id': 'good2', 'name': 'ב', 'type': 1},
        ]),
      });

      final loaded = await StorageService().loadProjects();
      expect(loaded.map((p) => p.id), ['good1', 'good2']);
    });
  });

  group('HebrewWorkCalendar — days that are never writing days', () {
    // Stated as Hebrew dates, because that is how the rules themselves are
    // stated. Nothing here depends on which Gregorian day a festival lands on.
    //
    // Every configurable category is set to a full working day, so anything
    // still off is off because it is fixed.
    WorkDay day(int year, int month, int dayOfMonth,
            [WorkCalendarRules r = shabbatOnly]) =>
        HebrewWorkCalendar.classifyHebrewDate(year, month, dayOfMonth, r);

    test('Yom Tov, whatever else is configured', () {
      for (final y in [5785, 5786, 5787]) {
        expect(day(y, JewishDate.NISSAN, 15).reason, NonWorkReason.yomTov,
            reason: 'first day of Pesach $y');
        expect(day(y, JewishDate.TISHREI, 1).reason, NonWorkReason.yomTov,
            reason: 'Rosh Hashana $y');
        expect(day(y, JewishDate.TISHREI, 10).reason, NonWorkReason.yomTov,
            reason: 'Yom Kippur $y');
        expect(day(y, JewishDate.SIVAN, 6).reason, NonWorkReason.yomTov,
            reason: 'Shavuot $y');
        expect(day(y, JewishDate.TISHREI, 22).reason, NonWorkReason.yomTov,
            reason: 'Shemini Atzeret $y');
      }
    });

    test('Chol HaMoed, including Hoshana Rabba', () {
      for (var d = 17; d <= 21; d++) {
        expect(
            day(5786, JewishDate.TISHREI, d).reason, NonWorkReason.cholHamoed,
            reason: '$d Tishrei');
      }
      for (var d = 17; d <= 19; d++) {
        expect(day(5786, JewishDate.NISSAN, d).reason, NonWorkReason.cholHamoed,
            reason: '$d Nisan');
      }
    });

    test('the eves of festivals', () {
      expect(day(5786, JewishDate.NISSAN, 14).reason, NonWorkReason.erevYomTov);
      expect(day(5786, JewishDate.SIVAN, 5).reason, NonWorkReason.erevYomTov);
      expect(day(5786, JewishDate.ELUL, 29).reason, NonWorkReason.erevYomTov);
      expect(day(5786, JewishDate.TISHREI, 9).reason, NonWorkReason.erevYomTov);
      expect(
          day(5786, JewishDate.TISHREI, 14).reason, NonWorkReason.erevYomTov);
      // 20 Nisan is Chol HaMoed and also the eve of the seventh day.
      expect(day(5786, JewishDate.NISSAN, 20).reason, NonWorkReason.erevYomTov);
    });

    test('Purim and Shushan Purim', () {
      expect(day(5786, JewishDate.ADAR, 14).reason, NonWorkReason.purim);
      expect(day(5786, JewishDate.ADAR, 15).reason, NonWorkReason.purim);
      // In a leap year Purim is in Adar II.
      expect(day(5787, JewishDate.ADAR_II, 14).reason, NonWorkReason.purim);
      expect(day(5787, JewishDate.ADAR_II, 15).reason, NonWorkReason.purim);
    });

    test('Tisha BeAv, and its eve, wherever the fast lands', () {
      for (var y = 5780; y <= 5800; y++) {
        var observed = 0;
        for (var d = 9; d <= 10; d++) {
          if (day(y, JewishDate.AV, d).reason == NonWorkReason.tishaBeav) {
            observed = d;
            break;
          }
        }
        expect(observed, isNot(0), reason: 'no Tisha BeAv found in $y');

        final before = day(y, JewishDate.AV, observed - 1);
        expect(before.reason,
            anyOf(NonWorkReason.erevTishaBeav, NonWorkReason.shabbat),
            reason: 'day before Tisha BeAv $y');
      }
    });

    test('Shabbat beats a category set to a full working day', () {
      // Chanukah is a full working day in these rules; a Shabbat of Chanukah is
      // still Shabbat. Walked forward across the eight days, which span two
      // Hebrew months.
      final jc = JewishCalendar.initDate(5786, JewishDate.KISLEV, 25);
      for (var i = 0; i < 8; i++) {
        if (jc.getDayOfWeek() == JewishDate.saturday) {
          final classified = HebrewWorkCalendar.classify(jc, shabbatOnly);
          expect(classified.value, 0);
          expect(classified.reason, NonWorkReason.shabbat);
          return;
        }
        jc.forward();
      }
      fail('no Shabbat found during Chanukah 5786');
    });

    test('Chol HaMoed closes a Friday that would otherwise be half a day', () {
      // Chol HaMoed Pesach in Israel is 16–20 Nisan.
      final jc =
          JewishCalendar.initDate(5786, JewishDate.NISSAN, 16, inIsrael: true);
      for (var i = 0; i < 5; i++) {
        if (jc.getDayOfWeek() == JewishDate.friday) {
          final classified = HebrewWorkCalendar.classify(jc, shabbatOnly);
          expect(classified.value, 0);
          expect(classified.reason,
              anyOf(NonWorkReason.cholHamoed, NonWorkReason.erevYomTov));
          return;
        }
        jc.forward();
      }
      fail('no Friday found in Chol HaMoed Pesach 5786');
    });

    test('Chol HaMoed starts a day earlier in Israel', () {
      expect(day(5786, JewishDate.NISSAN, 16).reason, NonWorkReason.cholHamoed);
      expect(
          day(5786, JewishDate.NISSAN, 16,
                  shabbatOnly.copyWith(inIsrael: false))
              .reason,
          NonWorkReason.yomTov);
    });

    test('days that are always ordinary working days', () {
      // Rosh Chodesh, Tu BiShvat, Pesach Sheni, Purim Katan, Tu BeAv and Yom
      // HaAtzmaut are not settings, and are never skipped.
      final ordinary = <String, ({int month, int day})>{
        'Tu BiShvat': (month: JewishDate.SHEVAT, day: 15),
        'Pesach Sheni': (month: JewishDate.IYAR, day: 14),
        'Tu BeAv': (month: JewishDate.AV, day: 15),
        'Rosh Chodesh Iyar': (month: JewishDate.IYAR, day: 1),
        'Yom HaAtzmaut': (month: JewishDate.IYAR, day: 5),
      };

      // Checked against the default rules, so Friday and Shabbat are off and
      // are skipped over — the weekday, not the day itself, would be the reason.
      ordinary.forEach((name, d) {
        final jc = JewishCalendar.initDate(5786, d.month, d.day);
        if (jc.getDayOfWeek() == JewishDate.saturday ||
            jc.getDayOfWeek() == JewishDate.friday) {
          return;
        }
        expect(
            HebrewWorkCalendar.classifyHebrewDate(
                    5786, d.month, d.day, WorkCalendarRules.standard)
                .value,
            1,
            reason: name);
      });

      final katan = JewishCalendar.initDate(5787, JewishDate.ADAR, 14);
      if (katan.getDayOfWeek() != JewishDate.saturday &&
          katan.getDayOfWeek() != JewishDate.friday) {
        expect(
            HebrewWorkCalendar.classifyHebrewDate(
                    5787, JewishDate.ADAR, 14, WorkCalendarRules.standard)
                .value,
            1,
            reason: 'Purim Katan');
      }
    });
  });

  group('HebrewWorkCalendar — configurable categories', () {
    WorkDay day(int year, int month, int dayOfMonth, WorkCalendarRules r) =>
        HebrewWorkCalendar.classifyHebrewDate(year, month, dayOfMonth, r);

    /// The first day in a Hebrew month range that falls on [weekday].
    int findWeekday(int year, int month, int from, int to, int weekday) {
      for (var d = from; d <= to; d++) {
        if (JewishCalendar.initDate(year, month, d).getDayOfWeek() == weekday) {
          return d;
        }
      }
      fail('no weekday $weekday between $from and $to of month $month');
    }

    test('Friday is half a day or nothing, never a full one', () {
      final friday =
          findWeekday(5786, JewishDate.IYAR, 15, 28, JewishDate.friday);

      expect(
          day(5786, JewishDate.IYAR, friday,
                  shabbatOnly.copyWith(friday: DayWeight.half))
              .value,
          0.5);
      expect(
          day(5786, JewishDate.IYAR, friday,
                  shabbatOnly.copyWith(friday: DayWeight.none))
              .value,
          0);
      // A stored `full` is clamped rather than honoured.
      expect(
          day(5786, JewishDate.IYAR, friday,
                  shabbatOnly.copyWith(friday: DayWeight.full))
              .value,
          0);
      // And clamped on the way in from storage too.
      expect(
          WorkCalendarRules.fromJson(
                  const {'schemaVersion': 2, 'friday': 'full'})
              .friday,
          DayWeight.none);
    });

    test('motzei Shabbat is half a day or nothing, never a full one', () {
      final shabbat =
          findWeekday(5786, JewishDate.IYAR, 15, 28, JewishDate.saturday);

      expect(day(5786, JewishDate.IYAR, shabbat, shabbatOnly).value, 0);
      expect(
          day(5786, JewishDate.IYAR, shabbat,
                  shabbatOnly.copyWith(motzeiShabbat: DayWeight.half))
              .value,
          0.5);
      // A stored `full` is clamped rather than honoured.
      expect(
          day(5786, JewishDate.IYAR, shabbat,
                  shabbatOnly.copyWith(motzeiShabbat: DayWeight.full))
              .value,
          0);
    });

    test('each fast is set separately', () {
      final rules = shabbatOnly.copyWith(fastTenthTevet: DayWeight.none);
      // 10 Tevet never moves, so it is the safest fast to assert on.
      expect(day(5786, JewishDate.TEVES, 10, rules).value, 0);
      expect(day(5786, JewishDate.TEVES, 10, rules).reason,
          NonWorkReason.fastTenthTevet);
      // The other three are untouched by that setting.
      expect(day(5786, JewishDate.TEVES, 10, shabbatOnly).value, 1);
    });

    test('the window before Pesach follows the chosen number of days', () {
      final three = shabbatOnly.copyWith(
          daysBeforePesach: 3, beforePesach: DayWeight.none);
      expect(three.pesachWindow, (from: 12, to: 14));
      expect(day(5786, JewishDate.NISSAN, 12, three).value, 0);
      // 11 Nisan is outside a three-day window.
      expect(day(5786, JewishDate.NISSAN, 11, three).value, 1);

      final seven = shabbatOnly.copyWith(
          daysBeforePesach: 7, beforePesach: DayWeight.none);
      expect(seven.pesachWindow, (from: 8, to: 14));
      expect(day(5786, JewishDate.NISSAN, 8, seven).value, 0);
      expect(day(5786, JewishDate.NISSAN, 7, seven).value, 1);

      // Zero clears the window entirely.
      expect(shabbatOnly.copyWith(daysBeforePesach: 0).pesachWindow, isNull);
      // And it can never reach back into Adar.
      expect(shabbatOnly.copyWith(daysBeforePesach: 40).pesachWindow,
          (from: 1, to: 14));
    });

    test('the days between Yom Kippur and Sukkot', () {
      final off =
          shabbatOnly.copyWith(betweenYomKippurAndSukkot: DayWeight.none);
      for (var d = 11; d <= 13; d++) {
        expect(day(5786, JewishDate.TISHREI, d, off).value, 0, reason: '$d');
        // Shabbat is fixed and outranks the window, so it can be the reason on
        // whichever of the three days it falls.
        expect(
            day(5786, JewishDate.TISHREI, d, off).reason,
            anyOf(NonWorkReason.betweenYomKippurAndSukkot,
                NonWorkReason.shabbat),
            reason: '$d Tishrei');
      }
    });

    test('Isru Chag is a day later outside Israel', () {
      final israel = shabbatOnly.copyWith(isruChag: DayWeight.none);
      final diaspora = israel.copyWith(inIsrael: false);

      expect(day(5786, JewishDate.NISSAN, 22, israel).reason,
          NonWorkReason.isruChag);
      // 22 Nisan is still Yom Tov abroad; Isru Chag is the 23rd.
      expect(day(5786, JewishDate.NISSAN, 22, diaspora).reason,
          NonWorkReason.yomTov);
      expect(day(5786, JewishDate.NISSAN, 23, diaspora).reason,
          NonWorkReason.isruChag);
    });

    test('the most restrictive setting wins where two overlap', () {
      // A Friday during Chanukah is covered by both settings.
      final walker = JewishCalendar.initDate(5786, JewishDate.KISLEV, 25);
      JewishCalendar? friday;
      for (var i = 0; i < 8; i++) {
        if (walker.getDayOfWeek() == JewishDate.friday) {
          friday = walker.clone();
          break;
        }
        walker.forward();
      }
      expect(friday, isNotNull, reason: 'no Friday during Chanukah 5786');

      WorkDay withRules(DayWeight fri, DayWeight chan) =>
          HebrewWorkCalendar.classify(friday!,
              shabbatOnly.copyWith(friday: fri, chanukah: chan));

      // Friday is capped at half, so half is the most this day can ever be.
      expect(withRules(DayWeight.half, DayWeight.full).value, 0.5);
      expect(withRules(DayWeight.half, DayWeight.half).value, 0.5);
      // Either one saying "not a working day" settles it.
      expect(withRules(DayWeight.half, DayWeight.none).value, 0);
      expect(withRules(DayWeight.none, DayWeight.full).value, 0);
    });
  });

  group('HebrewWorkCalendar — counting and planning', () {
    test('an ordinary week is five days, or five and a half with Friday', () {
      // 15–21 Iyar 5786: seven consecutive days with no festival in them.
      // Sunday to Thursday is five, Shabbat is nothing, and Friday is worth
      // whatever it is set to — never more than a half.
      final from = JewishCalendar.initDate(5786, JewishDate.IYAR, 15)
          .getGregorianCalendar();
      final to = JewishCalendar.initDate(5786, JewishDate.IYAR, 21)
          .getGregorianCalendar();

      expect(HebrewWorkCalendar.countWorkDays(from, to, shabbatOnly), 5.5);
      expect(HebrewWorkCalendar.countWorkDays(from, to, shabbatAndFriday), 5);
    });

    test('counting is inclusive of both ends and never negative', () {
      final d = DateTime(2026, 5, 4);
      expect(HebrewWorkCalendar.countWorkDays(d, d, shabbatOnly),
          inInclusiveRange(0, 1));
      expect(
          HebrewWorkCalendar.countWorkDays(
              d, d.subtract(const Duration(days: 5)), shabbatOnly),
          0);
    });

    test('a plan never finishes on a day nobody is writing', () {
      // Walk a whole year of starting days against the full default rules.
      for (var offset = 0; offset < 365; offset += 7) {
        final start = DateTime(2026, 1, 1).add(Duration(days: offset));
        final plan = HebrewWorkCalendar.plan(
          from: start,
          workDaysNeeded: 12,
          rules: WorkCalendarRules.standard,
        )!;

        final landed = HebrewWorkCalendar.classify(
          HebrewWorkCalendar.hebrewDayOf(
              plan.completionDate, WorkCalendarRules.standard),
          WorkCalendarRules.standard,
        );
        expect(landed.isOff, isFalse,
            reason: 'starting $start finished on ${landed.reason?.label}');
      }
    });

    test('festivals push a delivery date out, and the reasons add up', () {
      // Ten working days starting on 1 Nisan run straight into Pesach.
      final start = JewishCalendar.initDate(5786, JewishDate.NISSAN, 1)
          .getGregorianCalendar();
      final plan = HebrewWorkCalendar.plan(
        from: start,
        workDaysNeeded: 10,
        rules: WorkCalendarRules.standard,
      )!;

      expect(plan.calendarDays, greaterThan(10));
      expect(plan.skippedTotal, plan.calendarDays - 10);
      expect(plan.skipped.keys, contains(NonWorkReason.yomTov));
      expect(plan.skipped.keys, contains(NonWorkReason.cholHamoed));
    });

    test('half days accumulate without drifting a day', () {
      final halves = shabbatOnly.copyWith(
        friday: DayWeight.half,
        motzeiShabbat: DayWeight.half,
      );
      final start = JewishCalendar.initDate(5786, JewishDate.IYAR, 15)
          .getGregorianCalendar();
      final plan = HebrewWorkCalendar.plan(
          from: start, workDaysNeeded: 7, rules: halves)!;

      // The plan must be the *earliest* day the work is done: seven days of
      // writing fit into it, and not into a day less.
      expect(
          HebrewWorkCalendar.countWorkDays(start, plan.completionDate, halves),
          greaterThanOrEqualTo(7));
      expect(
          HebrewWorkCalendar.countWorkDays(start,
              plan.completionDate.subtract(const Duration(days: 1)), halves),
          lessThan(7));
    });

    test('nothing to do yields no plan rather than today', () {
      expect(
          HebrewWorkCalendar.plan(
              from: DateTime(2026, 5, 4),
              workDaysNeeded: 0,
              rules: shabbatOnly),
          isNull);
      expect(
          HebrewWorkCalendar.plan(
              from: DateTime(2026, 5, 4),
              workDaysNeeded: double.nan,
              rules: shabbatOnly),
          isNull);
    });

    test('daysOff reports half days as well as full ones', () {
      final halves = shabbatOnly.copyWith(friday: DayWeight.half);
      final from = JewishCalendar.initDate(5786, JewishDate.IYAR, 15)
          .getGregorianCalendar();
      final to = JewishCalendar.initDate(5786, JewishDate.IYAR, 21)
          .getGregorianCalendar();

      final entries = HebrewWorkCalendar.daysOff(from, to, halves);
      expect(entries.any((e) => e.day.value == 0.5), isTrue);
      expect(entries.any((e) => e.day.value == 0), isTrue);
    });
  });

  group('WorkCalendarRules storage', () {
    test('survives a round trip', () {
      const original = WorkCalendarRules(
        inIsrael: false,
        friday: DayWeight.half,
        motzeiShabbat: DayWeight.half,
        chanukah: DayWeight.full,
        fastTenthTevet: DayWeight.half,
        daysBeforePesach: 3,
        lagBaomer: DayWeight.full,
      );
      final restored = WorkCalendarRules.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      expect(restored.inIsrael, isFalse);
      expect(restored.friday, DayWeight.half);
      expect(restored.motzeiShabbat, DayWeight.half);
      expect(restored.chanukah, DayWeight.full);
      expect(restored.fastTenthTevet, DayWeight.half);
      expect(restored.daysBeforePesach, 3);
      expect(restored.lagBaomer, DayWeight.full);
    });

    test('an empty or unknown blob falls back to the defaults', () {
      final blank = WorkCalendarRules.fromJson(const {'schemaVersion': 2});
      expect(blank.friday, DayWeight.none);
      expect(blank.daysBeforePesach, 7);
      expect(blank.inIsrael, isTrue);

      // Keys this build has never heard of must not break it.
      final future = WorkCalendarRules.fromJson(const {
        'schemaVersion': 99,
        'friday': 'half',
        'somethingAddedLater': {'nested': true},
      });
      expect(future.friday, DayWeight.half);
    });

    test('migrates the first stored shape', () {
      // The version-1 blob: one boolean per category, and no schemaVersion.
      final v1 = <String, dynamic>{
        'inIsrael': true,
        'friday': 'half',
        'motzeiShabbatHalfDay': true,
        'skipCholHamoed': true,
        'skipFasts': false,
        'skipChanukah': true,
        'skipWeekBeforePesach': true,
        'skipBetweenYomKippurAndSukkot': false,
        'skipMinorHolidays': false,
        'skipRoshChodesh': true,
      };
      final migrated = WorkCalendarRules.fromJson(v1);

      expect(migrated.friday, DayWeight.half);
      expect(migrated.motzeiShabbat, DayWeight.half);
      // "skip" became "not a working day", its absence a full day.
      expect(migrated.chanukah, DayWeight.none);
      expect(migrated.fastTenthTevet, DayWeight.full);
      expect(migrated.beforePesach, DayWeight.none);
      expect(migrated.betweenYomKippurAndSukkot, DayWeight.full);
      expect(migrated.daysBeforePesach, 7);
    });
  });

  group('DayStart and the zmanim clock', () {
    test('survives a round trip and tolerates an unknown boundary', () {
      const original = DayStart(boundary: DayBoundary.nightfall, hour: 3);
      final restored = DayStart.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);
      expect(restored.boundary, DayBoundary.nightfall);
      expect(restored.hour, 3);

      final unknown =
          DayStart.fromJson(const {'boundary': 'somethingNew', 'hour': 4});
      // Falls back on the hour that is present rather than losing the setting.
      expect(unknown.boundary, DayBoundary.fixedHour);
      expect(unknown.hour, 4);
    });

    test('carries the old standalone rollover hour forward', () {
      expect(DayStart.fromRolloverHour(0).boundary, DayBoundary.midnight);
      expect(DayStart.fromRolloverHour(2).boundary, DayBoundary.fixedHour);
      expect(DayStart.fromRolloverHour(2).hour, 2);
      // Out-of-range values are clamped rather than stored as-is.
      expect(DayStart.fromRolloverHour(99).hour, 23);
    });

    test('nightfall comes after sunset, both in the evening', () {
      final date = DateTime(2026, 7, 15);
      final sunset = HebrewClock.sunset(date)!;
      final night = HebrewClock.nightfall(date)!;

      expect(sunset.hour, inInclusiveRange(18, 21));
      expect(night.isAfter(sunset), isTrue);
      expect(night.difference(sunset).inMinutes, inInclusiveRange(20, 60));
    });

    test('an evening boundary files work after it under the next day', () {
      const nightfall = DayStart(boundary: DayBoundary.nightfall);
      final summer = DateTime(2026, 7, 15);
      final night = HebrewClock.nightfall(summer)!;

      expect(DateLogic.effectiveDate(
              night.subtract(const Duration(minutes: 10)), nightfall),
          DateTime(2026, 7, 15));
      expect(
          DateLogic.effectiveDate(
              night.add(const Duration(minutes: 10)), nightfall),
          DateTime(2026, 7, 16));
    });

    test('a morning boundary files work before it under the previous day', () {
      const early = DayStart(boundary: DayBoundary.fixedHour, hour: 2);
      expect(DateLogic.effectiveDate(DateTime(2026, 7, 15, 1, 30), early),
          DateTime(2026, 7, 14));
      expect(DateLogic.effectiveDate(DateTime(2026, 7, 15, 23, 30), early),
          DateTime(2026, 7, 15));
    });
  });


  group('CompletionEstimator', () {
    Project sefer({int pages = 100, int targetDaily = 0}) => Project(
          id: 'p1',
          name: 'ספר',
          type: ProjectType.sefer,
          price: 100,
          expenses: 0,
          targetDaily: targetDaily,
          targetMonthly: 0,
          totalPages: pages,
          linesPerPage: 42,
        );

    WorkSession page(int index, DateTime day) => WorkSession(
          id: 's$index',
          projectId: 'p1',
          startTime: DateTime(day.year, day.month, day.day, 9),
          endTime: DateTime(day.year, day.month, day.day, 13),
          amount: index,
          startLine: 1,
          endLine: 42,
          description: '',
          isManual: false,
        );

    test('no stated size means no estimate', () {
      final p = Project(
        id: 'p1',
        name: 'מזוזות',
        type: ProjectType.mezuza,
        price: 100,
        expenses: 0,
        targetDaily: 2,
        targetMonthly: 0,
      );
      expect(
          CompletionEstimator.estimate(
              project: p, history: const [], rules: shabbatOnly),
          isNull);

      final sized = p.copyWith(targetUnits: 10);
      expect(
          CompletionEstimator.estimate(
              project: sized, history: const [], rules: shabbatOnly),
          isNotNull);
    });

    test('falls back to the daily target when nothing was recorded', () {
      final e = CompletionEstimator.estimate(
        project: sefer(pages: 10, targetDaily: 2),
        history: const [],
        rules: shabbatOnly,
        from: DateTime(2026, 5, 4),
      )!;

      expect(e.paceMeasured, isFalse);
      expect(e.unitsPerWorkDay, 2);
      expect(e.remainingUnits, 10);
      expect(e.workDaysLeft, 5);
    });

    test('measures the real pace once there is work to measure', () {
      // Two pages written across a Sunday and a Monday: one page per work day.
      final history = [
        page(1, DateTime(2026, 5, 3)),
        page(2, DateTime(2026, 5, 4)),
      ];
      final e = CompletionEstimator.estimate(
        project: sefer(pages: 10),
        history: history,
        rules: shabbatOnly,
        from: DateTime(2026, 5, 5),
      )!;

      expect(e.paceMeasured, isTrue);
      expect(e.doneUnits, 2);
      expect(e.unitsPerWorkDay, 1);
      expect(e.remainingUnits, 8);
    });

    test('a finished project has nothing left to estimate', () {
      final history =
          List.generate(10, (i) => page(i + 1, DateTime(2026, 5, 3)));
      expect(
          CompletionEstimator.estimate(
              project: sefer(pages: 10), history: history, rules: shabbatOnly),
          isNull);
    });

    test('required pace answers only when the deadline is still reachable', () {
      expect(
        CompletionEstimator.paceRequiredFor(
          remainingUnits: 10,
          deadline: DateTime(2026, 5, 1),
          rules: shabbatOnly,
          from: DateTime(2026, 5, 4),
        ),
        isNull,
      );
      // Monday 4 May to Thursday 7 May inclusive is four working days.
      expect(
        CompletionEstimator.paceRequiredFor(
          remainingUnits: 8,
          deadline: DateTime(2026, 5, 7),
          rules: shabbatAndFriday,
          from: DateTime(2026, 5, 4),
        ),
        2,
      );
    });
  });

  group('ExpenseLogic.averagePerUnit', () {
    test('learns the real material cost from recorded expenses', () {
      final project = Project(
        id: 'p1',
        name: 'מזוזות',
        type: ProjectType.mezuza,
        price: 200,
        expenses: 0,
        targetDaily: 0,
        targetMonthly: 0,
        targetUnits: 10,
      );
      final history = <WorkSession>[
        WorkSession(
          id: 's1',
          projectId: 'p1',
          startTime: DateTime(2026, 5, 3, 9),
          endTime: DateTime(2026, 5, 3, 13),
          amount: 5, // five mezuzot
          startLine: 0,
          endLine: 0,
          description: '',
          isManual: false,
        ),
      ];
      final expenses = [
        Expense(
          id: 'e1',
          product: 'קלף מזוזות',
          date: DateTime(2026, 5, 1),
          amount: 250,
          allocation: ExpenseAllocation.project,
          projectIds: const ['p1'],
        ),
        // A monthly overhead must not be charged to a single mezuza.
        Expense(
          id: 'e2',
          product: 'חדר סופרים',
          date: DateTime(2026, 5, 1),
          amount: 900,
          allocation: ExpenseAllocation.month,
        ),
      ];

      expect(
          ExpenseLogic.averagePerUnit(
              ProjectType.mezuza, [project], history, expenses),
          50);
    });

    test('nothing recorded gives null rather than zero', () {
      expect(
          ExpenseLogic.averagePerUnit(
              ProjectType.tefillin, const [], const [], const []),
          isNull);
    });
  });

  group('SessionLogic.splitRange', () {
    final start = DateTime(2026, 7, 20, 9);
    final end = DateTime(2026, 7, 20, 12);

    test('one part is the whole stretch', () {
      final slices = SessionLogic.splitRange(start: start, end: end, parts: 1);
      expect(slices, hasLength(1));
      expect(slices.single.start, start);
      expect(slices.single.end, end);
    });

    test('the parts add back up to exactly what was entered', () {
      // The point of the whole thing: five pages written in an hour are an
      // hour, not five.
      for (final parts in [2, 3, 5, 7, 245]) {
        final slices =
            SessionLogic.splitRange(start: start, end: end, parts: parts);
        expect(slices, hasLength(parts));
        final total = slices.fold(
            Duration.zero, (sum, s) => sum + s.end.difference(s.start));
        expect(total, end.difference(start), reason: '$parts parts');
      }
    });

    test('the parts run consecutively from the start to the end', () {
      final slices = SessionLogic.splitRange(start: start, end: end, parts: 7);
      expect(slices.first.start, start);
      expect(slices.last.end, end);
      for (var i = 1; i < slices.length; i++) {
        expect(slices[i].start, slices[i - 1].end,
            reason: 'a gap or an overlap at slice $i');
      }
    });

    test('an entry with no working time splits into nothing', () {
      final slices =
          SessionLogic.splitRange(start: start, end: start, parts: 4);
      expect(slices, hasLength(4));
      for (final s in slices) {
        expect(s.end.difference(s.start), Duration.zero);
      }
    });
  });

  group('WorkSession.timeRecorded', () {
    WorkSession session({
      required DateTime start,
      required DateTime end,
      bool? timeRecorded,
    }) =>
        WorkSession(
          id: 's',
          projectId: 'p',
          startTime: start,
          endTime: end,
          amount: 1,
          startLine: 1,
          endLine: 42,
          description: '',
          isManual: true,
          timeRecorded: timeRecorded,
        );

    test('survives a round trip in both states', () {
      final withTime = session(
        start: DateTime(2026, 7, 20, 9),
        end: DateTime(2026, 7, 20, 12),
        timeRecorded: true,
      );
      final without = session(
        start: DateTime(2026, 7, 20, 12),
        end: DateTime(2026, 7, 20, 12),
        timeRecorded: false,
      );

      expect(
          WorkSession.fromJson(jsonDecode(jsonEncode(withTime.toJson())))
              .timeRecorded,
          isTrue);
      expect(
          WorkSession.fromJson(jsonDecode(jsonEncode(without.toJson())))
              .timeRecorded,
          isFalse);
    });

    test('what was stored wins over what the times suggest', () {
      // The whole point of the field: a writer who did not give a time is not
      // the same as a sitting that measured none, and the stored answer is not
      // re-derived behind their back.
      final stated = session(
        start: DateTime(2026, 7, 20, 9),
        end: DateTime(2026, 7, 20, 12),
        timeRecorded: false,
      );
      expect(
          WorkSession.fromJson(jsonDecode(jsonEncode(stated.toJson())))
              .timeRecorded,
          isFalse);
    });

    test('a session written before the field existed reads its times', () {
      // The migration is lossless because the older writer had exactly one way
      // to say "no time": an end equal to the start.
      Map<String, dynamic> legacy(String start, String end) => {
            'id': 's',
            'projectId': 'p',
            'startTime': start,
            'endTime': end,
            'amount': 1,
            'startLine': 1,
            'endLine': 42,
            'description': '',
            'isManual': true,
          };

      expect(
          WorkSession.fromJson(
                  legacy('2026-07-20T09:00:00', '2026-07-20T12:00:00'))
              .timeRecorded,
          isTrue);
      expect(
          WorkSession.fromJson(
                  legacy('2026-07-20T12:00:00', '2026-07-20T12:00:00'))
              .timeRecorded,
          isFalse);
    });

    test('editing an amount does not invent a time', () {
      final without = session(
        start: DateTime(2026, 7, 20, 12),
        end: DateTime(2026, 7, 20, 12),
        timeRecorded: false,
      );
      expect(without.copyWith(amount: 7).timeRecorded, isFalse);
      expect(without.copyWith(timeRecorded: true).timeRecorded, isTrue);
    });

    test('an unstated value is read off the times', () {
      expect(
          session(
                  start: DateTime(2026, 7, 20, 9),
                  end: DateTime(2026, 7, 20, 12))
              .timeRecorded,
          isTrue);
      expect(
          session(
                  start: DateTime(2026, 7, 20, 12),
                  end: DateTime(2026, 7, 20, 12))
              .timeRecorded,
          isFalse);
    });
  });

  group('QuoteExpense', () {
    test('a cost per unit is the same whatever the quantity', () {
      const parchment =
          QuoteExpense(label: 'קלף', amount: 45, perUnit: true);
      expect(parchment.perUnitOver(1), 45);
      expect(parchment.perUnitOver(120), 45);
    });

    test('a cost for the whole job is spread over the quantity', () {
      const delivery =
          QuoteExpense(label: 'משלוח', amount: 60, perUnit: false);
      expect(delivery.perUnitOver(10), 6);
      expect(delivery.perUnitOver(3), closeTo(20, 0.001));
    });

    test('a one-off cost with no quantity yet charges nothing', () {
      // The quantity field is a text field, so it is empty for as long as it
      // takes to type into. Dividing by it would put an infinity in the price.
      const delivery =
          QuoteExpense(label: 'משלוח', amount: 60, perUnit: false);
      expect(delivery.perUnitOver(0), 0);
    });
  });
}
