// What a number of money is a number of.
//
// Every amount used to be a bare number with a shekel sign typed in beside it
// on screen. True and unambiguous while the shekel was the only possibility —
// and the moment it was not, every amount already stored would have been a
// figure with no unit, unrecoverable, because nothing anywhere said what it had
// meant.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const usd = Currency('USD');

  group('reading a stored currency', () {
    test('an amount from before this existed is shekels', () {
      // Not a guess. It is the only thing it could have been.
      expect(Currency.fromJson(null), Currency.ils);
      expect(Currency.fromJson(''), Currency.ils);
      expect(Currency.fromJson(42), Currency.ils);
    });

    test('a code this build has never heard of still survives', () {
      // A currency added by a later version must come back out of a round trip
      // exactly as it went in, or a backup that visits an older build loses it.
      final exotic = Currency.fromJson('XAU');
      expect(exotic.code, 'XAU');
      expect(Currency.fromJson(exotic.toJson()), exotic);
    });

    test('and prints as its code rather than as nothing', () {
      final exotic = Currency.fromJson('XAU');
      expect(exotic.symbol, 'XAU');
      expect(exotic.format(120), 'XAU 120',
          reason: 'a code run into a numeral is unreadable');
    });

    test('a known one prints as its sign, with no gap', () {
      expect(Currency.ils.format(120), '₪120');
      expect(usd.format(120), '\$120');
    });
  });

  group('the currency travels with the record', () {
    Project project({Currency? currency}) => Project(
          id: 'p',
          name: 'x',
          type: ProjectType.sefer,
          price: 100,
          expenses: 5,
          currency: currency ?? Currency.ils,
          targetDaily: 1,
          targetMonthly: 20,
        );

    Expense expense({Currency? currency}) => Expense(
          id: 'e',
          product: 'קלף',
          date: DateTime(2026, 7, 20),
          amount: 250,
          currency: currency ?? Currency.ils,
          allocation: ExpenseAllocation.month,
        );

    test('through a save and a load', () {
      final back = Project.fromJson(
          jsonDecode(jsonEncode(project(currency: usd).toJson()))
              as Map<String, dynamic>);
      expect(back.currency, usd);
    });

    test('an expense too', () {
      final back = Expense.fromJson(
          jsonDecode(jsonEncode(expense(currency: usd).toJson()))
              as Map<String, dynamic>);
      expect(back.currency, usd);
    });

    test('through an edit of something else', () {
      // The whole point: correcting a price does not restate what it is in.
      expect(project(currency: usd).copyWith(price: 200).currency, usd);
      expect(expense(currency: usd).copyWith(amount: 300).currency, usd);
    });

    test('through a delete and a restore', () {
      expect(
          expense(currency: usd)
              .withTombstone(deletedAt: DateTime(2026, 8))
              .currency,
          usd);
    });

    test('a record stored before the field existed reads as shekels', () {
      final old = Project.fromJson({
        'id': 'p1',
        'name': 'ספר',
        'typeName': 'sefer',
        'price': 100,
        'expenses': 0,
        'targetDaily': 1,
        'targetMonthly': 20,
      });
      expect(old.currency, Currency.ils);
      expect(old.price, 100, reason: 'the amount itself is untouched');
    });
  });

  group('adding money', () {
    test('within one currency is ordinary arithmetic', () {
      expect((Money(10, usd) + Money(5, usd)).amount, 15);
      expect((Money(10, usd) - Money(5, usd)).amount, 5);
      expect((Money(10, usd) * 3).amount, 30);
    });

    test('across two is refused', () {
      // Shekels and dollars do not make a number, and converting would need a
      // rate the app does not have and should not invent.
      expect(() => Money(10, usd) + Money(5, Currency.ils), throwsA(anything));
    });
  });

  group('a total that may span currencies', () {
    test('of one currency reads as an ordinary figure', () {
      final total = MoneyTotal.of([Money(10, usd), Money(5, usd)]);
      expect(total.isMixed, isFalse);
      expect(total.single(Currency.ils)!.amount, 15);
      expect(total.format(Currency.ils), '\$15');
    });

    test('of none is zero, not an absence', () {
      final total = MoneyTotal();
      expect(total.isEmpty, isTrue);
      expect(total.single(Currency.ils)!.amount, 0);
      expect(total.format(Currency.ils), '₪0');
    });

    test('of two has no single answer, and says so', () {
      final total =
          MoneyTotal.of([Money(10, usd), Money(400, Currency.ils)]);
      expect(total.isMixed, isTrue);
      expect(total.single(Currency.ils), isNull,
          reason: 'returning the larger part would be the lie this prevents');
    });

    test('and states every part rather than one of them', () {
      final total =
          MoneyTotal.of([Money(10, usd), Money(400, Currency.ils)]);
      final text = total.format(Currency.ils);
      expect(text, contains('\$10'));
      expect(text, contains('₪400'));
    });

    test('the largest part comes first, whichever sign it carries', () {
      final total =
          MoneyTotal.of([Money(10, usd), Money(400, Currency.ils)]);
      expect(total.parts.first.currency, Currency.ils);
    });

    test('nothing is lost when the same currency arrives twice', () {
      final total = MoneyTotal.of([
        Money(10, usd),
        Money(400, Currency.ils),
        Money(5, usd),
      ]);
      expect(total.parts, hasLength(2));
      expect(
          total.parts.firstWhere((m) => m.currency == usd).amount, 15);
    });
  });
}
