import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/backup/migration_backup_gate.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/main.dart' as app;
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/onboarding/onboarding_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

import 'support/fault_store.dart';

class MigrationFolderPicker extends FilePicker {
  String? path;
  Object? error;
  int calls = 0;
  MigrationFolderPicker(this.path);
  @override
  Future<String?> getDirectoryPath(
      {String? dialogTitle,
      bool lockParentWindow = false,
      String? initialDirectory}) async {
    calls++;
    if (error != null) throw error!;
    return path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BackupService service;
  FilePicker? originalPicker;
  late Directory directory;
  late MigrationFolderPicker picker;
  const dialog = ValueKey('backup-migration-dialog');
  const choose = ValueKey('backup-migration-choose');
  const defer = ValueKey('backup-migration-defer');

  final project = Project(
      id: 'p',
      name: 'ספר בדיקה',
      type: ProjectType.sefer,
      price: 300,
      expenses: 20,
      targetDaily: 1,
      targetMonthly: 20,
      totalPages: 245,
      linesPerPage: 42);

  setUp(() {
    service = BackupService.forTesting();
    try {
      originalPicker = FilePicker.platform;
    } catch (_) {}
    directory = Directory.systemTemp.createTempSync('migration-backup-');
    picker = MigrationFolderPicker(directory.path);
    FilePicker.platform = picker;
    StorageService.demoStore = MemoryStore({});
    StorageService.onChanged = null;
    service.autoBackupStatus.value = {};
  });
  tearDown(() {
    StorageService.onChanged = null;
    StorageService.demoStore = null;
    if (originalPicker != null) FilePicker.platform = originalPicker!;
    directory.deleteSync(recursive: true);
  });

  Widget host(
          {AppTheme theme = AppTheme.modern,
          bool english = false,
          bool enabled = true}) =>
      MaterialApp(
        locale: Locale(english ? 'en' : 'he'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        theme: AppThemeBuilder.build(theme),
        home: MigrationBackupGate(
            backupService: service,
            enabled: enabled,
            child: const Scaffold(body: Text('application-ready'))),
      );

  Future<void> io(WidgetTester tester) async {
    // Pump preference continuations before waiting for real filesystem I/O.
    // A fake-clock pumpAndSettle alone cannot finish an OS file operation.
    await tester.pump();
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await io(tester);
  }

  for (final theme in AppTheme.values) {
    testWidgets(
        'external-folder request works in $theme and only closes after verified save',
        (tester) async {
      await tester.pumpWidget(host(theme: theme));
      await io(tester);
      expect(find.byKey(dialog), findsOneWidget);
      expect(find.text('application-ready'), findsNothing);
      expect(await StorageService().getAutoBackupFolder(), isNull);
      await tap(tester, choose);
      expect(find.byKey(dialog), findsNothing);
      expect(find.text('application-ready'), findsOneWidget);
      expect(await StorageService().getAutoBackupFolder(), directory.path);
      final file =
          File('${directory.path}/${BackupService.liveBackupFileName}');
      expect(file.existsSync(), isTrue);
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final checksum = raw.remove('checksum');
      expect(checksum, sha256.convert(utf8.encode(jsonEncode(raw))).toString());
      expect((await StorageService().getAutoBackupStatus())['lastSuccess'],
          isA<String>());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'existing verified destination is actually refreshed without asking again',
      (tester) async {
    StorageService.demoStore = MemoryStore({
      'auto_backup_folder': directory.path,
      'projects': jsonEncode([project.toJson()])
    });
    await tester.pumpWidget(host());
    await io(tester);
    expect(find.byKey(dialog), findsNothing);
    expect(find.text('application-ready'), findsOneWidget);
    expect(picker.calls, 0);
    final raw = jsonDecode(
        File('${directory.path}/${BackupService.liveBackupFileName}')
            .readAsStringSync());
    expect(raw['projects'].single['id'], project.id);
    expect((await StorageService().getAutoBackupStatus())['error'], isNull);
  });

  testWidgets('old successful status does not conceal a missing destination',
      (tester) async {
    final missing = '${directory.path}/removed-folder';
    StorageService.demoStore = MemoryStore({
      'auto_backup_folder': missing,
      'auto_backup_status': jsonEncode({
        'folder': missing,
        'lastSuccess': '2026-10-01T12:00:00',
        'error': null
      })
    });
    await tester.pumpWidget(host());
    await io(tester);
    expect(find.byKey(dialog), findsOneWidget);
    expect(find.textContaining('לא נוצר גיבוי חיצוני מאומת'), findsOneWidget);
    expect((await StorageService().getAutoBackupStatus())['error'], isNotNull);
    await tap(tester, choose);
    expect(find.text('application-ready'), findsOneWidget);
    expect(await StorageService().getAutoBackupFolder(), directory.path);
  });

  testWidgets(
      'cancelled picker remains incomplete and reappears on the next launch',
      (tester) async {
    picker.path = null;
    await tester.pumpWidget(host());
    await io(tester);
    await tap(tester, choose);
    expect(find.byKey(dialog), findsOneWidget);
    expect(find.textContaining('לא נבחרה תיקייה'), findsOneWidget);
    expect(await StorageService().getAutoBackupFolder(), isNull);
    await tap(tester, defer);
    expect(find.text('application-ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host());
    await io(tester);
    expect(find.byKey(dialog), findsOneWidget);
    expect(picker.calls, 1);
  });

  testWidgets('failed first write never announces success and supports retry',
      (tester) async {
    final target = '${directory.path}/not-created-yet';
    picker.path = target;
    await tester.pumpWidget(host());
    await io(tester);
    await tap(tester, choose);
    expect(find.byKey(dialog), findsOneWidget);
    expect(find.textContaining('לא נוצר גיבוי חיצוני מאומת'), findsOneWidget);
    expect(find.textContaining('הגיבוי החיצוני נכתב ואומת'), findsNothing);
    expect(
        (await StorageService().getAutoBackupStatus())['lastSuccess'], isNull);
    Directory(target).createSync();
    await tap(tester, const ValueKey('backup-migration-retry'));
    expect(find.text('application-ready'), findsOneWidget);
    expect(File('$target/${BackupService.liveBackupFileName}').existsSync(),
        isTrue);
  });

  testWidgets(
      'picker exception and preference write failure keep the setup actionable',
      (tester) async {
    final store = FaultStore({});
    StorageService.demoStore = store;
    picker.error = StateError('permission denied');
    await tester.pumpWidget(host());
    await io(tester);
    await tap(tester, choose);
    expect(find.byKey(dialog), findsOneWidget);
    expect(await StorageService().getAutoBackupFolder(), isNull);
    picker.error = null;
    store.arm('auto_backup_folder');
    await tap(tester, choose);
    expect(find.byKey(dialog), findsOneWidget);
    expect(await StorageService().getAutoBackupFolder(), isNull);
    await tap(tester, choose);
    expect(find.text('application-ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English request fits a narrow screen and can be deferred',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(english: true));
    await io(tester);
    expect(find.text('External backup before migration'), findsOneWidget);
    await tap(tester, defer);
    expect(find.text('application-ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('destination build can disable the migration campaign',
      (tester) async {
    await tester.pumpWidget(host(enabled: false));
    await tester.pumpAndSettle();
    expect(find.text('application-ready'), findsOneWidget);
    expect(find.byKey(dialog), findsNothing);
    expect(picker.calls, 0);
  });

  for (final kind in [
    'already-0.6.0',
    'legacy-no-onboarding',
    'empty-existing',
    'new-user'
  ]) {
    testWidgets('real app asks $kind after language and onboarding',
        (tester) async {
      StorageService.demoStore = MemoryStore({
        if (kind != 'new-user') 'app_language': 'he',
        if (kind != 'legacy-no-onboarding' && kind != 'new-user')
          'onboarding_seen': true,
        if (kind != 'empty-existing' && kind != 'new-user')
          'projects': jsonEncode([project.toJson()]),
        'last_run_app_version': '0.6.0',
      });
      await app.localeController.load();
      await app.themeController.load();
      await app.accessibilityController.load();
      await tester.pumpWidget(const app.MyApp());
      await io(tester);
      if (kind == 'new-user') {
        expect(find.byKey(dialog), findsNothing);
        await tester.tap(find.text('עברית'));
        await io(tester);
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.byKey(dialog), findsNothing);
        await tester.tap(find.text('דלג'));
        await io(tester);
      }
      expect(find.byKey(dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'setup preserves an older backup when this installation lacks its records',
      (tester) async {
    final old = <String, dynamic>{
      'app': BackupService.appId,
      'formatVersion': BackupService.formatVersion,
      'projects': [project.toJson()],
      'history': [],
      'expenses': [],
      'proofreads': [],
      'payments': [],
      'orders': [],
      'settings': {},
    };
    old['checksum'] = sha256.convert(utf8.encode(jsonEncode(old))).toString();
    final original = jsonEncode(old);
    final file = File('${directory.path}/${BackupService.liveBackupFileName}');
    file.writeAsStringSync(original);
    StorageService.demoStore =
        MemoryStore({'auto_backup_folder': directory.path});
    await tester.pumpWidget(host());
    await io(tester);
    expect(find.byKey(dialog), findsOneWidget);
    expect(find.textContaining('רשומות שאינן במכשיר הזה'), findsOneWidget);
    expect(file.readAsStringSync(), original);
    expect(
        (await StorageService().getAutoBackupStatus())['needsImport'], isTrue);
    final another = Directory('${directory.path}/another-folder');
    another.createSync();
    picker.path = another.path;
    await tap(tester, choose);
    expect(find.text('application-ready'), findsOneWidget);
    expect(file.readAsStringSync(), original);
  });

  test('unverifiable destination is preserved instead of silently replaced',
      () async {
    final file = File('${directory.path}/${BackupService.liveBackupFileName}');
    file.writeAsStringSync('{interrupted older backup');
    StorageService.demoStore =
        MemoryStore({'auto_backup_folder': directory.path});
    expect(await service.writeAutoBackup(), isFalse);
    expect(file.readAsStringSync(), '{interrupted older backup');
    expect(
        (await StorageService().getAutoBackupStatus())['needsImport'], isTrue);
  });

  test(
      'verified live file includes all six ledgers, settings, positions, extensions and open work',
      () async {
    final when = DateTime(2026, 10, 18, 9);
    final history = WorkSession(
        id: 's',
        projectId: project.id,
        startTime: when,
        endTime: when.add(const Duration(hours: 1)),
        amount: 3,
        startLine: 1,
        endLine: 42,
        description: 'עמוד ג',
        isManual: false,
        extraFields: const {'entryNotes': 'הערה ביומן', 'futureField': 'kept'});
    final order = Order(
        id: 'o',
        customerName: 'מזמין',
        orderedAt: when,
        dueDate: when.add(const Duration(days: 20)),
        lastUpdated: when,
        unreadableItems: const [
          {'id': 'future-item', 'typeName': 'future-type', 'quantity': 9}
        ]);
    final ledgers = <String, List<Map<String, dynamic>>>{
      'projects': [project.toJson()],
      'history': [history.toJson()],
      'expenses': [
        Expense(id: 'e', product: 'דיו', date: when, amount: 40).toJson()
      ],
      'proofreads': [
        Proofread(id: 'r', projectId: project.id, scope: 'הגהה').toJson()
      ],
      'payments': [
        Payment(id: 'pay', projectId: project.id, amount: 70, receivedAt: when)
            .toJson()
      ],
      'orders': [order.toJson()],
    };
    final positions = {
      project.id: {'page': 3, 'line': 21}
    };
    const timer = '{"projectId":"p","isRunning":true,"elapsedSeconds":180}';
    const draft = '{"projectId":"p","entryId":"draft","amount":"3"}';
    StorageService.demoStore = MemoryStore({
      for (final entry in ledgers.entries) entry.key: jsonEncode(entry.value),
      'auto_backup_folder': directory.path,
      'last_positions': jsonEncode(positions),
      'app_language': 'he',
      'writing_journal': '{"showNotes":true}',
      'work_calendar_rules': '{"schemaVersion":2,"inIsrael":true}',
      'timer_state': timer,
      'pending_entry': draft,
    });
    expect(await service.writeAutoBackup(), isTrue);
    final file = File('${directory.path}/${BackupService.liveBackupFileName}');
    final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    for (final entry in ledgers.entries) {
      expect(raw[entry.key], entry.value, reason: entry.key);
      expect(raw['counts'][entry.key], entry.value.length);
    }
    expect(raw['lastPositions'], positions);
    expect(raw['settings']['app_language'], 'he');
    expect(raw['settings']['writing_journal'], '{"showNotes":true}');
    expect(raw['migrationRecovery']['timerStateRaw'], timer);
    expect(raw['migrationRecovery']['pendingEntryRaw'], draft);
    expect(raw['migrationRecovery']['requiresReview'], isTrue);
    final checksum = raw.remove('checksum');
    expect(checksum, sha256.convert(utf8.encode(jsonEncode(raw))).toString());

    // Every later durable write refreshes the same external file.
    StorageService.onChanged = service.writeAutoBackup;
    await StorageService().setSoferName('שם מעודכן');
    final updated = jsonDecode(file.readAsStringSync());
    expect(updated['settings']['sofer_name'], 'שם מעודכן');
    expect(directory.listSync().whereType<File>().length, 1);
  });
}
