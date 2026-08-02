// The one thing the app writes that leaves it.
//
// A progress update goes out over the sofer's name to his client. It was built
// inside a screen, so not a word of it could be checked, and a figure that came
// out wrong here would be read by someone who has no way of knowing.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/client_update.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Project project({
    ProjectType type = ProjectType.sefer,
    int? totalPages,
    int? linesPerPage = 42,
    DateTime? target,
  }) =>
      Project(
        id: 'p',
        name: 'ספר תורה למשפחת כהן',
        type: type,
        price: 100,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        totalPages: totalPages,
        linesPerPage: linesPerPage,
        targetCompletionDate: target,
      );

  String compose({
    Project? p,
    String totalWritten = '30 עמודים',
    String estimatedEnd = 'כ״ה בטבת',
    int linesWritten = 0,
    String soferName = 'שאול',
  }) =>
      ClientUpdate.compose(
        project: p ?? project(),
        totalWritten: totalWritten,
        estimatedEnd: estimatedEnd,
        linesWritten: linesWritten,
        soferName: soferName,
        today: DateTime(2026, 7, 20),
        formatDate: (d) => '${d.day}/${d.month}/${d.year}',
      );

  group('what the client is told', () {
    test('opens properly and names the commission', () {
      final body = compose();
      expect(body, startsWith('בס"ד'));
      expect(body, contains('ספר תורה למשפחת כהן'));
      expect(body, contains('20/7/2026'));
    });

    test('what has been written', () {
      expect(compose(totalWritten: '30 עמודים ו-5 שורות'),
          contains('• נכתב עד כה: 30 עמודים ו-5 שורות'));
    });

    test('and when it is expected to land', () {
      expect(compose(estimatedEnd: 'כ״ה בטבת'),
          contains('• צפי סיום משוער: כ״ה בטבת'));
    });

    test('is signed', () {
      expect(compose(soferName: 'שאול'), endsWith('שאול'));
    });
  });

  group('a percentage needs something to be a fraction of', () {
    test('given the length of the sefer, it is quoted', () {
      final body = compose(
        p: project(totalPages: 100, linesPerPage: 10),
        linesWritten: 250,
      );
      expect(body, contains('(מתוך 100 עמודים)'));
      expect(body, contains('• התקדמות: 25%'));
    });

    test('without it, no percentage is invented', () {
      // The denominator would have to be made up, and the client would read it
      // as a fact about their sefer.
      final body = compose(p: project(totalPages: null), linesWritten: 250);
      expect(body, isNot(contains('• התקדמות:')));
      expect(body, isNot(contains('מתוך')));
    });

    test('nor for work that is counted rather than paginated', () {
      final body = compose(
          p: project(type: ProjectType.mezuza), linesWritten: 100);
      expect(body, isNot(contains('• התקדמות:')));
      expect(body, contains('• נכתב עד כה:'));
    });

    test('and it never exceeds a whole', () {
      // A sefer written past its stated length — a page range entered twice,
      // or a length corrected downwards — must not be reported at 130%.
      final body = compose(
        p: project(totalPages: 10, linesPerPage: 10),
        linesWritten: 130,
      );
      expect(body, contains('• התקדמות: 100%'));
    });
  });

  group('what is left out rather than sent empty', () {
    test('an estimate the app could not compute', () {
      expect(compose(estimatedEnd: ''), isNot(contains('צפי סיום')));
    });

    test('a deadline that was never agreed', () {
      expect(compose(), isNot(contains('תאריך יעד')));
    });

    test('a deadline that was appears', () {
      expect(compose(p: project(target: DateTime(2027, 3, 1))),
          contains('• תאריך יעד מוסכם: 1/3/2027'));
    });

    test('an unset name, rather than a blank line where it should be', () {
      final body = compose(soferName: '');
      expect(body, endsWith('בברכה,'));
      expect(body, isNot(endsWith('\n')));
    });
  });
}
