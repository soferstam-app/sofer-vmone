// What the entry form must refuse.
//
// The checks it had were written against an empty field — `== 0` for a quantity
// that was not typed, `== 0` for a page that did not parse. A minus sign walks
// straight past all of them, and on a desktop keyboard, or a paste, or a phone
// keyboard that offers one, it is a slip anyone can make.
//
// What made it worth finding is that nothing downstream objects either. A
// negative quantity is arithmetic like any other: it subtracts.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/entry_builder.dart';
import 'package:sofer_vmone/logic/profit_calculator.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Project project(ProjectType type, {int? totalPages = 245}) => Project(
        id: 'p1',
        name: 'עבודה',
        type: type,
        price: 100,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        totalPages: totalPages,
        linesPerPage: 42,
      );

  EntryOutcome build(
    Project p, {
    String pageFrom = '',
    String pageTo = '',
    String lineFrom = '',
    String lineTo = '',
    String amount = '',
    String partialLine = '',
  }) =>
      EntryBuilder.build(
        input: EntryInput(
          project: p,
          start: DateTime(2026, 5, 1, 9),
          end: DateTime(2026, 5, 1, 11),
          isManual: true,
          pageFrom: pageFrom,
          pageTo: pageTo,
          lineFrom: lineFrom,
          lineTo: lineTo,
          amount: amount,
          partialLine: partialLine,
        ),
        history: const [],
      );

  group('a quantity that is not a quantity', () {
    test('a negative count is refused', () {
      // It used to be built: five mezuzot entered as "-5" were recorded as
      // minus five, worth minus five hundred shekels, and the only sign of it
      // was the totals going down.
      expect(build(project(ProjectType.mezuza), amount: '-5'),
          isA<EntryRejected>());
    });

    test('an empty one still is too', () {
      expect(build(project(ProjectType.mezuza)), isA<EntryRejected>());
      expect(build(project(ProjectType.mezuza), amount: 'שלוש'),
          isA<EntryRejected>());
    });

    test('a real one is built, and is worth what it should be', () {
      final out = build(project(ProjectType.mezuza), amount: '5');
      expect(out, isA<EntryBuilt>());
      final built = out as EntryBuilt;
      expect(
          ProfitCalculator.billableUnits(
              project(ProjectType.mezuza), built.sessions),
          5.0);
    });

    test('the same for tefillin', () {
      expect(build(project(ProjectType.tefillin), amount: '-2'),
          isA<EntryRejected>());
    });
  });

  group('a page that is not a page', () {
    test('a negative page number is refused', () {
      // `formatHebrewNumber` has no numeral for one, so the record was filed
      // reading "עמוד  (1-10)" — a blank where its page should be.
      final out = build(project(ProjectType.sefer),
          pageFrom: '-3', lineFrom: '1', lineTo: '10');
      expect(out, isA<EntryRejected>());
    });

    test('page zero is refused', () {
      expect(
          build(project(ProjectType.sefer),
              pageFrom: '0', lineFrom: '1', lineTo: '10'),
          isA<EntryRejected>());
    });

    test('an ordinary page is built and named', () {
      final out = build(project(ProjectType.sefer),
          pageFrom: '3', lineFrom: '1', lineTo: '10');
      expect(out, isA<EntryBuilt>());
      final description = (out as EntryBuilt).sessions.first.description;
      expect(description, contains('('));
      expect(description, isNot(contains('עמוד  ')),
          reason: 'the page has no name');
    });

    test('a negative "up to page" is refused, not silently ignored', () {
      final out = build(project(ProjectType.sefer),
          pageFrom: '3', pageTo: '-9', lineFrom: '1', lineTo: '10');
      expect(out, isA<EntryRejected>());
    });
  });

  group('a range that is not a range', () {
    test('an unbounded commission does not accept a boundless one', () {
      // History is stored as one JSON string. A slip in "up to page" on a
      // commission with no stated page count built a record per page of it,
      // and a few hundred thousand of those is a file that cannot be written.
      final out = build(project(ProjectType.sefer, totalPages: null),
          pageFrom: '1', pageTo: '400000', lineFrom: '1', lineTo: '42');
      expect(out, isA<EntryRejected>());
    });

    test('a real range is still built', () {
      final out = build(project(ProjectType.sefer),
          pageFrom: '1', pageTo: '5', lineFrom: '1', lineTo: '42');
      expect(out, isA<EntryBuilt>());
      expect((out as EntryBuilt).sessions, hasLength(5));
    });

    test('a range beyond the stated page count is refused, as before', () {
      expect(
          build(project(ProjectType.sefer),
              pageFrom: '1', pageTo: '300', lineFrom: '1', lineTo: '42'),
          isA<EntryRejected>());
    });
  });

  group('a partial line that is not one', () {
    test('a negative mezuza line is refused', () {
      expect(build(project(ProjectType.mezuza), amount: '2', partialLine: '-4'),
          isA<EntryRejected>());
    });

    test('none given is not the same as a bad one', () {
      expect(
          build(project(ProjectType.mezuza), amount: '2'), isA<EntryBuilt>());
      expect(build(project(ProjectType.mezuza), amount: '2', partialLine: '10'),
          isA<EntryBuilt>());
    });
  });
}
