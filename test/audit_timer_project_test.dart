import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/home/ruled_home_body.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/logic/tefillin_units.dart';
import 'package:sofer_vmone/logic/timer_controller.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/project/tefillin_board.dart';
import 'package:sofer_vmone/project_summary_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

import 'support/fault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final p = Project(
      id: 'p',
      name: 'ספר בדיקה',
      type: ProjectType.sefer,
      price: 420,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0,
      totalPages: 245,
      linesPerPage: 42);
  Widget host(Widget child) => MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.klaf),
      home: Directionality(textDirection: TextDirection.rtl, child: child));
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> mountHome(WidgetTester tester, FaultStore store) async {
    StorageService.demoStore = store;
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const SoferHome()));
    await tester.pumpAndSettle();
  }

  FaultStore homeStore({bool paused = false}) => FaultStore({
        'projects': jsonEncode([p.toJson()]),
        'history': '[]',
        'last_project': p.id,
        'ask_break_length': false,
        'smart_workflow_enabled': false,
        if (paused)
          'timer_state': jsonEncode({
            'isPaused': true,
            'accumulatedElapsedSeconds': 600,
            'lastLapElapsedSeconds': 120,
            'previousLineDurationSeconds': 120,
            'projectId': p.id,
            'isSmart': false
          }),
      });
  HomeSnapshot snapshot(WidgetTester tester) =>
      tester.widget<RuledHomeBody>(find.byType(RuledHomeBody)).snapshot;
  setUp(() {
    StorageService.onChanged = null;
    StorageService.demoStore = null;
  });
  tearDown(() {
    StorageService.onChanged = null;
    StorageService.demoStore = null;
  });

  test('C10 controller start/stop never removes the owners durable checkpoint',
      () async {
    final store = homeStore(paused: true);
    StorageService.demoStore = store;
    final original = store.getString('timer_state');
    final clock = TimerController(onTick: () {});
    addTearDown(clock.dispose);
    clock.start();
    clock.pause();
    clock.start();
    clock.stop();
    expect(store.getString('timer_state'), original);
    expect(store.operations, 0);
  });

  test('C10 checkpoint restore banks elapsed time exactly once', () {
    var now = DateTime(2026, 10, 15, 9);
    var mono = Duration.zero;
    final clock =
        TimerController(onTick: () {}, now: () => now, monotonic: () => mono);
    addTearDown(clock.dispose);
    clock.start();
    now = now.add(const Duration(minutes: 10));
    mono += const Duration(minutes: 10);
    final checkpoint = clock.checkpoint();
    clock.pause();
    now = now.add(const Duration(minutes: 2));
    mono += const Duration(minutes: 2);
    clock.restoreFrom(checkpoint);
    expect(clock.elapsed, const Duration(minutes: 12));
    now = now.add(const Duration(minutes: 1));
    mono += const Duration(minutes: 1);
    expect(clock.elapsed, const Duration(minutes: 13));
  });

  testWidgets('C10 failed Start rolls back and a retry creates a durable timer',
      (tester) async {
    final store = homeStore();
    await mountHome(tester, store);
    store.arm('timer_state');
    await tester.tap(find.text('תחילת כתיבה'));
    await pumpFrames(tester);
    expect(snapshot(tester).isActive, isFalse);
    expect(await StorageService().getTimerState(), isEmpty);
    expect(find.textContaining('הפעלת הטיימר לא נשמרה'), findsOneWidget);
    await tester.tap(find.text('תחילת כתיבה'));
    await pumpFrames(tester);
    expect(snapshot(tester).isActive, isTrue);
    expect((await StorageService().getTimerState())['projectId'], p.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'C10 failed Resume preserves the paused checkpoint and measured time',
      (tester) async {
    final store = homeStore(paused: true);
    await mountHome(tester, store);
    final before = store.getString('timer_state');
    store.arm('timer_state');
    await tester.tap(find.text('המשך'));
    await pumpFrames(tester);
    expect(snapshot(tester).isPaused, isTrue);
    expect(store.getString('timer_state'), before);
    await tester.tap(find.text('המשך'));
    await pumpFrames(tester);
    expect(snapshot(tester).isPaused, isFalse);
    expect(
        (await StorageService().getTimerState())['accumulatedElapsedSeconds'],
        greaterThanOrEqualTo(600));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('C10 failed Pause keeps the timer running and the old checkpoint',
      (tester) async {
    final store = homeStore(paused: true);
    await mountHome(tester, store);
    await tester.tap(find.text('המשך'));
    await pumpFrames(tester);
    final before = store.getString('timer_state');
    store.arm('timer_state');
    await tester.tap(find.text('הפסקה'));
    await pumpFrames(tester);
    expect(snapshot(tester).isPaused, isFalse);
    expect(store.getString('timer_state'), before);
    await tester.tap(find.text('הפסקה'));
    await pumpFrames(tester);
    expect(snapshot(tester).isPaused, isTrue);
    expect((await StorageService().getTimerState())['isPaused'], isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'C10 failed lap reset restores the visible and durable lap boundary',
      (tester) async {
    final store = homeStore(paused: true);
    await mountHome(tester, store);
    await tester.tap(find.text('המשך'));
    await pumpFrames(tester);
    final before = snapshot(tester).sinceLastLap;
    store.arm('timer_state');
    await tester.tap(find.text('איפוס זמן שורה'));
    await pumpFrames(tester);
    expect(
        (await StorageService().getTimerState())['lastLapElapsedSeconds'], 120);
    expect(snapshot(tester).sinceLastLap, before);
    await tester.tap(find.text('איפוס זמן שורה'));
    await pumpFrames(tester);
    expect((await StorageService().getTimerState())['lastLapElapsedSeconds'],
        greaterThanOrEqualTo(600));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'C10 lifecycle failure is handled without an asynchronous exception',
      (tester) async {
    final store = homeStore(paused: true);
    await mountHome(tester, store);
    final before = store.getString('timer_state');
    store.arm('timer_state');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(store.getString('timer_state'), before);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpFrames(tester);
    expect(snapshot(tester).isPaused, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'C4 rejected write changes neither caller lists nor visible/stored tefillin',
      (tester) async {
    final project = Project(
        id: 't',
        name: 'תפילין בדיקה',
        type: ProjectType.tefillin,
        price: 1200,
        expenses: 0,
        targetDaily: 0,
        targetMonthly: 0,
        targetUnits: 1);
    final work = WorkSession(
        id: 's',
        projectId: 't',
        startTime: DateTime(2026, 10, 1, 9),
        endTime: DateTime(2026, 10, 1, 10),
        amount: 1,
        startLine: 0,
        endLine: 0,
        pairIndex: 1,
        parshiya: 1,
        tefillinType: 'head',
        description: 'קדש',
        isManual: true);
    final callerHistory = [work];
    final callerProjects = [project];
    final store = FaultStore({
      'projects': jsonEncode([project.toJson()]),
      'history': jsonEncode([work.toJson()])
    });
    StorageService.demoStore = store;
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var committed = 0;
    await tester.pumpWidget(host(ProjectSummaryScreen(
        projects: callerProjects,
        history: callerHistory,
        onWorkCommitted: (projects, history) async {
          committed++;
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הכתיבה'));
    await tester.pumpAndSettle();
    Future<void> openSlot() async {
      await tester.runAsync(() async {
        final board = tester.widget<TefillinBoard>(find.byType(TefillinBoard));
        board.onSlotTap!(board.slots.singleWhere((s) =>
            s.pair == 1 && s.side == TefillinSide.head && s.parshiya == 1));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
    }

    store.arm('history');
    await openSlot();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('מסמן: נפסל'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(committed, 0);
    expect(callerHistory.single.isInvalid, isFalse);
    expect(callerProjects.single.tefillinFlags, isEmpty);
    expect((await StorageService().loadHistory()).single.isInvalid, isFalse);
    expect(
        (await StorageService().loadProjects()).single.tefillinFlags, isEmpty);
    final board = tester.widget<TefillinBoard>(find.byType(TefillinBoard));
    expect(
        board.slots
            .singleWhere((s) =>
                s.pair == 1 && s.side == TefillinSide.head && s.parshiya == 1)
            .state,
        isNot(SlotState.voided));
    await openSlot();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('מסמן: נפסל'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(committed, 1);
    expect((await StorageService().loadHistory()).single.isInvalid, isTrue);
    expect(
        (await StorageService().loadProjects())
            .single
            .tefillinFlags['1:head:1'],
        'void');
    expect(callerHistory.single.isInvalid, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'C4 unit correction awaits storage and reports failure without a success receipt',
      (tester) async {
    final work = WorkSession(
        id: 's',
        projectId: p.id,
        startTime: DateTime(2026, 10, 1, 9),
        endTime: DateTime(2026, 10, 1, 10),
        amount: 1,
        startLine: 1,
        endLine: 42,
        description: 'עמוד א',
        isManual: true);
    final store = FaultStore({
      'projects': jsonEncode([p.toJson()]),
      'history': jsonEncode([work.toJson()])
    });
    StorageService.demoStore = store;
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(ProjectSummaryScreen(
        projects: [p],
        history: [work],
        onHistoryUpdated: (next) async {
          await StorageService().saveHistory(next);
        })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הכתיבה'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sefer-page-1')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('מחק רישום שגוי'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    store.arm('history');
    await tester.runAsync(() async {
      await tester.tap(find.text('מחק'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await pumpFrames(tester);
    expect(store.failKey, isNull, reason: 'The durable write was attempted');
    expect((await StorageService().loadHistory()).single.isDeleted, isFalse);
    expect(find.textContaining('התיקון לא נשמר'), findsOneWidget);
    expect(find.text('העמוד נמחק'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
