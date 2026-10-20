import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/measured_work.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/profit_calculator.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  WorkSession session({bool invalid = false, bool deleted = false}) {
    final start = DateTime(2026, 8, 23, 9);
    return WorkSession(
      id: 's',
      projectId: 'p',
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      amount: 12,
      startLine: 1,
      endLine: 10,
      description: 'עמוד יב',
      isManual: true,
      isInvalid: invalid,
      deletedAt: deleted ? DateTime(2026, 8, 23, 12) : null,
    );
  }

  test('invalid work keeps its measured time but contributes no output', () {
    final invalid = session(invalid: true);

    expect(ProductionCalculator.seferLinesInSession(invalid), 0);
    expect(ProductionCalculator.seferLinesInSession(invalid, includeInvalid: true), 10);
    expect(MeasuredWork.time([invalid]), const Duration(hours: 1));
    expect(MeasuredWork.invalidTime([invalid]), const Duration(hours: 1));
    expect(MeasuredWork.validOnly([invalid]), isEmpty);
  });

  test('invalid state survives storage and can be cleared', () {
    final invalid = session(invalid: true);
    final restored = WorkSession.fromJson(invalid.toJson());

    expect(restored.isInvalid, isTrue);
    expect(restored.copyWith(isInvalid: false).isInvalid, isFalse);
  });

  test('a deleted record contributes neither output nor invalid time', () {
    final deleted = session(invalid: true, deleted: true);

    expect(ProductionCalculator.seferLinesInSession(deleted), 0);
    expect(MeasuredWork.invalidTime([deleted]), Duration.zero);
  });

  test('invalid work produces no billable units in every project type', () {
    Project project(ProjectType type) => Project(
          id: 'p',
          name: 'test',
          type: type,
          price: 100,
          expenses: 10,
          targetDaily: 1,
          targetMonthly: 20,
          linesPerPage: 42,
        );

    final invalid = session(invalid: true);
    for (final type in ProjectType.values) {
      expect(ProfitCalculator.billableUnits(project(type), [invalid]), 0,
          reason: type.name);
      expect(ProfitCalculator.profit(project(type), [invalid]), 0,
          reason: type.name);
    }
  });
}
