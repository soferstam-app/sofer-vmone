import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => StorageService.demoStore = null);

  for (final appTheme in AppTheme.values) {
    testWidgets(
        'workflow changes immediately between sittings in ${appTheme.name}',
        (tester) async {
      tester.view.physicalSize = const Size(900, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final project = Project(
        id: 'sefer',
        name: 'ספר תורה',
        type: ProjectType.sefer,
        price: 100,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: 42,
      );
      StorageService.demoStore = MemoryStore({
        'projects': jsonEncode([project.toJson()]),
        'history': '[]',
        'smart_workflow_enabled': false,
        'last_project': project.id,
      });

      await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(appTheme)
            .copyWith(splashFactory: NoSplash.splashFactory),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: SoferHome(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('מצב רגיל'));
      await tester.pumpAndSettle();
      expect(find.text('מצב חכם'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'smart to plain asks first and carries only the unfiled measured time',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final project = Project(
      id: 'sefer',
      name: 'ספר תורה',
      type: ProjectType.sefer,
      price: 100,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      linesPerPage: 42,
      totalPages: 245,
    );
    final savedLine = WorkSession(
      id: 'line-1',
      projectId: project.id,
      startTime: DateTime(2026, 8, 20, 9),
      endTime: DateTime(2026, 8, 20, 9, 10),
      amount: 1,
      startLine: 1,
      endLine: 1,
      description: 'עמוד א (1-1)',
      isManual: false,
      entryId: 'smart-entry',
      linesPerPageAtEntry: 42,
    );

    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([project.toJson()]),
      'history': jsonEncode([savedLine.toJson()]),
      'smart_workflow_enabled': true,
      'last_project': project.id,
      'timer_state': jsonEncode({
        'isPaused': true,
        'accumulatedElapsedSeconds': 1200,
        'accumulatedBreakSeconds': 0,
        'lastLapElapsedSeconds': 600,
        'isSmart': true,
        'projectId': project.id,
        'smartCurrentPage': 1,
        'smartCurrentLine': 2,
        'smartStartPage': 1,
        'smartStartLine': 2,
        'smartRecordedElapsedSeconds': 600,
        'smartSavedAny': true,
        'smartSavedLines': 1,
        'smartEntryId': 'smart-entry',
      }),
    });

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.modern)
          .copyWith(splashFactory: NoSplash.splashFactory),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: SoferHome(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('מצב חכם'), findsOneWidget);
    await tester.tap(find.text('מצב חכם'));
    await tester.pumpAndSettle();
    expect(find.text('לעבור למצב רגיל?'), findsOneWidget);

    await tester.tap(find.text('הישאר במצב הנוכחי'));
    await tester.pumpAndSettle();
    expect(find.text('מצב חכם'), findsOneWidget);

    await tester.tap(find.text('מצב חכם'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('כן, עבור'));
    await tester.pumpAndSettle();
    expect(find.text('מצב רגיל'), findsOneWidget);

    await tester.tap(find.text('סיים'));
    await tester.pumpAndSettle();

    expect(find.text('נמדדו 00:10:00'), findsOneWidget,
        reason: 'the first ten minutes were already filed with the smart line');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
