import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => StorageService.demoStore = null);

  testWidgets('a fast finished-line then stop sequence is not dropped',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final project = Project(
      id: 'sefer',
      name: 'ספר תורה',
      type: ProjectType.sefer,
      price: 420,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0,
      linesPerPage: 42,
      totalPages: 245,
    );
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([project.toJson()]),
      'history': '[]',
      'smart_workflow_enabled': true,
      'last_project': project.id,
      'timer_state': jsonEncode({
        'isPaused': true,
        'accumulatedElapsedSeconds': 10 * 60,
        'accumulatedBreakSeconds': 0,
        'lastLapElapsedSeconds': 0,
        'isSmart': true,
        'projectId': project.id,
        'smartCurrentPage': 7,
        'smartCurrentLine': 12,
        'smartStartPage': 7,
        'smartStartLine': 12,
        'smartRecordedElapsedSeconds': 0,
        'smartSavedAny': false,
        'smartSavedLines': 0,
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
    await tester.tap(find.text('המשך כתיבה'));
    await tester.pump();
    await tester.tap(find.textContaining('מעבר שורה'));
    await tester.tap(find.text('יציאה'));
    await tester.pumpAndSettle();

    final saved = await StorageService().loadHistory();
    expect(saved, hasLength(1));
    expect(saved.single.isPartialLine, isFalse);
    expect(ProductionCalculator.seferLinesTotal(saved), 1);
    expect(await StorageService().getLastPosition(project.id),
        {'page': 7, 'line': 13});
    expect(await StorageService().getTimerState(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
