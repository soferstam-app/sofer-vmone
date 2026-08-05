// A year's income and costs, for the writer's accountant.
//
// Every figure existed somewhere already; nothing had gathered them into the
// shape a self-employed sofer is asked for once a year. The one thing here that
// is not like the rest of the app: it counts in Gregorian months. A tax year is
// January to December, set by an authority that does not care how the writer
// counts his days, and reporting Tishrei to Elul would be handing them a year
// that does not exist.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/annual_report.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const dayStart = DayStart.midnight;
  const usd = Currency('USD');
  var seq = 0;

  Project project({
    String id = 'p',
    double price = 100,
    double perUnitCost = 0,
    Currency? currency,
    bool deleted = false,
  }) =>
      Project(
        id: id,
        name: 'ספר',
        type: ProjectType.sefer,
        price: price,
        expenses: perUnitCost,
        currency: currency ?? Currency.ils,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: 10,
        deletedAt: deleted ? DateTime(2026) : null,
      );

  /// One full page written on [day].
  WorkSession page(DateTime day, {String projectId = 'p', bool backlog = false}) =>
      WorkSession(
        id: 'w${seq++}',
        projectId: projectId,
        startTime: DateTime(day.year, day.month, day.day, 9),
        endTime: DateTime(day.year, day.month, day.day, 12),
        amount: 1,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
        backlogOnly: backlog,
        linesPerPageAtEntry: 10,
      );

  Expense expense(DateTime date, double amount, {Currency? currency}) => Expense(
        id: 'e${seq++}',
        product: 'קלף',
        date: date,
        amount: amount,
        currency: currency ?? Currency.ils,
        allocation: ExpenseAllocation.month,
      );

  AnnualReport report({
    List<Project>? projects,
    List<WorkSession> history = const [],
    List<Expense> expenses = const [],
    int year = 2026,
  }) =>
      AnnualReport.forYear(
        year: year,
        projects: projects ?? [project()],
        history: history,
        expenses: expenses,
        dayStart: dayStart,
      );

  group('the shape of a tax year', () {
    test('is twelve Gregorian months, always', () {
      final r = report();
      expect(r.months, hasLength(12));
      expect(r.months.first.month, 1);
      expect(r.months.last.month, 12);
      expect(r.months.first.name, 'ינואר');
    });

    test('work lands in the Gregorian month it was written in', () {
      final r = report(history: [page(DateTime(2026, 3, 15))]);
      expect(r.months[2].income.single(Currency.ils)!.amount, 100);
      expect(r.months[1].income.isEmpty, isTrue);
    });

    test('and follows the working day, not the clock', () {
      // Half past midnight on 1 April, counted by a writer whose day turns
      // over at two: it is March's income, and March is what he will be asked
      // about.
      final late = WorkSession(
        id: 'late',
        projectId: 'p',
        startTime: DateTime(2026, 4, 1, 0, 30),
        endTime: DateTime(2026, 4, 1, 1, 30),
        amount: 1,
        startLine: 1,
        endLine: 10,
        description: '',
        isManual: true,
        linesPerPageAtEntry: 10,
        dayRule: const DayStart(boundary: DayBoundary.fixedHour, hour: 2),
      );
      final r = report(history: [late]);
      expect(r.months[2].income.single(Currency.ils)!.amount, 100);
    });

    test('another year is not this one', () {
      final r = report(history: [page(DateTime(2025, 3, 15))]);
      expect(r.income.single(Currency.ils)!.amount, 0);
    });
  });

  group('what is counted as income', () {
    test('the price of what was written, not the profit on it', () {
      // Income and the cost of materials are reported apart, because that is
      // how they are asked for. Profit is the subtraction, not the entry.
      final r = report(
        projects: [project(price: 100, perUnitCost: 30)],
        history: [page(DateTime(2026, 5, 4))],
      );
      expect(r.income.single(Currency.ils)!.amount, 100);
      expect(r.expenses.single(Currency.ils)!.amount, 30);
      expect(r.net(Currency.ils)!.amount, 70);
    });

    test('backlog work is not income', () {
      // It records writing done before the app existed, and was not paid for
      // in this year. Counting it would invent income out of a placeholder.
      final r = report(history: [page(DateTime(2026, 5, 4), backlog: true)]);
      expect(r.income.single(Currency.ils)!.amount, 0);
    });

    test('a deleted commission is not counted', () {
      final r = report(
        projects: [project(deleted: true)],
        history: [page(DateTime(2026, 5, 4))],
      );
      expect(r.income.single(Currency.ils)!.amount, 0);
    });
  });

  group('what is counted as a cost', () {
    test('recorded expenses land in their own month', () {
      final r = report(expenses: [expense(DateTime(2026, 7, 2), 250)]);
      expect(r.months[6].expenses.single(Currency.ils)!.amount, 250);
      expect(r.expenses.single(Currency.ils)!.amount, 250);
    });

    test('per-unit materials and recorded expenses add up together', () {
      final r = report(
        projects: [project(price: 100, perUnitCost: 30)],
        history: [page(DateTime(2026, 7, 4))],
        expenses: [expense(DateTime(2026, 7, 2), 250)],
      );
      expect(r.months[6].expenses.single(Currency.ils)!.amount, 280);
    });
  });

  group('a year in more than one currency', () {
    test('has no single net, and says which currencies it holds', () {
      final r = report(
        projects: [project(), project(id: 'q', currency: usd)],
        history: [page(DateTime(2026, 5, 4)), page(DateTime(2026, 5, 4), projectId: 'q')],
      );
      expect(r.currenciesPresent, containsAll([Currency.ils, usd]));
      expect(r.net(Currency.ils), isNull,
          reason: 'shekels and dollars do not make a number');
      expect(r.income.isMixed, isTrue);
    });

    test('an ordinary year holds exactly one', () {
      final r = report(history: [page(DateTime(2026, 5, 4))]);
      expect(r.currenciesPresent, {Currency.ils});
      expect(r.net(Currency.ils), isNotNull);
    });
  });

  group('an empty year', () {
    test('reports zero rather than nothing', () {
      // A year with no work is a fact worth stating; it is what a writer takes
      // to an accountant to say so.
      final r = report();
      expect(r.income.single(Currency.ils)!.amount, 0);
      expect(r.net(Currency.ils)!.amount, 0);
      expect(r.months.every((m) => m.isEmpty), isTrue);
    });
  });
}
