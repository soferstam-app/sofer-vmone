import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/measured_work.dart';
import 'package:sofer_vmone/logic/partial_line_recording.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/smart_session.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  Project project(ProjectType type) => Project(
        id: type.name,
        name: type.name,
        type: type,
        price: 100,
        expenses: 0,
        targetDaily: 0,
        targetMonthly: 0,
        linesPerPage: type.isPaged ? 42 : null,
        totalPages: type.isPaged ? 245 : null,
      );

  final endedAt = DateTime(2026, 9, 2, 18);

  test('a partial line round-trips as time but never as output', () {
    final sefer = project(ProjectType.sefer);
    final partial = PartialLineRecording.create(
      project: sefer,
      position: const SmartPosition(7, 12),
      worked: const Duration(minutes: 9),
      endedAt: endedAt,
    );

    final revived = WorkSession.fromJson(partial.toJson());
    expect(revived.isPartialLine, isTrue);
    expect(revived.partialLineCompleted, isFalse);
    expect(revived.partialPositionPage, 7);
    expect(revived.partialPositionLine, 12);
    expect(MeasuredWork.time([revived]), const Duration(minutes: 9));
    expect(ProductionCalculator.seferLinesInSession(revived), 0);
    expect(
        ProductionCalculator.seferLinesInSession(revived, includeInvalid: true),
        0);
  });

  test('unfinished visits accumulate and resolving keeps their dated time', () {
    final sefer = project(ProjectType.sefer);
    final first = PartialLineRecording.create(
      project: sefer,
      position: const SmartPosition(7, 12),
      worked: const Duration(minutes: 9),
      endedAt: endedAt,
    );
    final second = PartialLineRecording.create(
      project: sefer,
      position: const SmartPosition(7, 12),
      worked: const Duration(minutes: 6),
      endedAt: endedAt.add(const Duration(days: 1)),
    );
    final anotherLine = PartialLineRecording.create(
      project: sefer,
      position: const SmartPosition(7, 13),
      worked: const Duration(minutes: 4),
      endedAt: endedAt,
    );
    final history = [first, second, anotherLine];

    expect(
      PartialLineRecording.carriedTime(
          history, sefer, const SmartPosition(7, 12)),
      const Duration(minutes: 15),
    );

    final resolved = PartialLineRecording.resolve(
        history, sefer, const SmartPosition(7, 12));
    expect(
      PartialLineRecording.carriedTime(
          resolved, sefer, const SmartPosition(7, 12)),
      Duration.zero,
    );
    expect(MeasuredWork.time(resolved), const Duration(minutes: 19));
    expect(resolved.where((s) => s.partialLineCompleted), hasLength(2));
  });

  test('the completed line has its true time without counting output twice',
      () {
    final sefer = project(ProjectType.sefer);
    final partial = PartialLineRecording.create(
      project: sefer,
      position: const SmartPosition(7, 12),
      worked: const Duration(minutes: 9),
      endedAt: endedAt,
    ).copyWith(partialLineCompleted: true);
    final completion = WorkSession(
      id: 'completion',
      projectId: sefer.id,
      startTime: endedAt.add(const Duration(days: 1)),
      endTime: endedAt.add(const Duration(days: 1, minutes: 6)),
      amount: 7,
      startLine: 12,
      endLine: 12,
      description: 'line 12',
      isManual: false,
    );

    expect(ProductionCalculator.seferLinesTotal([partial, completion]), 1);
    expect(
        MeasuredWork.time([partial, completion]), const Duration(minutes: 15));
  });

  test('partial geometry is zero output for every project type', () {
    final seferPartial = PartialLineRecording.create(
      project: project(ProjectType.sefer),
      position: const SmartPosition(2, 3),
      worked: const Duration(minutes: 2),
      endedAt: endedAt,
    );
    final mezuzaPartial = PartialLineRecording.create(
      project: project(ProjectType.mezuza),
      position: const SmartPosition(4, 16),
      worked: const Duration(minutes: 2),
      endedAt: endedAt,
    );
    final tefillinPartial = PartialLineRecording.create(
      project: project(ProjectType.tefillin),
      position: const SmartPosition(1, 2),
      worked: const Duration(minutes: 2),
      endedAt: endedAt,
    );

    expect(ProductionCalculator.seferLinesInSession(seferPartial), 0);
    expect(ProductionCalculator.mezuzaLinesInSession(mezuzaPartial), 0);
    expect(ProductionCalculator.tefillinPhysicalLinesInSession(tefillinPartial),
        0);
    expect(ProductionCalculator.tefillinSeferLines(tefillinPartial), 0);
  });
}
