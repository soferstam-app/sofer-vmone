import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/logic/home_additions.dart';
import 'package:sofer_vmone/logic/partial_line_recording.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/smart_session.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

class ResetFailingStore extends MemoryStore {
  ResetFailingStore(super.initial);
  bool failReset = false;

  @override
  Future<void> setString(String key, String value) async {
    if (failReset &&
        key == 'timer_state' &&
        jsonDecode(value)['accumulatedElapsedSeconds'] == 5 * 60) {
      throw StateError('Storage full');
    }
    await super.setString(key, value);
  }
}

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

  Map<String, Object> initial(
          {bool smart = true,
          int currentMinutes = 25,
          int previousMinutes = 5,
          List<WorkSession> history = const []}) =>
      {
        'projects': jsonEncode([project.toJson()]),
        'history': jsonEncode(history.map((s) => s.toJson()).toList()),
        'smart_workflow_enabled': smart,
        'last_project': project.id,
        'timer_state': jsonEncode({
          'isPaused': true,
          'accumulatedElapsedSeconds': (5 + currentMinutes) * 60,
          'accumulatedBreakSeconds': 0,
          'lastLapElapsedSeconds': 5 * 60,
          'previousLineDurationSeconds': previousMinutes * 60,
          'isSmart': smart,
          'projectId': project.id,
          'smartCurrentPage': 7,
          'smartCurrentLine': 12,
          'smartStartPage': 7,
          'smartStartLine': 12,
          'smartRecordedElapsedSeconds': smart ? 5 * 60 : 0,
          'smartSavedAny': smart,
          'smartSavedLines': smart ? 1 : 0,
          'smartEntryId': 'smart-entry',
        }),
      };

  Future<void> pumpHome(WidgetTester tester,
      {AppTheme theme = AppTheme.modern}) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(theme)
          .copyWith(splashFactory: NoSplash.splashFactory),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: SoferHome(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    // Storage writes run in a shared future queue. Let them complete in the
    // real async zone instead of retaining a previous widget test's fake zone.
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
  }

  for (final theme in AppTheme.values) {
    testWidgets('restart at stop preserves time and position in $theme',
        (tester) async {
      final earlier = PartialLineRecording.create(
        project: project,
        position: const SmartPosition(7, 12),
        worked: const Duration(minutes: 9),
        endedAt: DateTime(2026, 9, 1),
      );
      StorageService.demoStore = MemoryStore(initial(history: [earlier]));
      await pumpHome(tester, theme: theme);
      await tap(
          tester,
          theme == AppTheme.modern
              ? find.text('יציאה')
              : find.byIcon(Icons.stop));
      await tester.pumpAndSettle();
      expect(find.text('זמן שורה חריג'), findsOneWidget);
      await tap(tester, find.text('התחל מדידה מחדש'));
      await tester.pumpAndSettle();
      final state = await StorageService().getTimerState();
      expect(state['accumulatedElapsedSeconds'], 5 * 60);
      expect(state['accumulatedBreakSeconds'], greaterThanOrEqualTo(25 * 60));
      expect(state['smartCurrentLine'], 12);
      expect(state['smartRecordedElapsedSeconds'], 5 * 60);
      expect((await StorageService().loadHistory()).single.toJson(),
          earlier.toJson());
      expect(find.text('00:09:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('keep at stop saves the suspicious partial interval',
      (tester) async {
    StorageService.demoStore = MemoryStore(initial());
    await pumpHome(tester);
    await tap(tester, find.text('יציאה'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('כן, שמור את הזמן'));
    await tester.pumpAndSettle();
    final saved = await StorageService().loadHistory();
    expect(saved.single.isPartialLine, isTrue);
    expect(saved.single.duration, const Duration(minutes: 25));
    expect(await StorageService().getTimerState(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('cancel leaves time and history untouched', (tester) async {
    StorageService.demoStore = MemoryStore(initial());
    await pumpHome(tester);
    await tap(tester, find.text('יציאה'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('ביטול'));
    await tester.pumpAndSettle();
    final state = await StorageService().getTimerState();
    expect(state['accumulatedElapsedSeconds'], 30 * 60);
    expect(state['smartCurrentLine'], 12);
    expect(await StorageService().loadHistory(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('an hour with no baseline is guarded in plain mode too',
      (tester) async {
    StorageService.demoStore = MemoryStore(initial(
      smart: false,
      currentMinutes: 60,
      previousMinutes: 0,
    ));
    await pumpHome(tester);
    await tap(tester, find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    expect(find.text('זמן שורה חריג'), findsOneWidget);
    expect(await StorageService().getPendingEntry(), isNull);
    await tap(tester, find.text('התחל מדידה מחדש'));
    await tester.pumpAndSettle();
    expect(
        (await StorageService().getTimerState())['accumulatedElapsedSeconds'],
        5 * 60);
    expect(await StorageService().getPendingEntry(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('storage failure rolls back the reset', (tester) async {
    final store = ResetFailingStore(initial());
    StorageService.demoStore = store;
    await pumpHome(tester);
    store.failReset = true;
    await tap(tester, find.text('יציאה'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('התחל מדידה מחדש'));
    await tester.pumpAndSettle();
    final state = await StorageService().getTimerState();
    expect(state['accumulatedElapsedSeconds'], 30 * 60);
    expect(state['accumulatedBreakSeconds'], 0);
    expect(await StorageService().loadHistory(), isEmpty);
    expect(find.textContaining('הזמן נשמר ללא איפוס'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
  });

  testWidgets('keep on line completion saves exactly one line', (tester) async {
    StorageService.demoStore = MemoryStore(initial());
    await pumpHome(tester);
    await tap(tester, find.text('המשך כתיבה'));
    await tester.pump();
    await tap(tester, find.textContaining('מעבר שורה'));
    await tester.pumpAndSettle();
    expect(find.text('זמן שורה חריג'), findsOneWidget);
    await tap(tester, find.text('כן, שמור את הזמן'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if ((await StorageService().getTimerState())['smartCurrentLine'] == 13) {
        break;
      }
    }
    final saved = await StorageService().loadHistory();
    expect(ProductionCalculator.seferLinesTotal(saved), 1);
    expect(saved.single.duration.inSeconds, 25 * 60);
    expect((await StorageService().getTimerState())['smartCurrentLine'], 13);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('stop with auto completion also asks before adding output',
      (tester) async {
    StorageService.demoStore = MemoryStore({
      ...initial(),
      'home_additions': jsonEncode(const HomeAdditionsSettings(
        finishWritingCompletesLine: true,
      ).toJson()),
    });
    await pumpHome(tester);
    await tap(tester, find.text('יציאה'));
    await tester.pumpAndSettle();
    expect(await StorageService().loadHistory(), isEmpty);
    await tap(tester, find.text('כן, שמור את הזמן'));
    await tester.pumpAndSettle();
    expect(
        ProductionCalculator.seferLinesTotal(
            await StorageService().loadHistory()),
        1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
