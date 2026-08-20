// Gathering loose parshiyot back into the wholes they make.
//
// A sofer records tefillin at whatever grain he is working at, and the summary
// has to say it back the way he would: not "קדש של ראש, והיה כי יביאך של ראש,
// שמע של ראש, והיה אם שמע של ראש" but "תפילין של ראש". The arithmetic that
// does it sat in a summary screen where nothing could reach it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/tefillin_summary.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  var seq = 0;

  WorkSession session({
    int amount = 1,
    String? type,
    int? parshiya,
    int startLine = 0,
    int endLine = 0,
    int? pair,
  }) =>
      WorkSession(
        id: 'w${seq++}',
        projectId: 'p',
        startTime: DateTime(2026, 7, 20, 9),
        endTime: DateTime(2026, 7, 20, 10),
        amount: amount,
        startLine: startLine,
        endLine: endLine,
        tefillinType: type,
        parshiya: parshiya,
        pairIndex: pair,
        description: '',
        isManual: true,
      );

  /// The four parshiyot of one side, each written whole.
  List<WorkSession> allFour(String type) =>
      [for (var p = 1; p <= 4; p++) session(type: type, parshiya: p)];

  String describe(Iterable<WorkSession> sessions) =>
      TefillinSummary.describe(sessions);

  group('what was recorded whole is said whole', () {
    test('a pair', () {
      expect(describe([session()]), 'זוג תפילין אחד');
    });

    test('several pairs take the numeral', () {
      expect(describe([session(amount: 3)]), '3 זוגות תפילין');
    });

    test('a head on its own', () {
      expect(describe([session(type: 'head', amount: 2)]), '2 תפילין של ראש');
    });

    test('a hand on its own', () {
      expect(describe([session(type: 'hand')]), '1 תפילין של יד');
    });
  });

  group('loose parshiyot are gathered up', () {
    test('four of the head make a head', () {
      expect(describe(allFour('head')), '1 תפילין של ראש');
    });

    test('four and four make a pair, not two halves', () {
      // The point of the gathering: a writer who worked parshiya by parshiya
      // across both sides has finished a pair, and should be told so.
      expect(
          describe([...allFour('head'), ...allFour('hand')]), 'זוג תפילין אחד');
    });

    test('what is left over is named on its own', () {
      expect(
        describe([...allFour('head'), session(type: 'hand', parshiya: 3)]),
        '1 תפילין של ראש, פרשיית שמע של יד',
      );
    });

    test('and pluralised when there is more than one of it', () {
      expect(describe([session(type: 'head', parshiya: 1, amount: 2)]),
          '2 פרשיות קדש של ראש');
    });

    test('pairs are taken out before heads and hands', () {
      // Two heads and one hand is one pair plus a spare head — never "two heads
      // and one hand", which is the same tefillin described as parts.
      expect(
        describe([session(type: 'head', amount: 2), session(type: 'hand')]),
        'זוג תפילין אחד, 1 תפילין של ראש',
      );
    });
  });

  group('a parshiya left part-written', () {
    test('is named with the line it reached, not counted as done', () {
      // A head parshiya is four lines; three is not one.
      expect(describe([session(type: 'head', parshiya: 3, endLine: 3)]),
          'שמע של ראש (עד שורה 3)');
    });

    test('counts as done once it reaches the last line', () {
      expect(describe([session(type: 'head', parshiya: 3, endLine: 4)]),
          'פרשיית שמע של ראש');
    });

    test('the hand is measured against seven lines, not four', () {
      // The two are different lengths, and using one threshold for both would
      // call a hand parshiya finished less than halfway through it.
      expect(describe([session(type: 'hand', parshiya: 1, endLine: 4)]),
          'קדש של יד (עד שורה 4)');
      expect(describe([session(type: 'hand', parshiya: 1, endLine: 7)]),
          'פרשיית קדש של יד');
    });

    test('no line at all means finished', () {
      // The entry form leaves it empty for a parshiya written through.
      expect(describe([session(type: 'head', parshiya: 1, endLine: 0)]),
          'פרשיית קדש של ראש');
    });

    test('is listed after everything that was finished', () {
      final summary = describe([
        session(amount: 2),
        session(type: 'hand', parshiya: 2, endLine: 3),
      ]);
      expect(summary, startsWith('2 זוגות תפילין'));
      expect(summary, endsWith('(עד שורה 3)'));
    });

    test('two smart-mode stretches are one completed parshiya', () {
      final summary = describe([
        session(type: 'head', parshiya: 1, pair: 1, startLine: 1, endLine: 2),
        session(
            amount: 0,
            type: 'head',
            parshiya: 1,
            pair: 1,
            startLine: 3,
            endLine: 4),
      ]);

      expect(summary, 'פרשיית קדש של ראש');
    });
  });

  group('nothing to say', () {
    test('an empty month says so rather than saying zero', () {
      expect(describe(const []), 'לא נרשמה כתיבה משמעותית');
    });
  });

  group('the parshiyot are named in order', () {
    test('one to four', () {
      expect(TefillinSummary.parshiyaName(1), 'קדש');
      expect(TefillinSummary.parshiyaName(2), 'והיה כי יביאך');
      expect(TefillinSummary.parshiyaName(3), 'שמע');
      expect(TefillinSummary.parshiyaName(4), 'והיה אם שמע');
    });

    test('and nothing else is one', () {
      // Counting starts at one here as everywhere: there is no parshiya zero.
      expect(TefillinSummary.parshiyaName(0), '');
      expect(TefillinSummary.parshiyaName(5), '');
    });
  });
}
