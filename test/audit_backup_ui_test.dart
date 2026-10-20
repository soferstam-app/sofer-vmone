import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/settings_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

class DirectoryPicker extends FilePicker {
  final String path;
  DirectoryPicker(this.path);
  @override
  Future<String?> getDirectoryPath(
          {String? dialogTitle,
          bool lockParentWindow = false,
          String? initialDirectory}) async =>
      path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FilePicker? previous;
  setUp(() {
    try {
      previous = FilePicker.platform;
    } catch (_) {
      previous = null;
    }
    StorageService.demoStore = MemoryStore({});
    StorageService.onChanged = null;
    BackupService.instance.autoBackupStatus.value = {};
  });
  tearDown(() {
    if (previous != null) FilePicker.platform = previous!;
    StorageService.demoStore = null;
    StorageService.onChanged = null;
  });
  for (final theme in [AppTheme.modern, AppTheme.klaf]) {
    for (final valid in [false, true]) {
      testWidgets(
          'C8 first backup in $theme reports the actual write outcome valid=$valid',
          (tester) async {
        final root = Directory.systemTemp.createTempSync('backup-ui-');
        addTearDown(() => root.deleteSync(recursive: true));
        final path = valid ? root.path : '${root.path}/gone';
        FilePicker.platform = DirectoryPicker(path);
        tester.view.physicalSize = const Size(1000, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
            theme: AppThemeBuilder.build(theme),
            home: const Directionality(
                textDirection: TextDirection.rtl, child: SettingsScreen())));
        await tester.pumpAndSettle();
        final row = find.textContaining('גיבוי אוטומטי').first;
        await tester.ensureVisible(row);
        await tester.runAsync(() async {
          await tester.tap(row);
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        final status = await StorageService().getAutoBackupStatus();
        expect(await StorageService().getAutoBackupFolder(), path);
        if (valid) {
          expect(status['lastSuccess'], isA<String>());
          expect(status['error'], isNull);
          expect(File('$path/${BackupService.liveBackupFileName}').existsSync(),
              isTrue);
          expect(find.textContaining('גיבוי אוטומטי הופעל'), findsOneWidget);
        } else {
          expect(status['lastSuccess'], isNull);
          expect(status['error'], isNotNull);
          expect(find.textContaining('הגיבוי הראשון נכשל'), findsOneWidget);
          expect(find.textContaining('גיבוי אוטומטי הופעל'), findsNothing);
          expect(find.textContaining('הגיבוי האחרון נכשל'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
