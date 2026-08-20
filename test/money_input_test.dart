// Reading a sum of money the way a person types one.
//
// The project form had two answers for the same text: the validator read
// `text.replaceAll(',', '.')` and the save read a bare `double.tryParse`. A
// sofer entering the price of a sefer torah the natural way — 40,000 — was told
// the form was fine and got a commission priced at zero, because the validator
// saw 40.0 and the save saw nothing. Every earning, hourly rate and quote for
// that job was zero from then on, and nothing on screen said why.
//
// Both readings were wrong even where they agreed: the comma in 40,000
// separates thousands, and turning it into a decimal point gives forty.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/money_input.dart';

void main() {
  group('what a sofer types', () {
    test('a price with a thousands separator is that price', () {
      // The case that was silently becoming zero.
      expect(MoneyInput.parse('40,000'), 40000);
      expect(MoneyInput.parse('1,500'), 1500);
      expect(MoneyInput.parse('1,234,567'), 1234567);
    });

    test('a plain number is itself', () {
      expect(MoneyInput.parse('40000'), 40000);
      expect(MoneyInput.parse('0'), 0);
      expect(MoneyInput.parse('180'), 180);
    });

    test('a full stop is the decimal point', () {
      expect(MoneyInput.parse('40.5'), 40.5);
      expect(MoneyInput.parse('0.07'), 0.07);
      expect(MoneyInput.parse('1,200.50'), 1200.50);
    });

    test('spaces, wherever they fell', () {
      expect(MoneyInput.parse('  40000  '), 40000);
      expect(MoneyInput.parse('40 000'), 40000);
    });
  });

  group('what it refuses', () {
    test('nothing at all', () {
      expect(MoneyInput.parse(''), isNull);
      expect(MoneyInput.parse('   '), isNull);
      expect(MoneyInput.parse(null), isNull);
    });

    test('text that is not a number', () {
      expect(MoneyInput.parse('ארבעים אלף'), isNull);
      expect(MoneyInput.parse('40x'), isNull);
      expect(MoneyInput.parse('₪40'), isNull);
    });

    test('a second decimal point, which is a typo and not a number', () {
      expect(MoneyInput.parse('40.0.5'), isNull);
    });

    test('separators with nothing between them', () {
      expect(MoneyInput.parse(','), isNull);
      expect(MoneyInput.parse('  ,  '), isNull);
    });
  });

  group('the promise that made it necessary', () {
    test('anything accepted parses to the same number on the way in', () {
      // The validator and the save call this one function, so a value the form
      // accepts is the value that gets stored. That is the whole point.
      for (final typed in [
        '40,000', '40000', '40.5', '1,200.50', '0', '  180  ', '40 000',
      ]) {
        final first = MoneyInput.parse(typed);
        expect(first, isNotNull, reason: '"$typed" was accepted');
        expect(MoneyInput.parse(typed), first);
      }
    });

    test('a comma never turns a large price into a small one', () {
      // The old validator read this as 40.0 and let it through.
      expect(MoneyInput.parse('40,000'), greaterThan(1000));
    });
  });
}
