import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/entry_builder.dart';
import 'package:sofer_vmone/logic/megillah_format.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/profit_calculator.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Project megillah(String format,
      {double price = 1000, double expenses = 100}) {
    return Project(
      id: 'm',
      name: 'מגילה',
      type: ProjectType.megillah,
      price: price,
      expenses: expenses,
      targetDaily: 1,
      targetMonthly: 10,
      totalPages: MegillahFormat.totalPages(format),
      linesPerPage: MegillahFormat.storedLinesPerPage(format),
      megillahFormat: format,
    );
  }

  WorkSession page(Project project, int number) => WorkSession(
        id: 's$number',
        projectId: project.id,
        startTime: DateTime(2026, 8, 25, 9),
        endTime: DateTime(2026, 8, 25, 10),
        amount: number,
        startLine: 1,
        endLine: project.linesPerPage!,
        linesPerPageAtEntry: project.linesPerPage,
        description: 'עמוד $number',
        isManual: true,
      );

  test('the four layouts have their requested fixed geometry', () {
    expect(MegillahFormat.totalPages(MegillahFormat.lines11), 38);
    expect(MegillahFormat.totalPages(MegillahFormat.lines21), 20);
    expect(MegillahFormat.totalPages(MegillahFormat.lines28), 16);
    expect(MegillahFormat.totalPages(MegillahFormat.satire14_5), 399);
    expect(MegillahFormat.displayLines(MegillahFormat.satire14_5), '14.5');
    expect(MegillahFormat.storedLinesPerPage(MegillahFormat.satire14_5), 15);
  });

  test('the format marker survives JSON independently of geometry', () {
    final original = megillah(MegillahFormat.satire14_5);
    final json =
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
    final restored = Project.fromJson(json);

    expect(restored.type, ProjectType.megillah);
    expect(restored.megillahFormat, MegillahFormat.satire14_5);
    expect(MegillahFormat.isSatire(restored), isTrue);
  });

  test('manual Megillah entry uses the paged line-range path', () {
    final project = megillah(MegillahFormat.lines11);
    final outcome = EntryBuilder.build(
      input: EntryInput(
        project: project,
        start: DateTime(2026, 8, 25, 9),
        end: DateTime(2026, 8, 25, 10),
        isManual: true,
        pageFrom: '1',
        pageTo: '2',
        lineFrom: '6',
        lineTo: '5',
      ),
      history: const [],
    ) as EntryBuilt;

    expect(outcome.sessions, hasLength(2));
    expect(outcome.sessions.first.startLine, 6);
    expect(outcome.sessions.first.endLine, 11);
    expect(outcome.sessions.last.startLine, 1);
    expect(outcome.sessions.last.endLine, 5);
  });

  test('progress counts pages while money recognizes the whole-project price',
      () {
    final project = megillah(MegillahFormat.lines21);
    final written = [page(project, 1), page(project, 2)];

    expect(ProductionCalculator.projectUnits(project, written), 2);
    expect(
        ProfitCalculator.billableUnits(project, written), closeTo(0.1, 0.0001));
    expect(ProfitCalculator.profit(project, written), closeTo(90, 0.0001));
  });

  test('the 14.5 joke is isolated and counts backwards from 150 to 100', () {
    final joke = megillah(MegillahFormat.satire14_5);
    final ordinary = megillah(MegillahFormat.lines11);

    expect(MegillahFormat.displayedProgress(joke, 0), 0);
    expect(MegillahFormat.displayedProgress(joke, 0.1), closeTo(1.45, 0.0001));
    expect(MegillahFormat.displayedProgress(joke, 1), 1);
    expect(MegillahFormat.displayedProgress(ordinary, 0.1), 0.1);
  });
}
