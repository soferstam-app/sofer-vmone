// Where the writer had got to, after a restore.
//
// A backup carries three lists of records and one thing that is not a record:
// the page and line each commission is up to. It was written into the file,
// read back out of it, put on the preview — and then never applied. So a
// restore returned every page of work and sent the writer back to page one:
// the entry form suggested it, and the smart workflow resumed from there, over
// writing he had already done.
//
// It is also the one thing a writer coming from 0.3.x cannot retype from his
// own records, because it is the app's answer to "where was I".

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();

  BackupPreview preview(Map<String, dynamic> positions) => BackupPreview(
        projects: const [],
        history: const [],
        expenses: const [],
        settings: const {},
        lastPositions: positions,
        fileName: 'backup.json',
        exportedAt: null,
        exportedFrom: null,
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the place in each commission comes back with the records', () async {
    await BackupService.instance.applyBackup(preview({
      'p1': {'page': 12, 'line': 7},
      'p2': {'page': 3, 'line': 1},
    }));

    expect(await storage.getLastPosition('p1'), {'page': 12, 'line': 7});
    expect(await storage.getLastPosition('p2'), {'page': 3, 'line': 1});
  });

  test('an older file never rewinds a place already further on', () async {
    // The same rule a manual entry follows: filling in an earlier gap does not
    // move the writer backwards.
    await storage.saveLastPosition('p1', 40, 20);
    await BackupService.instance.applyBackup(preview({
      'p1': {'page': 12, 'line': 7},
    }));

    expect(await storage.getLastPosition('p1'), {'page': 40, 'line': 20});
  });

  test('but it does carry one further on than the device has', () async {
    await storage.saveLastPosition('p1', 5, 3);
    await BackupService.instance.applyBackup(preview({
      'p1': {'page': 5, 'line': 9},
    }));

    expect(await storage.getLastPosition('p1'), {'page': 5, 'line': 9});
  });

  group('a file that is damaged', () {
    test('a position that is not a position is skipped, not thrown on', () async {
      await BackupService.instance.applyBackup(preview({
        'p1': 'nonsense',
        'p2': {'page': 'twelve', 'line': 7},
        'p3': {'line': 7},
        'p4': {'page': 9, 'line': 2},
      }));

      // The readable one still came across.
      expect(await storage.getLastPosition('p4'), {'page': 9, 'line': 2});
      for (final id in ['p1', 'p2', 'p3']) {
        expect(await storage.getLastPosition(id), isEmpty);
      }
    });

    test('counting starts at one, so a zero is not restored', () async {
      await BackupService.instance.applyBackup(preview({
        'p1': {'page': 0, 'line': 0},
      }));
      expect(await storage.getLastPosition('p1'), isEmpty);
    });

    test('no positions at all is not an error', () async {
      await BackupService.instance.applyBackup(preview(const {}));
      expect(await storage.getLastPosition('p1'), isEmpty);
    });
  });

  group('stored positions that cannot be read', () {
    test('reading gives nothing rather than throwing', () async {
      SharedPreferences.setMockInitialValues(
          {'flutter.last_positions': 'not json at all'});
      expect(await storage.getLastPosition('p1'), isEmpty);
    });

    test('a list where a map belongs gives nothing', () async {
      SharedPreferences.setMockInitialValues(
          {'flutter.last_positions': '[1,2,3]'});
      expect(await storage.getLastPosition('p1'), isEmpty);
    });

    test('a value of the wrong shape gives nothing', () async {
      SharedPreferences.setMockInitialValues(
          {'flutter.last_positions': '{"p1": 5}'});
      expect(await storage.getLastPosition('p1'), isEmpty);
    });

    test('saving over an unreadable file works rather than failing', () async {
      SharedPreferences.setMockInitialValues(
          {'flutter.last_positions': 'not json at all'});
      await storage.saveLastPosition('p1', 4, 2);
      expect(await storage.getLastPosition('p1'), {'page': 4, 'line': 2});
    });
  });
}
