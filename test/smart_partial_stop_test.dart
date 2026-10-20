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

  Map<String, dynamic> pausedTimer({int minutes = 10}) => {
        'isPaused': true,
        'accumulatedElapsedSeconds': minutes * 60,
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
      };

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.modern)
          .copyWith(splashFactory: NoSplash.splashFactory),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: SoferHome(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('stopping normally saves time and keeps the unfinished line',
      (tester) async {
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([project.toJson()]),
      'history': '[]',
      'smart_workflow_enabled': true,
      'last_project': project.id,
      'timer_state': jsonEncode(pausedTimer()),
    });
    await pumpHome(tester);

    await tester.tap(find.text('יציאה'));
    await tester.pumpAndSettle();

    final saved = await StorageService().loadHistory();
    expect(saved, hasLength(1));
    expect(saved.single.isPartialLine, isTrue);
    expect(saved.single.partialPositionPage, 7);
    expect(saved.single.partialPositionLine, 12);
    expect(saved.single.duration, const Duration(minutes: 10));
    expect(ProductionCalculator.seferLinesTotal(saved), 0);
    expect(await StorageService().getLastPosition(project.id),
        {'page': 7, 'line': 12});

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
