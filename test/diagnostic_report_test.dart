import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/diagnostic_report.dart';
import 'package:sofer_vmone/settings/diagnostic_report_dialog.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/version.dart';

class _ReportFilePicker extends FilePicker {
  _ReportFilePicker(this.path);

  final String path;

  @override
  Future<String?> saveFile(
          {String? dialogTitle,
          String? fileName,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Uint8List? bytes,
          bool lockParentWindow = false}) async =>
      path;
}

void main() {
  test('journal keeps recent events across restarts with bounded files',
      () async {
    final folder = await Directory.systemTemp.createTemp('sofer-journal-test-');
    addTearDown(() => folder.delete(recursive: true));
    final journal = DiagnosticJournal(folder, maxFileBytes: 256);
    for (var i = 0; i < 12; i++) {
      await journal.record(DiagnosticEvent.planDayTapped);
    }
    await journal.record(DiagnosticEvent.planDaySaved);

    final reopened = DiagnosticJournal(folder, maxFileBytes: 256);
    final events = await reopened.read();
    expect(events.length, lessThan(13));
    expect(events.last['event'], 'planDaySaved');
    final files = await folder.list().where((file) => file is File).toList();
    expect(files, hasLength(2));
    for (final file in files.cast<File>()) {
      expect(await file.length(), lessThanOrEqualTo(256));
    }
  });

  test('torn appends are ignored and the next error retains its Dart frame',
      () async {
    final folder = await Directory.systemTemp.createTemp('sofer-journal-test-');
    addTearDown(() => folder.delete(recursive: true));
    final journal = DiagnosticJournal(folder);
    await journal.record(DiagnosticEvent.appStarted);
    await File('${folder.path}/events.jsonl')
        .writeAsString('{"broken":', mode: FileMode.append);
    await journal.record(DiagnosticEvent.flutterError,
        error: StateError('private user text'),
        stack: StackTrace.fromString(
            '#0 open (package:sofer_vmone/main.dart:12:3)\n/home/private/data'));
    final events = await journal.read();
    expect(
        events.map((event) => event['event']), ['appStarted', 'flutterError']);
    expect(events.last['errorType'], 'StateError');
    expect(events.last['frames'],
        ['#0 open (package:sofer_vmone/main.dart:12:3)']);
    expect(jsonEncode(events), isNot(contains('private')));
  });

  test('report can include work data and omits the local backup path',
      () async {
    StorageService.demoStore = MemoryStore({
      'projects': '[{"id":"p","name":"ספר לבדיקה"}]',
      'history': '[{"id":"h","projectId":"p","amount":3}]',
      'orders': '[{"id":"o","client":"לקוח לבדיקה"}]',
      'auto_backup_folder': 'private/local/path',
      'access_token': 'do not export',
    });
    addTearDown(() => StorageService.demoStore = null);
    final bytes = await Diagnostics.export(includeWorkData: true);
    final text = utf8.decode(bytes);
    final report = jsonDecode(text) as Map<String, dynamic>;
    expect(report['appVersion'], appVersion);
    expect(report['appBuild'], appBuildNumber);
    expect(report['workData']['projects'].single['name'], 'ספר לבדיקה');
    expect(report['workData']['history'].single['amount'], 3);
    expect(report['workData']['orders'].single['client'], 'לקוח לבדיקה');
    expect(text, isNot(contains('private/local/path')));
    expect(text, isNot(contains('do not export')));
  });

  test('technical-only export works when the work database cannot be read',
      () async {
    StorageService.demoStore = MemoryStore({'projects': '{corrupt'});
    addTearDown(() => StorageService.demoStore = null);
    final report = jsonDecode(
        utf8.decode(await Diagnostics.export(includeWorkData: false))) as Map;
    expect(report.containsKey('workData'), isFalse);
    expect(report['formatVersion'], 1);
  });

  testWidgets('the export picker runs only after the user chooses to save',
      (tester) async {
    final folder = Directory.systemTemp.createTempSync('sofer-report-test-');
    addTearDown(() => folder.delete(recursive: true));
    final output = File('${folder.path}/report.json');
    FilePicker.platform = _ReportFilePicker(output.path);
    StorageService.demoStore =
        MemoryStore({'projects': '[{"id":"p","name":"test"}]'});
    addTearDown(() => StorageService.demoStore = null);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () => showDiagnosticReportDialog(context),
          child: const Text('open')),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(output.existsSync(), isFalse);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    await tester.runAsync(() async {
      await tester.tap(find.text('שמור דוח'));
      for (var attempt = 0; attempt < 120 && !output.existsSync(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final data = jsonDecode(await output.readAsString()) as Map;
      expect(data['workData']['projects'].single['name'], 'test');
    });
    await tester.pumpAndSettle();
    expect(find.text('דוח התקלה נשמר.'), findsOneWidget);
  });
}
