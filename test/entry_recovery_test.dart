import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/entry/entry_draft.dart';
import 'package:sofer_vmone/entry/entry_sheet.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/timer_controller.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

class _PendingWriteFails extends MemoryStore {
  _PendingWriteFails() : super({});

  @override
  Future<void> setString(String key, String value) {
    if (key == 'pending_entry') throw StateError('storage unavailable');
    return super.setString(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => StorageService.demoStore = null);

  Project project(ProjectType type) => Project(
        id: type.name,
        name: type == ProjectType.sefer ? 'ספר תורה' : 'מזוזות',
        type: type,
        price: 100,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: type == ProjectType.sefer ? 42 : null,
      );

  Widget host({
    required Project project,
    required Future<void> Function(EntrySave) onSave,
  }) =>
      MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.klaf),
        locale: const Locale('he', 'IL'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('he', 'IL')],
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(builder: (context) {
              return ElevatedButton(
                onPressed: () => showEntrySheet(
                  context: context,
                  isManual: true,
                  projects: [project],
                  history: const [],
                  useGregorianDates: true,
                  dayStart: DayStart.midnight,
                  onProjectCreated: (_) {},
                  onSave: onSave,
                  initialProject: project,
                ),
                child: const Text('פתיחה'),
              );
            }),
          ),
        ),
      );

  test('pending entry round-trips every value needed for recovery', () async {
    StorageService.demoStore = MemoryStore({});
    final draft = EntryDraft(
      projectId: 'p',
      entryId: 'stable-entry',
      isManual: true,
      measuredTime: const Duration(minutes: 37),
      measuredEnd: DateTime(2026, 8, 25, 11, 12),
      date: DateTime(2026, 8, 24),
      includeTime: true,
      byDuration: false,
      worked: const Duration(minutes: 52),
      startTime: const TimeOfDay(hour: 9, minute: 13),
      endTime: const TimeOfDay(hour: 10, minute: 5),
      amount: '2',
      partialLine: '16',
      mezuzaIndex: 4,
      tefillinMode: 'parshiya',
      tefillinPart: 'hand',
      tefillinParshiya: 4,
      tefillinPair: '7',
    );

    await StorageService().savePendingEntry(draft);
    final restored = await StorageService().getPendingEntry();

    expect(restored, isNotNull);
    expect(restored!.entryId, 'stable-entry');
    expect(restored.amount, '2');
    expect(restored.mezuzaIndex, 4);
    expect(restored.tefillinPair, '7');
    expect(restored.startTime, const TimeOfDay(hour: 9, minute: 13));
  });

  testWidgets('wide dialog shows validation inside the form and keeps a draft',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sefer = project(ProjectType.sefer);

    await tester.pumpWidget(host(project: sefer, onSave: (_) async {}));
    await tester.tap(find.text('פתיחה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור וסגור'));
    await tester.pumpAndSettle();

    final visibleError = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.textContaining('עמוד התחלה תקין'),
    );
    expect(visibleError, findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget,
        reason: 'a rejected form stays open for correction');
    expect((await StorageService().getPendingEntry())?.projectId, sefer.id);
  });

  testWidgets('a durable-write failure remains visible and recoverable',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mezuza = project(ProjectType.mezuza);

    await tester.pumpWidget(host(
      project: mezuza,
      onSave: (_) async => throw StateError('disk full'),
    ));
    await tester.tap(find.text('פתיחה'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'כמות מזוזות'), '1');
    await tester.tap(find.text('שמור וסגור'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('השמירה לא הושלמה'),
      ),
      findsOneWidget,
    );
    expect((await StorageService().getPendingEntry())?.amount, '1');
  });

  testWidgets('saving never starts when its recovery copy cannot be written',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    StorageService.demoStore = _PendingWriteFails();
    final sefer = project(ProjectType.sefer);
    var saveCalls = 0;

    await tester.pumpWidget(host(
      project: sefer,
      onSave: (_) async => saveCalls++,
    ));
    await tester.tap(find.text('פתיחה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('שמור וסגור'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('לא ניתן לגשת לאחסון'),
      ),
      findsOneWidget,
    );
    expect(saveCalls, 0);
  });

  testWidgets('startup reopens a pending manual entry with its fields',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mezuza = project(ProjectType.mezuza);
    final draft = EntryDraft(
      projectId: mezuza.id,
      entryId: 'recovered-entry',
      isManual: true,
      date: DateTime(2026, 8, 24),
      amount: '2',
    );
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([mezuza.toJson()]),
      'history': '[]',
      'last_project': mezuza.id,
      'pending_entry': jsonEncode(draft.toJson()),
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

    expect(find.text('הזנה ידנית'), findsOneWidget);
    final amount =
        tester.widget<TextField>(find.widgetWithText(TextField, 'כמות מזוזות'));
    expect(amount.controller!.text, '2');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stopping regular writing stores the summary before opening it',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sefer = project(ProjectType.sefer);
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([sefer.toJson()]),
      'history': '[]',
      'last_project': sefer.id,
      'timer_state': jsonEncode({
        'isPaused': true,
        'accumulatedElapsedSeconds': 20 * 60,
        'accumulatedBreakSeconds': 0,
        'lastLapElapsedSeconds': 0,
        'isSmart': false,
        'projectId': sefer.id,
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

    await tester.tap(find.text('סיים'));
    await tester.pumpAndSettle();

    expect(find.text('סיכום כתיבה'), findsOneWidget);
    expect((await StorageService().getPendingEntry())?.measuredTime,
        const Duration(minutes: 20));
    expect(await StorageService().getTimerState(), isEmpty,
        reason: 'the durable pending summary now owns the stopped sitting');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a pending token already in history is cleared, not reopened',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mezuza = project(ProjectType.mezuza);
    final draft = EntryDraft(
      projectId: mezuza.id,
      entryId: 'already-durable',
      isManual: true,
      amount: '1',
    );
    final durable = WorkSession(
      id: 'durable-record',
      projectId: mezuza.id,
      startTime: DateTime(2026, 8, 25, 9),
      endTime: DateTime(2026, 8, 25, 10),
      amount: 1,
      startLine: 0,
      endLine: 0,
      description: 'מזוזה',
      isManual: true,
      entryId: draft.entryId,
    );
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([mezuza.toJson()]),
      'history': jsonEncode([durable.toJson()]),
      'last_project': mezuza.id,
      'pending_entry': jsonEncode(draft.toJson()),
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

    expect(find.byType(AlertDialog), findsNothing);
    expect(await StorageService().getPendingEntry(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('stopping for a pending summary can retain the old timer state',
      () async {
    StorageService.demoStore = MemoryStore({});
    final clock = TimerController(onTick: () {});
    addTearDown(clock.dispose);

    clock.start();
    await StorageService().saveTimerState({'isPaused': true, 'projectId': 'p'});
    clock.stop(clearStoredState: false);
    await Future<void>.delayed(Duration.zero);

    expect(await StorageService().getTimerState(), isNotEmpty);
  });
}
