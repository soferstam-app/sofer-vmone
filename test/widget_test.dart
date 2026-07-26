// Unit tests for the pure logic of the app.
//
// The previous file here was the default Flutter counter smoke test, which did
// not compile and tested nothing relevant to this project.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/hebrew_utils.dart';
import 'package:sofer_vmone/models.dart';

void main() {
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
}
