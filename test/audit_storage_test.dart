import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/logic/work_correction.dart';
import 'package:sofer_vmone/logic/merge_service.dart';
import 'package:sofer_vmone/storage_service.dart';

import 'support/fault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final project = Project(
      id: 'p',
      name: 'בדיקה',
      type: ProjectType.tefillin,
      price: 1200,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      targetUnits: 2);
  final work = WorkSession(
      id: 's',
      projectId: 'p',
      startTime: DateTime(2026, 10, 1, 9),
      endTime: DateTime(2026, 10, 1, 10),
      amount: 1,
      startLine: 0,
      endLine: 0,
      pairIndex: 1,
      tefillinType: 'head',
      parshiya: 1,
      description: 'קדש',
      isManual: true);
  final storage = StorageService();
  String projects() => jsonEncode([
        project.toJson(),
        {'id': 'future', 'newField': 42}
      ]);
  String history() => jsonEncode([work.toJson(), 'future-raw-record']);

  setUp(() {
    StorageService.onChanged = null;
    BackupService.instance.autoBackupStatus.value = {};
  });
  tearDown(() {
    StorageService.onChanged = null;
    StorageService.demoStore = null;
  });

  for (var step = 1; step <= 4; step++) {
    test('C4 rolls back a failure at snapshot write $step', () async {
      final beforeProjects = projects();
      final beforeHistory = history();
      final store =
          FaultStore({'projects': beforeProjects, 'history': beforeHistory});
      StorageService.demoStore = store;
      var notifications = 0;
      StorageService.onChanged = () async {
        notifications++;
      };
      store.failAt({step});
      await expectLater(
          storage.saveWorkSnapshot(projects: [
            project.copyWith(tefillinFlags: {'1:head:1': 'void'})
          ], history: [
            work.copyWith(isInvalid: true)
          ]),
          throwsStateError);
      expect(store.getString('projects'), beforeProjects);
      expect(store.getString('history'), beforeHistory);
      expect(store.getString('pending_work_mutation'), isNull);
      expect((await storage.loadHistory()).single.isInvalid, isFalse);
      expect(notifications, 0);
    });
  }

  test('C4 interrupted rollback recovers on the next read', () async {
    final store = FaultStore({'projects': projects(), 'history': history()});
    StorageService.demoStore = store;
    store.failAt({3, 4});
    await expectLater(
        storage.saveWorkSnapshot(projects: [
          project.copyWith(tefillinFlags: {'1:head:1': 'void'})
        ], history: [
          work.copyWith(isInvalid: true)
        ]),
        throwsStateError);
    expect(store.getString('pending_work_mutation'), isNotNull);
    expect(
        (await storage.loadProjects())
            .singleWhere((p) => p.id == project.id)
            .tefillinFlags,
        isEmpty);
    expect((await storage.loadHistory()).single.isInvalid, isFalse);
    expect(store.getString('pending_work_mutation'), isNull);
  });

  test('C4 readers wait for the entire snapshot and backup runs once',
      () async {
    final store = FaultStore({'projects': projects(), 'history': history()});
    StorageService.demoStore = store;
    store.blockedKey = 'history';
    store.blocked = Completer<void>();
    store.release = Completer<void>();
    var notified = 0;
    List<Project>? observedProjects;
    List<WorkSession>? observedHistory;
    StorageService.onChanged = () async {
      notified++;
      observedProjects = await storage.loadProjects();
      observedHistory = await storage.loadHistory();
    };
    final saving = storage.saveWorkSnapshot(projects: [
      project.copyWith(tefillinFlags: {'1:head:1': 'void'})
    ], history: [
      work.copyWith(isInvalid: true)
    ]);
    await store.blocked!.future;
    var readFinished = false;
    final reading = storage.exportAll().then((value) {
      readFinished = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(readFinished, isFalse);
    store.release!.complete();
    await saving;
    final data = await reading;
    expect(data['projects'], hasLength(2), reason: 'Unknown records survive');
    expect(data['history'], hasLength(2));
    expect(notified, 1);
    expect(
        observedProjects!.singleWhere((p) => p.id == project.id).tefillinFlags,
        isNotEmpty);
    expect(observedHistory!.single.isInvalid, isTrue);
  });

  for (final key in [
    'projects',
    'history',
    'expenses',
    'proofreads',
    'payments',
    'orders',
    'last_positions'
  ]) {
    for (final raw in ['not-json', '', key == 'last_positions' ? '[]' : '{}']) {
      test('C7 export rejects damaged $key value ${jsonEncode(raw)}', () async {
        final store = MemoryStore({key: raw});
        StorageService.demoStore = store;
        await expectLater(storage.exportAll(), throwsFormatException);
        expect(store.getString(key), raw);
      });
    }
  }

  test('C7-C8 bad source keeps the last backup and records failure/recovery',
      () async {
    final folder = await Directory.systemTemp.createTemp('audit-backup-');
    addTearDown(() => folder.delete(recursive: true));
    final store = MemoryStore({
      'projects': projects(),
      'history': history(),
      'auto_backup_folder': folder.path
    });
    StorageService.demoStore = store;
    final backup = BackupService.instance;
    final successAt = DateTime(2026, 10, 15, 10);
    expect(await backup.writeAutoBackup(now: successAt), isTrue);
    final file = File('${folder.path}/${BackupService.liveBackupFileName}');
    final original = await file.readAsBytes();
    await store.setString('history', 'damaged');
    expect(
        await backup.writeAutoBackup(
            now: successAt.add(const Duration(minutes: 1))),
        isFalse);
    expect(await backup.writeAutoBackup(), isFalse);
    expect(await file.readAsBytes(), original);
    final failed = await storage.getAutoBackupStatus();
    expect(failed['lastSuccess'], successAt.toIso8601String());
    expect(failed['error'], contains('history'));
    expect(failed['failures'], 2);
    await store.setString('history', history());
    expect(await backup.writeAutoBackup(), isTrue);
    expect((await storage.getAutoBackupStatus())['failures'], 0);
    expect((await storage.getAutoBackupStatus())['error'], isNull);
  });

  test('C8 a vanished folder has no false success and status stays local',
      () async {
    final folder = await Directory.systemTemp.createTemp('audit-gone-');
    final missingPath = '${folder.path}/missing';
    addTearDown(() => folder.delete(recursive: true));
    StorageService.demoStore = MemoryStore({'auto_backup_folder': missingPath});
    expect(await BackupService.instance.writeAutoBackup(), isFalse);
    final status = await storage.getAutoBackupStatus();
    expect(status['lastSuccess'], isNull);
    expect(status['failures'], 1);
    expect(status['error'], isNotNull);
    expect((await storage.exportAll()).toString(),
        isNot(contains('auto_backup_status')));
  });

  test('post-save hook failure cannot undo or reject durable work', () async {
    StorageService.demoStore = MemoryStore({});
    StorageService.onChanged = () async {
      throw StateError('external backup unavailable');
    };
    await storage.saveHistory([work]);
    expect((await storage.loadHistory()).single.id, work.id);
  });
  for (final deletion in [false, true]) {
    test('undo $deletion survives a merge with the corrected device', () async {
      final correction = deletion
          ? WorkCorrection.delete([work], {work.id})
          : WorkCorrection.markInvalid([work], {work.id});
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final undo = correction.undo();
      final outcome = MergeService.mergeBackup(
          localProjects: [project],
          localHistory: correction.history,
          localExpenses: [],
          incomingProjects: [project],
          incomingHistory: undo,
          incomingExpenses: []);
      final restored = outcome.history.single;
      expect(restored.isDeleted, isFalse);
      expect(restored.isInvalid, isFalse);
      expect(restored.duration, work.duration);
      expect(
          restored.lastUpdated.isAfter(correction.history.single.lastUpdated),
          isTrue);
      if (deletion) expect(restored.restoredAt, isNotNull);
    });
  }
}
