import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/project_analytics.dart';
import 'package:sofer_vmone/logic/profit_calculator.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/models.dart';

Project project(String id, ProjectType type) => Project(
      id: id,
      name: id,
      type: type,
      price: 1000,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0,
      totalPages: type == ProjectType.megillah ? 20 : null,
      linesPerPage: type == ProjectType.megillah ? 21 : null,
      megillahFormat: type == ProjectType.megillah ? 'lines21' : null,
    );

WorkSession timed(String id, String projectId, {int endLine = 42}) {
  final start = DateTime(2026, 8, 25, 9);
  return WorkSession(
    id: id,
    projectId: projectId,
    startTime: start,
    endTime: start.add(const Duration(hours: 1)),
    amount: 1,
    startLine: 1,
    endLine: endLine,
    description: '',
    isManual: false,
  );
}

void main() {
  test('the agreed cross-type line weights are explicit and stable', () {
    expect(ProductionCalculator.comparableLinesPerUnit(ProjectType.sefer), 42);
    expect(
      ProductionCalculator.comparableLinesPerUnit(ProjectType.mezuza),
      closeTo(22 * 1.1, 0.0001),
    );
    expect(
      ProductionCalculator.comparableLinesPerUnit(ProjectType.tefillin),
      closeTo(104 * 1.3, 0.0001),
    );
    expect(
      ProductionCalculator.comparableLinesPerUnit(
        ProjectType.megillah,
        megillahFormat: 'lines11',
      ),
      38 * 11,
    );
  });

  test('a missing type uses the requested fallback order', () {
    final sefer = project('sefer', ProjectType.sefer);
    final history = [timed('s', sefer.id)];

    // Mezuza has no data, so it falls back to Tefillin, then Sefer. Here the
    // first available source is Sefer: one hour / 42 weighted lines.
    final pace = ProjectAnalytics.typicalTimePerComparableLine(
      ProjectType.mezuza,
      [sefer],
      history,
    );
    expect(pace, const Duration(minutes: 1, seconds: 26));
  });

  test('Megillah time and pricing use deliberately different axes', () {
    final eleven = project('m11', ProjectType.megillah).copyWith(
      price: 6000,
      expenses: 1800,
      totalPages: 38,
      linesPerPage: 11,
    );
    final twentyEight = eleven.copyWith(
      totalPages: 16,
      linesPerPage: 28,
    );
    // Time sees the physical layouts, while the price axis always sees ten
    // standard Sefer pages (420 lines), in both directions of the conversion.
    expect(
      ProductionCalculator.comparableLinesPerUnit(
        ProjectType.megillah,
        megillahFormat: 'lines11',
      ),
      418,
    );
    expect(
      ProductionCalculator.comparableLinesPerUnit(
        ProjectType.megillah,
        megillahFormat: 'lines28',
      ),
      448,
    );
    expect(ProfitCalculator.netPerComparableLine(eleven), closeTo(10, 0.0001));
    expect(ProfitCalculator.netPerComparableLine(twentyEight),
        closeTo(10, 0.0001));
  });
}
