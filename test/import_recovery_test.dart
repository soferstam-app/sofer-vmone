import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';

import 'support/fault_store.dart';

void main() {
  final storage = StorageService();
  const journal = 'pending_work_mutation';
  final date = DateTime(2026, 11, 9, 9);
  final project = Project(
      id: 'p',
      name: 'ספר',
      type: ProjectType.sefer,
      price: 100,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0);
  const before = <String, Object>{
    'projects': '[{"futureProject":42}]',
    'history': '[]',
    'payments': '[]',
    'orders': '[]',
    'last_positions': '{"p":{"page":1,"line":2}}',
    'app_language': 'en',
    'notification_enabled': false,
    'day_rollover_hour': 1,
    'timer_state': '{"projectId":"p"}',
  };
  Future<void> importBackup() => storage.saveImportedSnapshot(
        projects: [project],
        history: [
          WorkSession(
              id: 's',
              projectId: 'p',
              startTime: date,
              endTime: date.add(const Duration(minutes: 12)),
              amount: 1,
              startLine: 1,
              endLine: 1,
              description: '',
              isManual: true)
        ],
        expenses: [Expense(id: 'e', product: 'דיו', date: date, amount: 3)],
        proofreads: [Proofread(id: 'r', projectId: 'p', scope: 'עמוד')],
        payments: [
          Payment(id: 'pay', projectId: 'p', amount: 70, receivedAt: date)
        ],
        orders: [
          Order(
              id: 'o',
              customerName: 'לקוח',
              orderedAt: date,
              dueDate: date,
              lastUpdated: date)
        ],
        lastPositions: {
          'p': {'page': 2, 'line': 3}
        },
        settings: {
          'notification_enabled': true,
          'day_rollover_hour': 4,
          'app_language': 'he',
          'keyboard_shortcuts': '{}'
        },
      );
  tearDown(() {
    StorageService.demoStore = null;
    StorageService.onChanged = null;
  });

  test('reopening an interrupted import rolls back ledgers and settings',
      () async {
    final store = FaultStore(before)
      ..blockedKey = 'keyboard_shortcuts'
      ..blocked = Completer<void>()
      ..release = Completer<void>();
    StorageService.demoStore = store;
    final pending = importBackup();
    await store.blocked!.future;
    final interrupted = store.snapshot;
    expect(interrupted[journal], isA<String>());
    expect(jsonDecode(interrupted['payments'] as String).single['id'], 'pay');
    expect(interrupted['notification_enabled'], isTrue);
    var readCompleted = false;
    final read = storage.exportAll().then((snapshot) {
      readCompleted = true;
      return snapshot;
    });
    await Future<void>.delayed(Duration.zero);
    expect(readCompleted, isFalse);
    store.release!.complete();
    await pending;
    expect((await read)['orders'], isNotEmpty);
    expect(store.getString(journal), isNull);

    final restarted = MemoryStore(interrupted);
    StorageService.demoStore = restarted;
    expect((await storage.exportAll())['payments'], isEmpty);
    expect(restarted.snapshot, before);
  });

  test('a rollback failure leaves recovery pending and suppresses notification',
      () async {
    final store = FaultStore(before)..failAt({4, 5});
    StorageService.demoStore = store;
    var notifications = 0;
    StorageService.onChanged = () async {
      notifications++;
    };
    await expectLater(importBackup(), throwsStateError);
    expect(store.getString(journal), isNotNull);
    await storage.ensureWorkRecovered();
    expect(store.snapshot, before);
    expect(notifications, 0);
  });

  test('every import write failure restores the exact original snapshot',
      () async {
    final baseline = FaultStore(before);
    StorageService.demoStore = baseline;
    await importBackup();
    expect(baseline.operations, greaterThan(10));

    for (var step = 1; step <= baseline.operations; step++) {
      final store = FaultStore(before)..failAt({step});
      StorageService.demoStore = store;
      var notifications = 0;
      StorageService.onChanged = () async {
        notifications++;
      };
      await expectLater(importBackup(), throwsStateError,
          reason: 'write $step');
      expect(store.snapshot, before, reason: 'write $step');
      expect(notifications, 0, reason: 'write $step');
    }
  });

  test('overlapping imports preserve the newest data and deletion', () async {
    StorageService.demoStore = MemoryStore({});
    final service = BackupService.forTesting();
    Project version(String name, int day, {bool deleted = false}) =>
        Project.fromJson({
          ...project.toJson(),
          'name': name,
          'lastUpdated': DateTime(2026, 11, day).toIso8601String(),
          if (deleted) 'deletedAt': DateTime(2026, 11, day).toIso8601String(),
        });
    BackupPreview preview(Project row) => BackupPreview(
        projects: [row],
        history: const [],
        expenses: const [],
        settings: const {},
        lastPositions: const {},
        fileName: 'backup.json');
    final newer = preview(version('עדכני', 9, deleted: true));
    final older = preview(version('ישן', 8));
    final outcomes = await Future.wait([
      service.applyBackup(newer),
      service.applyBackup(older),
    ]);
    final saved = (await storage.loadProjects()).single;
    expect(saved.name, 'עדכני');
    expect(saved.isDeleted, isTrue);
    expect(outcomes.first.projectStats.added, 1);
    expect(outcomes.last.projectStats.unchanged, 1);
  });
}
