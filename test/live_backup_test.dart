import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/storage_service.dart';

void main() {
  late Directory folder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StorageService.demoStore = null;
    StorageService.onChanged = null;
    folder = await Directory.systemTemp.createTemp('sofer-live-backup-');
  });

  tearDown(() async {
    StorageService.onChanged = null;
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  test('writes one verified live snapshot and replaces it', () async {
    final storage = StorageService();
    await storage.setAutoBackupFolder(folder.path);

    expect(await BackupService.instance.writeAutoBackup(), isTrue);
    final first = File('${folder.path}${Platform.pathSeparator}'
        '${BackupService.liveBackupFileName}');
    expect(await first.exists(), isTrue);
    final firstJson = jsonDecode(await first.readAsString()) as Map;
    expect(firstJson['checksum'], isA<String>());
    await File('${folder.path}${Platform.pathSeparator}'
            'sofer-vmone-2026-08-24.json')
        .writeAsString('old');

    await storage.setSoferName('כותב');
    expect(await BackupService.instance.writeAutoBackup(), isTrue);
    final files = await folder.list().toList();
    expect(files.whereType<File>().map((f) => f.path), contains(first.path));
    expect(files.whereType<File>().length, 1);
    expect(
        files.whereType<File>().any((f) => f.path.endsWith('2026-08-24.json')),
        isFalse);
    final secondJson = jsonDecode(await first.readAsString()) as Map;
    expect((secondJson['settings'] as Map)['sofer_name'], 'כותב');
  });
}
