// Unit tests for the pure logic of the app.
//
// The previous file here was the default Flutter counter smoke test, which did
// not compile and tested nothing relevant to this project.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/hebrew_utils.dart';
import 'package:sofer_vmone/logic/date_logic.dart';
import 'package:sofer_vmone/logic/completion_estimator.dart';
import 'package:sofer_vmone/logic/expense_logic.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/logic/id_generator.dart';
import 'package:sofer_vmone/logic/merge_service.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/profit_calculator.dart';
import 'package:sofer_vmone/logic/project_analytics.dart';
import 'package:sofer_vmone/logic/quote_calculator.dart';
import 'package:sofer_vmone/logic/session_logic.dart';
import 'package:sofer_vmone/models.dart';

/// Only the days nobody writes on, so arithmetic tests stay independent of
/// wherever in the year the sample dates happen to fall. The festival rules
/// themselves are exercised in the HebrewWorkCalendar group.
const shabbatOnly = WorkCalendarRules(
  friday: FridayWork.full,
  skipCholHamoed: false,
  skipErevYomTov: false,
  skipFasts: false,
  skipErevTishaBeav: false,
  skipBetweenYomKippurAndSukkot: false,
  skipWeekBeforePesach: false,
  skipPurim: false,
  skipChanukah: false,
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
    test('rollover 0 behaves as the plain calendar date', () {
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 10, 1, 30), 0),
          DateTime(2026, 5, 10));
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 10, 23, 0), 0),
          DateTime(2026, 5, 10));
    });

    test('before the rollover hour belongs to the previous day', () {
      // 01:00 with rollover at 02:00 is still "yesterday"
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 10, 1, 0), 2),
          DateTime(2026, 5, 9));
      // 02:00 exactly starts the new day
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 10, 2, 0), 2),
          DateTime(2026, 5, 10));
    });

    test('crosses a month boundary correctly', () {
      // 01:00 on the 1st, rollover 3 → belongs to the last day of April
      expect(DateLogic.effectiveDate(DateTime(2026, 5, 1, 1, 0), 3),
          DateTime(2026, 4, 30));
    });

    test('crosses a year boundary correctly', () {
      expect(DateLogic.effectiveDate(DateTime(2026, 1, 1, 0, 30), 2),
          DateTime(2025, 12, 31));
    });

    test('a late-night session and the day it belongs to agree', () {
      final lateNight = DateTime(2026, 5, 10, 1, 15);
      final theWorkingDay = DateTime(2026, 5, 9, 20, 0);
      expect(DateLogic.isSameWorkingDay(lateNight, theWorkingDay, 2), isTrue);
      // Without the rollover they would be different days
      expect(DateLogic.isSameWorkingDay(lateNight, theWorkingDay, 0), isFalse);
    });

    test('month grouping honours the rollover at a boundary', () {
      final lateNight = DateTime(2026, 5, 1, 1, 0);
      expect(
          DateLogic.isSameWorkingMonth(lateNight, DateTime(2026, 4), 3), isTrue);
      expect(DateLogic.isSameWorkingMonth(lateNight, DateTime(2026, 5), 3),
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

  group('HebrewWorkCalendar — days off', () {
    // Stated as Hebrew dates, because that is how the rules themselves are
    // stated. Nothing here depends on which Gregorian day a festival lands on
    // in any particular year.
    const rules = WorkCalendarRules.standard;

    WorkDay day(int year, int month, int dayOfMonth,
            [WorkCalendarRules r = rules]) =>
        HebrewWorkCalendar.classifyHebrewDate(year, month, dayOfMonth, r);

    test('Yom Tov is off however the rest is configured', () {
      // Every optional rule turned off; these days must still be off.
      const everythingAllowed = WorkCalendarRules(
        friday: FridayWork.full,
        skipCholHamoed: false,
        skipErevYomTov: false,
        skipFasts: false,
        skipErevTishaBeav: false,
        skipBetweenYomKippurAndSukkot: false,
        skipWeekBeforePesach: false,
        skipPurim: false,
        skipChanukah: false,
      );
      for (final y in [5785, 5786, 5787]) {
        expect(day(y, JewishDate.NISSAN, 15, everythingAllowed).reason,
            NonWorkReason.yomTov,
            reason: 'first day of Pesach $y');
        expect(day(y, JewishDate.TISHREI, 1, everythingAllowed).reason,
            NonWorkReason.yomTov,
            reason: 'Rosh Hashana $y');
        expect(day(y, JewishDate.TISHREI, 10, everythingAllowed).reason,
            NonWorkReason.yomTov,
            reason: 'Yom Kippur $y');
        expect(day(y, JewishDate.SIVAN, 6, everythingAllowed).reason,
            NonWorkReason.yomTov,
            reason: 'Shavuot $y');
      }
    });

    test('Tisha BeAv is off even when fasts are allowed', () {
      const fastsAllowed = WorkCalendarRules(skipFasts: false);
      for (final y in [5785, 5786, 5787, 5788]) {
        // 9 Av unless it fell on Shabbat, in which case the fast is the 10th.
        final ninth = day(y, JewishDate.AV, 9, fastsAllowed);
        final tenth = day(y, JewishDate.AV, 10, fastsAllowed);
        expect(
          ninth.reason == NonWorkReason.tishaBeav ||
              (ninth.reason == NonWorkReason.shabbat &&
                  tenth.reason == NonWorkReason.tishaBeav),
          isTrue,
          reason: 'Tisha BeAv $y was $ninth / $tenth',
        );
      }
    });

    test('the eve of Tisha BeAv moves with the fast', () {
      for (var y = 5780; y <= 5800; y++) {
        // Find the day the fast is actually kept, then check the day before it.
        var observed = 0;
        for (var d = 9; d <= 10; d++) {
          if (day(y, JewishDate.AV, d).reason == NonWorkReason.tishaBeav) {
            observed = d;
            break;
          }
        }
        expect(observed, isNot(0), reason: 'no Tisha BeAv found in $y');

        final before = day(y, JewishDate.AV, observed - 1);
        expect(
          before.reason,
          anyOf(NonWorkReason.erevTishaBeav, NonWorkReason.shabbat),
          reason: 'day before Tisha BeAv $y',
        );
      }
    });

    test('Chol HaMoed starts a day earlier in Israel', () {
      const israel = WorkCalendarRules(inIsrael: true);
      const diaspora = WorkCalendarRules(inIsrael: false);

      expect(day(5786, JewishDate.NISSAN, 16, israel).reason,
          NonWorkReason.cholHamoed);
      expect(day(5786, JewishDate.NISSAN, 16, diaspora).reason,
          NonWorkReason.yomTov);
    });

    test('the four days between Yom Kippur and Sukkot are off', () {
      for (var d = 11; d <= 14; d++) {
        final classified = day(5786, JewishDate.TISHREI, d);
        expect(classified.isOff, isTrue, reason: '$d Tishrei');
      }
      // 14 Tishrei is Erev Sukkot and should be named as such.
      expect(day(5786, JewishDate.TISHREI, 14).reason, NonWorkReason.erevYomTov);
    });

    test('the week before Pesach is off', () {
      for (var d = 8; d <= 14; d++) {
        expect(day(5786, JewishDate.NISSAN, d).isOff, isTrue,
            reason: '$d Nisan');
      }
      // 7 Nisan is an ordinary day, unless it happens to be Shabbat.
      final seventh = day(5786, JewishDate.NISSAN, 7);
      expect(seventh.reason, isNot(NonWorkReason.weekBeforePesach));
    });

    test('minor fasts are off, and can be turned back on', () {
      // 10 Tevet never moves, so it is the safest fast to assert on.
      expect(day(5786, JewishDate.TEVES, 10).reason, NonWorkReason.fast);
      expect(
          day(5786, JewishDate.TEVES, 10,
                  const WorkCalendarRules(skipFasts: false))
              .isOff,
          isFalse);
    });

    test('Purim is in Adar II in a leap year', () {
      // 5787 is a leap year: 14 Adar I is Purim Katan, 14 Adar II is Purim.
      final jc = JewishCalendar.initDate(5787, JewishDate.ADAR, 14);
      expect(jc.isJewishLeapYear(), isTrue);

      expect(day(5787, JewishDate.ADAR_II, 14).reason, NonWorkReason.purim);
      // Purim Katan is only off when minor days are switched on.
      expect(day(5787, JewishDate.ADAR, 14).reason, isNot(NonWorkReason.purim));
      expect(
          day(5787, JewishDate.ADAR, 14,
                  const WorkCalendarRules(skipMinorHolidays: true))
              .reason,
          NonWorkReason.minorHoliday);
    });

    test('Chanukah can be worked or not, as configured', () {
      expect(day(5786, JewishDate.KISLEV, 25).reason, NonWorkReason.chanukah);
      expect(
          day(5786, JewishDate.KISLEV, 25,
                  const WorkCalendarRules(skipChanukah: false))
              .isOff,
          isFalse);
    });

    test('Friday is worth none, half or a full day as set', () {
      // 20 Iyar 5786 — an ordinary stretch with no festival in it.
      for (var d = 15; d <= 28; d++) {
        final jc = JewishCalendar.initDate(5786, JewishDate.IYAR, d);
        if (jc.getDayOfWeek() != JewishDate.friday) continue;

        expect(day(5786, JewishDate.IYAR, d).value, 0);
        expect(
            day(5786, JewishDate.IYAR, d,
                    const WorkCalendarRules(friday: FridayWork.half))
                .value,
            0.5);
        expect(
            day(5786, JewishDate.IYAR, d,
                    const WorkCalendarRules(friday: FridayWork.full))
                .value,
            1);
        return;
      }
      fail('no Friday found in the sample range');
    });

    test('Isru Chag is a day later outside Israel', () {
      const israel = WorkCalendarRules(inIsrael: true, skipMinorHolidays: true);
      const diaspora =
          WorkCalendarRules(inIsrael: false, skipMinorHolidays: true);

      expect(day(5786, JewishDate.NISSAN, 22, israel).reason,
          NonWorkReason.minorHoliday);
      // 22 Nisan is still Yom Tov abroad; Isru Chag is the 23rd.
      expect(day(5786, JewishDate.NISSAN, 22, diaspora).reason,
          NonWorkReason.yomTov);
      expect(day(5786, JewishDate.NISSAN, 23, diaspora).reason,
          NonWorkReason.minorHoliday);
    });
  });

  group('HebrewWorkCalendar — counting and planning', () {
    test('an ordinary week has six working days without the Friday rule', () {
      // 15–21 Iyar 5786: seven consecutive days with no festival in them.
      final from = JewishCalendar.initDate(5786, JewishDate.IYAR, 15)
          .getGregorianCalendar();
      final to = JewishCalendar.initDate(5786, JewishDate.IYAR, 21)
          .getGregorianCalendar();

      expect(HebrewWorkCalendar.countWorkDays(from, to, shabbatOnly), 6);
      // With Friday off as well, five.
      expect(
          HebrewWorkCalendar.countWorkDays(
              from, to, const WorkCalendarRules(skipChanukah: false)),
          5);
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
      expect(plan.skipped.keys, contains(NonWorkReason.weekBeforePesach));
      expect(plan.skipped.keys, contains(NonWorkReason.yomTov));
    });

    test('half days accumulate without drifting a day', () {
      // Fridays and Saturday nights each worth half: two of them make one day.
      const halves = WorkCalendarRules(
        friday: FridayWork.half,
        motzeiShabbatHalfDay: true,
        skipCholHamoed: false,
        skipErevYomTov: false,
        skipFasts: false,
        skipErevTishaBeav: false,
        skipBetweenYomKippurAndSukkot: false,
        skipWeekBeforePesach: false,
        skipPurim: false,
        skipChanukah: false,
      );
      final start = JewishCalendar.initDate(5786, JewishDate.IYAR, 15)
          .getGregorianCalendar();
      final plan =
          HebrewWorkCalendar.plan(from: start, workDaysNeeded: 7, rules: halves)!;

      // The plan must be the *earliest* day the work is done: seven days of
      // writing fit into it, and not into a day less.
      expect(HebrewWorkCalendar.countWorkDays(start, plan.completionDate, halves),
          greaterThanOrEqualTo(7));
      expect(
          HebrewWorkCalendar.countWorkDays(
              start,
              plan.completionDate.subtract(const Duration(days: 1)),
              halves),
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

    test('rules survive a round trip through storage', () {
      const original = WorkCalendarRules(
        inIsrael: false,
        friday: FridayWork.half,
        motzeiShabbatHalfDay: true,
        skipChanukah: false,
        skipRoshChodesh: true,
      );
      final restored = WorkCalendarRules.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>);

      expect(restored.inIsrael, isFalse);
      expect(restored.friday, FridayWork.half);
      expect(restored.motzeiShabbatHalfDay, isTrue);
      expect(restored.skipChanukah, isFalse);
      expect(restored.skipRoshChodesh, isTrue);
      // Anything missing from an older file falls back to the default.
      expect(WorkCalendarRules.fromJson(const {}).friday, FridayWork.none);
      expect(WorkCalendarRules.fromJson(const {}).skipCholHamoed, isTrue);
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
      // 4 May to 9 May inclusive is five working days with only Shabbat off.
      expect(
        CompletionEstimator.paceRequiredFor(
          remainingUnits: 10,
          deadline: DateTime(2026, 5, 9),
          rules: shabbatOnly,
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
}
