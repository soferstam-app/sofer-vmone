import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/home/floating_window.dart';
import 'package:sofer_vmone/settings/home_additions_screen.dart';
import 'package:sofer_vmone/entry/entry_draft.dart';
import 'package:sofer_vmone/logic/home_additions.dart';
import 'package:sofer_vmone/logic/partial_line_recording.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/smart_live_recording.dart';
import 'package:sofer_vmone/logic/smart_session.dart';
import 'package:sofer_vmone/logic/timer_controller.dart';
import 'package:sofer_vmone/logic/work_time_breakdown.dart';
import 'package:sofer_vmone/logic/work_correction.dart';
import 'package:sofer_vmone/logic/recording.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

class FailingTimerStore extends MemoryStore {
  FailingTimerStore(super.initial);
  bool fail = false;
  @override
  Future<void> setString(String key, String value) async {
    if (fail && key == 'timer_state') throw StateError('disk full');
    await super.setString(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Heebo', 'FrankRuhlLibre']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font-var.ttf')))
          .load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => StorageService.demoStore = null);

  group('professional time', () {
    late DateTime now;
    late Duration mono;
    late TimerController clock;
    void pass(int minutes) {
      now = now.add(Duration(minutes: minutes));
      mono += Duration(minutes: minutes);
    }

    setUp(() {
      now = DateTime(2026, 11, 1, 9);
      mono = Duration.zero;
      clock =
          TimerController(onTick: () {}, now: () => now, monotonic: () => mono);
    });
    tearDown(() => clock.dispose());

    test('resetting unattended pen time keeps reading before and after the lap',
        () {
      clock.start();
      pass(5);
      clock.beginReadingCorrection();
      pass(10);
      clock.endReadingCorrection();
      clock.recordLap();
      pass(60);
      clock.beginReadingCorrection();
      pass(3);
      clock.pause();
      clock.restartCurrentLine();
      clock.start();
      pass(5);
      expect(clock.elapsed, const Duration(minutes: 23));
      expect(clock.totalBreakElapsed, const Duration(minutes: 60));
      expect(clock.sinceLastLap, const Duration(minutes: 5));
      final reading =
          clock.workIntervals.where((span) => span.reading).toList();
      expect(reading.map((s) => s.workMs), [600000, 180000]);
      expect(reading.map((s) => s.start),
          [DateTime(2026, 11, 1, 9, 5), DateTime(2026, 11, 1, 10, 15)]);
    });

    test('reading freezes the line while remaining work, with a distinct break',
        () {
      clock.start();
      pass(10);
      clock.beginReadingCorrection();
      pass(8);
      expect(clock.sinceLastLap, const Duration(minutes: 10));
      expect(clock.elapsed, const Duration(minutes: 18));
      clock.endReadingCorrection();
      pass(5);
      expect(clock.sinceLastLap, const Duration(minutes: 15));
      clock.recordLap();
      expect(clock.previousLineDuration, const Duration(minutes: 15));
      clock.pause();
      pass(3);
      final sitting = clock.stop();
      expect(sitting.worked, const Duration(minutes: 23));
      expect(sitting.readingCorrection, const Duration(minutes: 8));
      expect(sitting.onBreak, const Duration(minutes: 3));
    });
    test('subsecond reading and saved line boundaries survive a checkpoint',
        () {
      void passMs(int milliseconds) {
        final duration = Duration(milliseconds: milliseconds);
        now = now.add(duration);
        mono += duration;
      }

      clock.start();
      passMs(300);
      clock.recordLap();
      clock.beginReadingCorrection();
      passMs(500);
      final checkpoint = clock.checkpoint();
      expect(clock.restoreFrom(checkpoint), isTrue);
      expect(clock.elapsed, const Duration(milliseconds: 800));
      expect(clock.lastLapElapsed, const Duration(milliseconds: 300));
      expect(clock.previousLineDuration, const Duration(milliseconds: 300));
      expect(clock.sinceLastLap, Duration.zero);
      expect(
          clock.workIntervals.where((span) => span.reading).single.workMs, 500);
    });

    test('restart while reading keeps the line frozen and the reading category',
        () {
      clock.start();
      pass(10);
      clock.beginReadingCorrection();
      pass(2);
      final checkpoint = clock.checkpoint();
      clock.dispose();
      pass(20);
      clock =
          TimerController(onTick: () {}, now: () => now, monotonic: () => mono);
      expect(clock.restoreFrom(checkpoint), isTrue);
      expect(clock.isReadingCorrection, isTrue);
      expect(clock.elapsed, const Duration(minutes: 32));
      expect(clock.readingCorrectionElapsed, const Duration(minutes: 22));
      expect(clock.sinceLastLap, const Duration(minutes: 10));
      pass(5);
      expect(clock.sinceLastLap, const Duration(minutes: 10));
      clock.endReadingCorrection();
      pass(1);
      expect(clock.sinceLastLap, const Duration(minutes: 11));
    });
    test('pause from reading closes reading before counting a normal break',
        () {
      clock.start();
      pass(3);
      clock.beginReadingCorrection();
      pass(2);
      clock.pause();
      pass(7);
      expect(clock.isReadingCorrection, isFalse);
      clock.restoreFrom(clock.checkpoint());
      expect(clock.isPaused, isTrue);
      expect(clock.readingCorrectionElapsed, const Duration(minutes: 2));
      expect(clock.totalBreakElapsed, const Duration(minutes: 7));
      clock.start();
      pass(1);
      expect(clock.sinceLastLap, const Duration(minutes: 4));
    });
    test('reading alone does not trigger unattended line review', () {
      clock.start();
      pass(1);
      clock.beginReadingCorrection();
      pass(120);
      expect(clock.hasUnusualLineTime, isFalse);
      final sitting = clock.previewStop();
      expect(sitting.readingCorrection, const Duration(hours: 2));
      expect(clock.isReadingCorrection, isTrue);
      clock.commitPreview(sitting);
      clock.start();
      pass(1);
      expect(clock.readingCorrectionElapsed, Duration.zero);
      expect(clock.sinceLastLap, const Duration(minutes: 1));
    });
    test('rolling back a failed line restores the reading baseline', () {
      clock.start();
      pass(2);
      clock.beginReadingCorrection();
      pass(3);
      clock.endReadingCorrection();
      final lap = clock.lastLapElapsed;
      final readingLap = clock.lapReadingElapsed;
      clock.recordLap();
      clock.restoreLastLap(lap, lapReading: readingLap);
      expect(clock.sinceLastLap, const Duration(minutes: 2));
    });
  });

  final project = Project(
      id: 'm',
      name: 'מזוזות',
      type: ProjectType.mezuza,
      price: 100,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0);
  test(
      'metadata survives JSON and merged smart checkpoints without changing output',
      () {
    WorkSession session(int line) => WorkSession(
        id: '$line',
        projectId: 'm',
        startTime: DateTime(2026, 11, 1, 9),
        endTime: DateTime(2026, 11, 1, 9, line),
        amount: 0,
        startLine: 0,
        endLine: 1,
        mezuzaIndex: 1,
        description: '',
        isManual: false,
        entryId: 'timer');
    final allocated = WorkTimeBreakdown.allocate([session(1), session(2)],
        reading: const Duration(seconds: 61),
        breaks: const Duration(seconds: 7));
    final restored =
        allocated.map((s) => WorkSession.fromJson(s.toJson())).toList();
    final merged = SmartLiveRecording.merge([], restored);
    final details = WorkTimeBreakdown.of(merged);
    expect(details.work, const Duration(minutes: 3));
    expect(details.reading, const Duration(seconds: 61));
    expect(details.breaks, const Duration(seconds: 7));
    expect(ProductionCalculator.mezuzaLinesTotal(merged), 2);
    expect(details.label(), contains('קריאה / תיקון: 00:01:01'));
  });
  test('unfinished line carries only pen time, total work stays intact', () {
    final partial = WorkTimeBreakdown.allocate([
      PartialLineRecording.create(
          project: project,
          position: const SmartPosition(1, 1),
          worked: const Duration(minutes: 10),
          endedAt: DateTime(2026, 11, 1, 10))
    ], reading: const Duration(minutes: 3))
        .single;
    expect(
        PartialLineRecording.carriedTime(
            [partial], project, const SmartPosition(1, 1)),
        const Duration(minutes: 7));
    expect(partial.duration, const Duration(minutes: 10));
  });
  test('splitting and reweighting work preserve reading and break totals', () {
    final source = WorkTimeBreakdown.allocate([
      WorkSession(
          id: 'legacy',
          projectId: 'm',
          startTime: DateTime(2026, 11, 1, 9),
          endTime: DateTime(2026, 11, 1, 9, 30),
          amount: 3,
          startLine: 0,
          endLine: 0,
          description: '',
          isManual: false,
          entryId: 'e')
    ], reading: const Duration(minutes: 6), breaks: const Duration(minutes: 3))
        .single;
    final corrected = WorkCorrection.markMezuzaInvalid(
            history: [source], projectId: 'm', index: 2)
        .history
        .where((s) => !s.isDeleted)
        .toList();
    final before = WorkTimeBreakdown.of(corrected);
    expect(before.reading, const Duration(minutes: 6));
    expect(before.breaks, const Duration(minutes: 3));
    final reweighted = Recording(entryId: 'e', sessions: corrected)
        .divideBy((s) => s.mezuzaIndex == 2 ? 2 : 1);
    final after = WorkTimeBreakdown.of(reweighted);
    expect(after.reading, before.reading);
    expect(after.breaks, before.breaks);
    expect(after.work, before.work);
  });
  test('backup snapshot retains reading metadata and the recovery draft',
      () async {
    StorageService.demoStore = MemoryStore({});
    final storage = StorageService();
    final history = WorkTimeBreakdown.allocate([
      PartialLineRecording.create(
          project: project,
          position: const SmartPosition(1, 1),
          worked: const Duration(minutes: 10),
          endedAt: DateTime(2026, 11, 1, 10))
    ], reading: const Duration(minutes: 2), breaks: const Duration(minutes: 1));
    await storage.saveHistory(history);
    await storage.savePendingEntry(EntryDraft.timed(
        projectId: 'm',
        entryId: 'e',
        measuredTime: const Duration(minutes: 10),
        measuredEnd: DateTime(2026, 11, 1),
        readingCorrection: const Duration(minutes: 2),
        sittingBreak: const Duration(minutes: 1)));
    final snapshot = await storage.exportAllAfterPendingWrites();
    final restored = (snapshot['history'] as List).map(
        (raw) => WorkSession.fromJson(Map<String, dynamic>.from(raw as Map)));
    expect(WorkTimeBreakdown.of(restored).reading, const Duration(minutes: 2));
    final draft = EntryDraft.fromJson(jsonDecode(
        (snapshot['migrationRecovery'] as Map)['pendingEntryRaw'] as String));
    expect(draft.readingCorrection, const Duration(minutes: 2));
  });
  test('defaults and pending forms preserve the optional classification', () {
    expect(
        HomeAdditionsSettings.fromJson({}).readingCorrectionEnabled, isFalse);
    final settings =
        HomeAdditionsSettings.defaults.copyWith(readingCorrectionEnabled: true);
    expect(
        HomeAdditionsSettings.fromJson(settings.toJson())
            .readingCorrectionEnabled,
        isTrue);
    final draft = EntryDraft.timed(
        projectId: 'm',
        entryId: 'e',
        measuredTime: const Duration(minutes: 10),
        measuredEnd: DateTime(2026, 11, 1),
        readingCorrection: const Duration(minutes: 3),
        sittingBreak: const Duration(minutes: 2));
    final restored = EntryDraft.fromJson(draft.toJson());
    expect(restored.readingCorrection, draft.readingCorrection);
    expect(restored.sittingBreak, draft.sittingBreak);
  });

  Map<String, Object> initial({bool smart = true, bool enabled = true}) => {
        'projects': jsonEncode([project.toJson()]),
        'history': '[]',
        'last_project': 'm',
        'smart_workflow_enabled': smart,
        'home_additions': jsonEncode(HomeAdditionsSettings(
                readingCorrectionEnabled: enabled,
                finishWritingCompletesLine: true)
            .toJson()),
        'timer_state': jsonEncode({
          'projectId': 'm',
          'isSmart': smart,
          'isPaused': false,
          'sessionStartTime': DateTime.now().toIso8601String(),
          'accumulatedElapsedSeconds': 600,
          'readingCorrectionMs': 120000,
          'isReadingCorrection': true,
          'readingCheckpointAt': DateTime.now().toIso8601String(),
          'smartCurrentPage': 1,
          'smartCurrentLine': 1,
          'smartStartPage': 1,
          'smartStartLine': 1,
          'smartEntryId': 'timer',
        }),
      };
  Future<void> host(WidgetTester tester, AppTheme theme) async {
    tester.view.physicalSize = const Size(1100, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(theme),
        home: const Directionality(
            textDirection: TextDirection.rtl, child: SoferHome())));
    await tester.pumpAndSettle();
  }

  for (final theme in AppTheme.values) {
    for (final smart in [true, false]) {
      testWidgets('reading and resume in $theme smart=$smart', (tester) async {
        StorageService.demoStore = MemoryStore(initial(smart: smart));
        await host(tester, theme);
        expect(find.text('חזרה לכתיבה'), findsOneWidget);
        expect(find.text('סיימתי שורה'), findsNothing);
        expect(find.textContaining('קריאה / תיקון: 00:02:'), findsOneWidget);
        await tester.ensureVisible(find.text('חזרה לכתיבה'));
        await tester.tap(find.text('חזרה לכתיבה'));
        await tester.pump(const Duration(milliseconds: 400));
        expect((await StorageService().getTimerState())['isReadingCorrection'],
            isFalse);
        await tester.tap(find.text('קריאה / תיקון'));
        await tester.pump(const Duration(milliseconds: 400));
        expect((await StorageService().getTimerState())['isReadingCorrection'],
            isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
  testWidgets('stopping during reading saves time without completing the line',
      (tester) async {
    StorageService.demoStore = MemoryStore(initial());
    await host(tester, AppTheme.modern);
    await tester.runAsync(() async {
      await tester.tap(find.text('יציאה'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();
    final history = await StorageService().loadHistory();
    expect(history, hasLength(1));
    expect(history.single.isTimeOnly, isTrue);
    expect(ProductionCalculator.mezuzaLinesTotal(history), 0);
    expect(WorkTimeBreakdown.of(history).reading.inSeconds,
        greaterThanOrEqualTo(120));
    expect(await StorageService().getLastPosition('m'), {'page': 1, 'line': 1});
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('failed toggle preserves reading and its durable checkpoint',
      (tester) async {
    final store = FailingTimerStore(initial());
    StorageService.demoStore = store;
    await host(tester, AppTheme.modern);
    store.fail = true;
    await tester.tap(find.text('חזרה לכתיבה'));
    await tester.pumpAndSettle();
    expect(find.text('חזרה לכתיבה'), findsOneWidget);
    expect((await StorageService().getTimerState())['isReadingCorrection'],
        isTrue);
    expect(find.textContaining('לא נשמר'), findsOneWidget);
    store.fail = false;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('regular stop and save preserve the breakdown in history',
      (tester) async {
    StorageService.demoStore = MemoryStore(initial(smart: false));
    await host(tester, AppTheme.modern);
    await tester.runAsync(() async {
      await tester.tap(find.text('סיים'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('קריאה / תיקון:'), findsOneWidget);
    final amount = find.widgetWithText(TextField, 'כמות מזוזות');
    await tester.ensureVisible(amount);
    await tester.enterText(amount, '1');
    await tester.runAsync(() async {
      await tester.tap(find.text('שמור וסגור'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    final history = await StorageService().loadHistory();
    expect(WorkTimeBreakdown.of(history).reading.inSeconds,
        greaterThanOrEqualTo(120));
    expect(ProductionCalculator.mezuzaLinesTotal(history), 22);
    expect(await StorageService().getPendingEntry(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  for (final theme in AppTheme.values) {
    testWidgets('Tefillin reading stop keeps progress in $theme',
        (tester) async {
      final data = initial();
      data['projects'] = jsonEncode([
        Project(
                id: 'm',
                name: 'תפילין',
                type: ProjectType.tefillin,
                targetUnits: 1,
                price: 100,
                expenses: 0,
                targetDaily: 0,
                targetMonthly: 0)
            .toJson()
      ]);
      StorageService.demoStore = MemoryStore(data);
      await host(tester, theme);
      expect(find.text('חזרה לכתיבה'), findsOneWidget);
      await tester.ensureVisible(
          find.text(theme == AppTheme.modern ? 'יציאה' : 'סיים'));
      await tester.runAsync(() async {
        await tester
            .tap(find.text(theme == AppTheme.modern ? 'יציאה' : 'סיים'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pumpAndSettle();
      final history = await StorageService().loadHistory();
      expect(history, isNotEmpty,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join(' | '));
      expect(history.single.isTimeOnly, isTrue);
      expect(ProductionCalculator.tefillinPhysicalLinesTotal(history), 0);
      expect(WorkTimeBreakdown.of(history).reading.inSeconds,
          greaterThanOrEqualTo(120));
      expect(
          await StorageService().getLastPosition('m'), {'page': 1, 'line': 1});
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
  testWidgets('the setting can be enabled and survives storage',
      (tester) async {
    StorageService.demoStore = MemoryStore({});
    await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.modern),
        home: const HomeAdditionsScreen()));
    await tester.pumpAndSettle();
    final card = find
        .ancestor(
            of: find.text('אפשר מדידת זמן קריאה ותיקון'),
            matching: find.byType(Row))
        .last;
    final toggle = find.descendant(of: card, matching: find.byType(Switch));
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect((await StorageService().getHomeAdditions()).readingCorrectionEnabled,
        isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('floating window has a resume control at its minimum size',
      (tester) async {
    final clock = TimerController(onTick: () {});
    clock.start();
    clock.beginReadingCorrection();
    addTearDown(clock.dispose);
    tester.view.physicalSize = const Size(320, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var resumed = false;
    await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.modern),
        home: FloatingTimerWindow(
            clock: clock,
            onStart: () {},
            onPause: () {},
            onStop: () {},
            onLap: () {},
            onRestore: () {},
            showReadingCorrection: true,
            onReadingCorrection: () => resumed = true)));
    await tester.tap(find.textContaining('חזרה לכתיבה'));
    expect(resumed, isTrue);
    clock.dispose();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
      'a restored reading state can exit even after the setting is disabled',
      (tester) async {
    StorageService.demoStore = MemoryStore(initial(enabled: false));
    await host(tester, AppTheme.modern);
    expect(find.text('חזרה לכתיבה'), findsOneWidget);
    await tester.tap(find.text('חזרה לכתיבה'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('קריאה / תיקון'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
