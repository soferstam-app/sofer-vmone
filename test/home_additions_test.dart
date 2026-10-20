// The optional home tools are one feature set, not a separate implementation
// per theme or workflow. These tests keep the defaults quiet, the arithmetic
// signed, and the shared snapshot visible everywhere it is drawn.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/home/cards_smart_body.dart';
import 'package:sofer_vmone/home/ruled_home_body.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/logic/home_additions.dart';
import 'package:sofer_vmone/logic/metronome_audio.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/settings/home_additions_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => StorageService.demoStore = null);

  group('home addition settings', () {
    test('every addition is opt-in', () {
      const value = HomeAdditionsSettings.defaults;
      expect(value.celebrateDailyGoal, isFalse);
      expect(value.finishWritingCompletesLine, isFalse);
      expect(value.lineTargetEnabled, isFalse);
      expect(value.metronomeEnabled, isFalse);
      expect(value.writingTargetEnabled, isFalse);
      expect(value.sessionTargetChimeEnabled, isFalse);
      expect(value.endTimeAlertEnabled, isFalse);
    });

    test('round-trips and clamps unsafe values', () {
      final value = HomeAdditionsSettings.fromJson({
        'celebrateDailyGoal': true,
        'finishWritingCompletesLine': true,
        'lineTargetEnabled': true,
        'lineTargetSeconds': -4,
        'metronomeEnabled': true,
        'metronomeBpm': 900,
        'metronomeVolume': 500,
        'writingTargetEnabled': true,
        'writingTargetMinutes': 0,
        'sessionTargetChimeEnabled': true,
        'endTimeAlertEnabled': true,
        'endTimeMinutes': 2000,
      });
      expect(value.lineTargetSeconds, 1);
      expect(value.finishWritingCompletesLine, isTrue);
      expect(value.metronomeBpm, 180);
      expect(value.metronomeVolume, 100);
      expect(value.writingTargetMinutes, 1);
      expect(value.sessionTargetChimeEnabled, isTrue);
      expect(value.endTimeMinutes, 1439);
      expect(HomeAdditionsSettings.fromJson(value.toJson()).toJson(),
          value.toJson());
    });

    test('survives storage and malformed storage fails closed', () async {
      StorageService.demoStore = MemoryStore({});
      final storage = StorageService();
      expect((await storage.getHomeAdditions()).metronomeEnabled, isFalse);

      const chosen = HomeAdditionsSettings(
        celebrateDailyGoal: true,
        finishWritingCompletesLine: true,
        lineTargetEnabled: true,
        lineTargetSeconds: 210,
        metronomeEnabled: true,
        metronomeBpm: 72,
        metronomeVolume: 35,
        writingTargetEnabled: true,
        writingTargetMinutes: 90,
        sessionTargetChimeEnabled: true,
        endTimeAlertEnabled: true,
        endTimeMinutes: 20 * 60 + 15,
      );
      await storage.setHomeAdditions(chosen);
      expect((await storage.getHomeAdditions()).toJson(), chosen.toJson());

      StorageService.demoStore = MemoryStore({'home_additions': '{not json'});
      expect((await storage.getHomeAdditions()).toJson(),
          HomeAdditionsSettings.defaults.toJson());
    });
  });

  group('target arithmetic', () {
    test('counts down and then becomes a red-ready signed overrun', () {
      const before = TargetCountdown(
        target: Duration(minutes: 5),
        elapsed: Duration(minutes: 4, seconds: 58),
      );
      const after = TargetCountdown(
        target: Duration(minutes: 5),
        elapsed: Duration(minutes: 5, seconds: 2),
      );
      expect(before.label, '00:00:02');
      expect(before.isOverrun, isFalse);
      expect(after.label, '-00:00:02');
      expect(after.isOverrun, isTrue);
      expect(
          after.crossedSince(const Duration(minutes: 4, seconds: 59)), isTrue);
    });

    test('chooses today when possible and tomorrow after the chosen hour', () {
      expect(
        nextClockOccurrence(DateTime(2026, 8, 20, 15), 18 * 60),
        DateTime(2026, 8, 20, 18),
      );
      expect(
        nextClockOccurrence(DateTime(2026, 8, 20, 19), 18 * 60),
        DateTime(2026, 8, 21, 18),
      );
      expect(metronomeInterval(60), const Duration(seconds: 1));
      expect(metronomeInterval(120), const Duration(milliseconds: 500));
    });

    test('bundled metronome click is a short valid WAV', () {
      final wav = buildMetronomeWav();
      expect(String.fromCharCodes(wav.take(4)), 'RIFF');
      expect(String.fromCharCodes(wav.skip(8).take(4)), 'WAVE');
      expect(wav.length, greaterThan(44));
      expect(wav.length, lessThan(3000));
    });

    test('timer alert is distinct, valid, and long enough to hear', () {
      final wav = buildAlertWav();
      expect(String.fromCharCodes(wav.take(4)), 'RIFF');
      expect(String.fromCharCodes(wav.skip(8).take(4)), 'WAVE');
      expect(wav.length, greaterThan(30000));
      expect(wav.length, lessThan(50000));
    });

    test('session target chimes once, only during active writing', () {
      bool due({
        bool enabled = true,
        bool sounded = false,
        bool running = true,
        bool paused = false,
        Duration elapsed = const Duration(minutes: 30),
      }) =>
          sessionTargetChimeDue(
            enabled: enabled,
            sounded: sounded,
            running: running,
            paused: paused,
            targetMinutes: 30,
            elapsed: elapsed,
          );

      expect(due(elapsed: const Duration(minutes: 29, seconds: 59)), isFalse);
      expect(due(), isTrue);
      expect(due(sounded: true), isFalse);
      expect(due(paused: true), isFalse);
      expect(due(enabled: false), isFalse);
    });

    test('native sound channel receives both beat and alert', () async {
      const channel = MethodChannel('sofer_vmone/metronome');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final audio = MetronomeAudio();
      expect(await audio.beat(35), isTrue);
      expect(await audio.alert(), isTrue);
      expect(calls.map((call) => call.method), ['beat', 'alert']);
      expect(calls.first.arguments, {'volume': 35});
    });
  });

  Project project() => Project(
        id: 'p',
        name: 'ספר תורה',
        type: ProjectType.sefer,
        price: 40000,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: 42,
        totalPages: 245,
      );

  HomeSnapshot snapshot() => HomeSnapshot(
        project: project(),
        projects: [project()],
        hebrewDate: 'כ״ו באב תשפ״ו',
        isRunning: true,
        isPaused: false,
        elapsed: '00:25:00',
        sinceLastLap: '00:05:02',
        lineClockLabel: 'יעד לשורה',
        lineClockValue: '-00:00:02',
        lineClockOverrun: true,
        writingTargetStatus: 'יעד הכתיבה · נותרו 01:05:00',
        showWritingTargetButton: true,
        endTimeStatus: 'שעת סיום 18:00 · נותרו 00:35:00',
        metronomeBpm: 72,
        metronomeActive: true,
        currentLine: 8,
        pageLabel: 'עמוד מ״ג',
        positionUnit: 'שורה',
        todayOutput: '21 שורות',
      );

  final actions = HomeActions(
    onStart: () {},
    onStop: () {},
    onBreak: () {},
    onManualEntry: () {},
    onNextLine: () {},
    onLap: () {},
    onEditPosition: () {},
    onSkipMezuza: () {},
    onProjectChanged: (_) {},
    onResume: () {},
    onWritingTarget: () {},
  );

  Future<void> pumpBody(WidgetTester tester, Widget body, AppTheme theme,
      {double textScale = 1}) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(theme)
          .copyWith(splashFactory: NoSplash.splashFactory),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: body),
      ),
    ));
    await tester.pump();
  }

  group('layout parity', () {
    testWidgets('cards smart mode shows every enabled addition',
        (tester) async {
      await pumpBody(
        tester,
        CardsSmartBody(
          snapshot: snapshot(),
          actions: actions,
          pulse: const AlwaysStoppedAnimation(1),
        ),
        AppTheme.modern,
      );
      expect(find.text('יעד לשורה'), findsOneWidget);
      expect(find.text('-00:00:02'), findsOneWidget);
      final targetText = tester.widget<Text>(find.text('-00:00:02'));
      expect(
        targetText.style?.color,
        SoferTokens.of(tester.element(find.text('-00:00:02'))).danger,
      );
      expect(find.textContaining('יעד הכתיבה'), findsOneWidget);
      expect(find.textContaining('שעת סיום'), findsOneWidget);
      expect(find.textContaining('72 פעימות'), findsOneWidget);
    });

    for (final theme in [AppTheme.klaf, AppTheme.layla]) {
      for (final smart in [false, true]) {
        testWidgets(
            '${theme.name} shows additions in ${smart ? 'smart' : 'plain'} mode',
            (tester) async {
          await pumpBody(
            tester,
            RuledHomeBody(
              snapshot: snapshot(),
              actions: actions,
              isSmart: smart,
            ),
            theme,
          );
          expect(find.text('יעד לשורה'), findsOneWidget);
          expect(find.text('-00:00:02'), findsOneWidget);
          final targetText = tester.widget<Text>(find.text('-00:00:02'));
          expect(
            targetText.style?.color,
            SoferTokens.of(tester.element(find.text('-00:00:02'))).danger,
          );
          expect(find.textContaining('יעד הכתיבה'), findsOneWidget);
          expect(find.textContaining('72 פעימות'), findsOneWidget);
        });
      }
    }

    testWidgets('modern plain mode reads the same stored setting',
        (tester) async {
      final p = project();
      const additions = HomeAdditionsSettings(
        lineTargetEnabled: true,
        lineTargetSeconds: 300,
        writingTargetEnabled: true,
        writingTargetMinutes: 90,
        metronomeEnabled: true,
        metronomeBpm: 72,
      );
      StorageService.demoStore = MemoryStore({
        'projects': jsonEncode([p.toJson()]),
        'history': '[]',
        'home_additions': jsonEncode(additions.toJson()),
        'smart_workflow_enabled': false,
      });
      tester.view.physicalSize = const Size(900, 1500);
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
      await tester.tap(find.text('תחילת כתיבה'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('יעד לשורה'), findsOneWidget);
      expect(find.text('בחירת יעד לישיבה'), findsOneWidget);
      expect(find.textContaining('72 פעימות'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('maximum text does not clip the main writing surfaces',
        (tester) async {
      for (final theme in AppTheme.values) {
        final body = theme == AppTheme.modern
            ? CardsSmartBody(
                snapshot: snapshot(),
                actions: actions,
                pulse: const AlwaysStoppedAnimation(1),
              )
            : RuledHomeBody(
                snapshot: snapshot(), actions: actions, isSmart: true);
        await pumpBody(tester, body, theme, textScale: 2);
        final exception = tester.takeException();
        expect(exception, isNull, reason: theme.name);
      }
    });
  });

  testWidgets('the dedicated settings screen exposes seven switches',
      (tester) async {
    StorageService.demoStore = MemoryStore({});
    await pumpBody(tester, const HomeAdditionsScreen(), AppTheme.modern);
    await tester.pumpAndSettle();
    expect(find.text('תוספות למסך הבית'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(7));
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.first.value, isTrue,
        reason: 'the existing break prompt remains on by default');
    for (final widget in switches.skip(1)) {
      expect(widget.value, isFalse);
    }
  });

  testWidgets('all sound controls remain reachable at maximum text',
      (tester) async {
    const additions = HomeAdditionsSettings(
      metronomeEnabled: true,
      writingTargetEnabled: true,
      sessionTargetChimeEnabled: true,
      endTimeAlertEnabled: true,
    );
    StorageService.demoStore = MemoryStore({
      'home_additions': jsonEncode(additions.toJson()),
    });
    await pumpBody(tester, const HomeAdditionsScreen(), AppTheme.klaf,
        textScale: 2);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('בדיקת צליל ההתראה'), 500);
    expect(find.text('בדיקת צליל היעד'), findsOneWidget);
    expect(find.text('בדיקת צליל ההתראה'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
