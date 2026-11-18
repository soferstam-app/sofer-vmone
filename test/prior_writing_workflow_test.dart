import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/entry/entry_sheet.dart';
import 'package:sofer_vmone/logic/completion_estimator.dart';
import 'package:sofer_vmone/logic/daily_goal.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/summary/history_editor.dart';

void main() {
  final project = Project(
      id: 'p',
      name: 'ספר',
      type: ProjectType.sefer,
      price: 0,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      totalPages: 245,
      linesPerPage: 42);
  final day = DateTime(2026, 11, 16);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.demoStore = MemoryStore({});
  });
  tearDown(() => StorageService.demoStore = null);

  testWidgets('manual entry marks 100 pages as progress without daily credit',
      (tester) async {
    List<WorkSession>? saved;
    tester.view.physicalSize = const Size(1200, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () => showEntrySheet(
                context: context,
                isManual: true,
                projects: [project],
                history: const [],
                initialProject: project,
                initialDate: day,
                useGregorianDates: true,
                dayStart: DayStart.midnight,
                onProjectCreated: (_) {},
                onSave: (result) async => saved = result.sessions,
              ),
          child: const Text('open')),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final (label, text) in [
      ('מעמוד', '1'),
      ('עד עמוד', '100'),
      ('משורה', '1'),
      ('עד שורה', '42')
    ]) {
      final target = find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == label);
      await tester.ensureVisible(target);
      await tester.enterText(target, text);
    }
    await tester.ensureVisible(find.text('כתיבה קודמת'));
    await tester.tap(find.text('כתיבה קודמת'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור וסגור'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(100));
    expect(saved!.every((record) => record.backlogOnly && !record.timeRecorded),
        isTrue);
    expect(CompletionEstimator.doneUnits(project, saved!), 100);
    expect(
        DailyGoal.doneOn(
            project: project,
            history: saved!,
            day: day,
            dayStart: DayStart.midnight),
        0);
  });

  testWidgets('existing undated-time entry pages can be corrected together',
      (tester) async {
    final history = [
      for (final record in [
        (id: 'a', entry: 'group'),
        (id: 'b', entry: 'group'),
        (id: 'c', entry: 'other')
      ])
        WorkSession(
            id: record.id,
            entryId: record.entry,
            projectId: 'p',
            startTime: day,
            endTime: day,
            amount: 1,
            startLine: 1,
            endLine: 42,
            description: record.id,
            isManual: true,
            timeRecorded: false),
    ];
    List<WorkSession>? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () => showHistoryEditor(
                context: context,
                projects: [project],
                history: history,
                day: day,
                dayLabel: 'יום',
                dayStart: DayStart.midnight,
                useGregorianDates: true,
                onHistoryUpdated: (result) => saved = result,
              ),
          child: const Text('open')),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('סמן ככתיבה קודמת').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('אישור'));
    await tester.pumpAndSettle();
    expect(saved!.map((s) => (s.id, s.backlogOnly)),
        [('a', true), ('b', true), ('c', false)]);
  });
}
