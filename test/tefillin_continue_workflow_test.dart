import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/entry/entry_sheet.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/home_additions.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => StorageService.demoStore = null);
  final project = Project(
    id: 'p',
    name: 'תפילין',
    type: ProjectType.tefillin,
    price: 1000,
    expenses: 0,
    targetDaily: 0,
    targetMonthly: 0,
    targetUnits: 3,
  );
  WorkSession done(int number, {int pair = 2}) => WorkSession(
        id: '$pair-$number',
        projectId: 'p',
        startTime: DateTime(2026, 10, 1, 9),
        endTime: DateTime(2026, 10, 1, 10),
        amount: 1,
        startLine: 0,
        endLine: 0,
        description: '',
        isManual: true,
        pairIndex: pair,
        tefillinType: 'head',
        parshiya: number,
      );
  Future<void> tap(WidgetTester tester, Finder finder,
      {bool settle = true}) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  void size(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget app(AppTheme theme, Widget home) => MaterialApp(
        theme: AppThemeBuilder.build(theme)
            .copyWith(splashFactory: NoSplash.splashFactory),
        locale: const Locale('he', 'IL'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        supportedLocales: const [Locale('he', 'IL')],
        home: Directionality(textDirection: TextDirection.rtl, child: home),
      );

  testWidgets('add another keeps the chosen set when several sets are open',
      (tester) async {
    size(tester);
    final saved = <EntrySave>[];
    StorageService.demoStore = MemoryStore({});
    await tester.pumpWidget(app(
        AppTheme.modern,
        Scaffold(
            body: Builder(
          builder: (context) => ElevatedButton(
              onPressed: () => showEntrySheet(
                    context: context,
                    isManual: true,
                    projects: [project],
                    history: [done(1), done(2), done(1, pair: 3)],
                    useGregorianDates: true,
                    dayStart: DayStart.midnight,
                    onProjectCreated: (_) {},
                    onSave: (entry) async {
                      saved.add(entry);
                    },
                    initialProject: project,
                  ),
              child: const Text('פתיחה')),
        ))));
    await tap(tester, find.text('פתיחה'));
    await tap(tester, find.byType(DropdownButtonFormField<String>));
    await tap(tester, find.text('המשך שמע של ראש, זוג 2 — משורה 1').last);
    await tester.ensureVisible(find.text('הוסף עוד'));
    await tap(tester, find.text('הוסף עוד'));
    expect(saved.single.sessions.single.pairIndex, 2);
    expect(find.textContaining('המשך והיה אם שמע של ראש, זוג 2 — משורה 1'),
        findsOneWidget);
    await tester.ensureVisible(find.text('שמור וסגור'));
    await tap(tester, find.text('שמור וסגור'));
    expect(saved.last.sessions.single.pairIndex, 2);
    expect(saved.last.sessions.single.parshiya, 4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  for (final theme in AppTheme.values) {
    for (final manual in [true, false]) {
      testWidgets(
          'continue the same set after a whole Parashah: ${theme.name}, manual=$manual',
          (tester) async {
        size(tester);
        final saved = <EntrySave>[];
        StorageService.demoStore = MemoryStore({});
        await tester.pumpWidget(app(
            theme,
            Scaffold(
                body: Builder(
              builder: (context) => ElevatedButton(
                  onPressed: () => showEntrySheet(
                        context: context,
                        isManual: manual,
                        projects: [project],
                        history: [done(1), done(2)],
                        useGregorianDates: true,
                        dayStart: DayStart.midnight,
                        onProjectCreated: (_) {},
                        onSave: (entry) async {
                          saved.add(entry);
                        },
                        initialProject: project,
                        measuredTime: const Duration(minutes: 10),
                      ),
                  child: const Text('פתיחה')),
            ))));
        await tap(tester, find.text('פתיחה'));
        expect(find.textContaining('המשך שמע של ראש, זוג 2 — משורה 1'),
            findsOneWidget);
        expect(find.textContaining('המשך הסט: פרשיית שמע'), findsOneWidget);
        await tester.ensureVisible(find.text('הוסף עוד'));
        await tap(tester, find.text('הוסף עוד'));
        expect(saved.single.sessions.single.pairIndex, 2);
        expect(saved.single.sessions.single.parshiya, 3);
        expect(saved.single.sessions.single.amount, 1);
        expect(find.textContaining('המשך והיה אם שמע של ראש, זוג 2 — משורה 1'),
            findsOneWidget);
        await tester.ensureVisible(find.text('שמור וסגור'));
        await tap(tester, find.text('שמור וסגור'));
        expect(saved, hasLength(2));
        expect(saved.last.sessions.single.parshiya, 4);
        expect(saved.last.sessions.single.pairIndex, 2);
        expect(saved.last.sessions.single.timeRecorded, manual);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }

    testWidgets('smart mode repairs a completed old position in ${theme.name}',
        (tester) async {
      size(tester);
      StorageService.demoStore = MemoryStore({
        'projects': jsonEncode([project.toJson()]),
        'history': jsonEncode(
            [done(1).toJson(), done(2).toJson(), done(1, pair: 3).toJson()]),
        'smart_workflow_enabled': true,
        'last_project': 'p',
        'last_positions': jsonEncode({
          'p': {'page': 10, 'line': 4}
        }),
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(app(theme, const SoferHome()));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(
          await StorageService().getLastPosition('p'), {'page': 11, 'line': 1});
      final start =
          find.text(theme == AppTheme.modern ? 'כניסה' : 'תחילת כתיבה');
      await tester.runAsync(() async {
        await tester.tap(start);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      expect((await StorageService().getTimerState())['smartCurrentPage'], 11);
      expect(find.textContaining('כבר הסתיימה. יש לבחור'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    for (final automatic in [false, true]) {
      testWidgets(
          'stop on the final line and resume the set: ${theme.name}, automatic=$automatic',
          (tester) async {
        size(tester);
        final previous = done(2).copyWith(startLine: 1, endLine: 3);
        StorageService.demoStore = MemoryStore({
          'projects': jsonEncode([project.toJson()]),
          'history': jsonEncode([done(1).toJson(), previous.toJson()]),
          'smart_workflow_enabled': true,
          'last_project': 'p',
          'home_additions': jsonEncode(HomeAdditionsSettings(
            finishWritingCompletesLine: automatic,
          ).toJson()),
          'timer_state': jsonEncode({
            'isPaused': true,
            'accumulatedElapsedSeconds': 120,
            'accumulatedBreakSeconds': 0,
            'lastLapElapsedSeconds': 0,
            'isSmart': true,
            'projectId': 'p',
            'smartCurrentPage': 10,
            'smartCurrentLine': 4,
            'smartStartPage': 10,
            'smartStartLine': 4,
            'smartRecordedElapsedSeconds': 0,
            'smartSavedAny': false,
            'smartSavedLines': 0,
            'smartEntryId': 'last-line',
          }),
        });
        await tester.pumpWidget(app(theme, const SoferHome()));
        await tester.pumpAndSettle();
        final stop = find.text(theme == AppTheme.modern ? 'יציאה' : 'סיים');
        if (automatic) {
          await tap(tester, stop);
        } else {
          await tap(tester,
              find.text(theme == AppTheme.modern ? 'המשך כתיבה' : 'המשך'),
              settle: false);
          await tester.runAsync(() async {
            await tester.tap(find.text(theme == AppTheme.modern
                ? 'מעבר שורה (סיימתי)'
                : 'סיימתי שורה'));
            await tester.tap(stop);
            await Future<void>.delayed(const Duration(milliseconds: 30));
          });
          await tester.pumpAndSettle();
        }
        expect(await StorageService().getTimerState(), isEmpty);
        expect(await StorageService().getLastPosition('p'),
            {'page': 11, 'line': 1});
        final history = await StorageService().loadHistory();
        expect(history, hasLength(3));
        expect(history.last.parshiya, 2);
        expect(history.last.startLine, 4);
        expect(history.last.endLine, 4);
        expect(history.last.isPartialLine, isFalse);
        await tap(tester,
            find.text(theme == AppTheme.modern ? 'כניסה' : 'תחילת כתיבה'),
            settle: false);
        expect(
            (await StorageService().getTimerState())['smartCurrentPage'], 11);
        expect((await StorageService().loadHistory()), hasLength(3));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
