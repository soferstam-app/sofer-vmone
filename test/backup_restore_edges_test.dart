import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/settings_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

import 'support/fault_store.dart';

class BackupBytesPicker extends FilePicker {
  BackupBytesPicker(Map<String, dynamic> content)
      : bytes = Uint8List.fromList(utf8.encode(jsonEncode(content)));

  final Uint8List bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        PlatformFile(name: 'backup.json', size: bytes.length, bytes: bytes),
      ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 11, 9, 9);
  final storage = StorageService();
  final payment =
      Payment(id: 'pay', projectId: 'p', amount: 55, receivedAt: date);
  final proofread = Proofread(id: 'r', projectId: 'p', scope: 'עמוד 2');
  final order = Order(
      id: 'o',
      customerName: 'לקוח',
      orderedAt: date,
      dueDate: date,
      lastUpdated: date);
  final legacy = <String, dynamic>{
    'flutter.payments': jsonEncode([payment.toJson()]),
    'flutter.proofreads': jsonEncode([proofread.toJson()]),
    'flutter.orders': jsonEncode([order.toJson()]),
    'flutter.app_language': 'he',
  };
  FilePicker? originalPicker;
  setUpAll(() async {
    for (final font in ['Heebo', 'FrankRuhlLibre']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font-var.ttf')))
          .load();
    }
  });
  setUp(() {
    try {
      originalPicker = FilePicker.platform;
    } catch (_) {}
    StorageService.demoStore = MemoryStore({});
  });
  tearDown(() {
    if (originalPicker != null) FilePicker.platform = originalPicker!;
    StorageService.demoStore = null;
    StorageService.onChanged = null;
  });

  test('legacy file survives preview, restore, export and repeated restore',
      () async {
    final service = BackupService.forTesting();
    FilePicker.platform = BackupBytesPicker(legacy);
    final preview = (await service.readBackupFile()).preview!;
    expect(preview.unreadableSections, 0);
    expect(preview.payments.single.id, payment.id);
    expect(preview.proofreads.single.id, proofread.id);
    expect(preview.orders.single.id, order.id);
    await service.applyBackup(preview);
    final exported =
        jsonDecode(await service.buildBackupJson()) as Map<String, dynamic>;
    FilePicker.platform = BackupBytesPicker(exported);
    final repeated = (await service.readBackupFile()).preview!;
    final result = await service.applyBackup(repeated);
    expect(result.changedAnything, isFalse);
    expect((await storage.loadPayments()).single.toJson(), payment.toJson());
    expect(
        (await storage.loadProofreads()).single.toJson(), proofread.toJson());
    expect((await storage.loadOrders()).single.toJson(), order.toJson());
  });

  test('damaged legacy sections are reported independently of damaged rows',
      () async {
    FilePicker.platform = BackupBytesPicker({
      ...legacy,
      'flutter.payments': '{truncated',
      'flutter.last_positions': '[]',
      'flutter.orders': jsonEncode([order.toJson(), 'unreadable row']),
    });
    final preview =
        (await BackupService.forTesting().readBackupFile()).preview!;
    expect(preview.unreadableSections, 2);
    expect(preview.unreadable, 1);
    expect(preview.payments, isEmpty);
    expect(preview.orders.single.id, order.id);
    expect(preview.proofreads.single.id, proofread.id);
  });

  test(
      'a prefixed key cannot turn a modern backup into an unchecked legacy file',
      () async {
    final service = BackupService.forTesting();
    final document = <String, dynamic>{
      'app': BackupService.appId,
      'formatVersion': BackupService.formatVersion,
      'payments': [payment.toJson()],
      'flutter.app_language': 'he',
    };
    FilePicker.platform = BackupBytesPicker(document);
    expect((await service.readBackupFile()).error, BackupReadError.unreadable);

    document['formatVersion'] = BackupService.formatVersion + 1;
    FilePicker.platform = BackupBytesPicker(document);
    expect((await service.readBackupFile()).error, BackupReadError.tooNew);

    document['formatVersion'] = BackupService.formatVersion;
    document['checksum'] =
        sha256.convert(utf8.encode(jsonEncode(document))).toString();
    FilePicker.platform = BackupBytesPicker(document);
    expect((await service.readBackupFile()).preview!.payments.single.id,
        payment.id);
  });

  testWidgets('restore failure is visible and retry works in a narrow window',
      (tester) async {
    final store = FaultStore({})..arm('payments');
    StorageService.demoStore = store;
    FilePicker.platform =
        BackupBytesPicker({...legacy, 'flutter.history': '{broken'});
    tester.view.physicalSize = const Size(390, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.modern),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: const Directionality(
          textDirection: TextDirection.rtl, child: SettingsScreen()),
    ));
    await tester.pumpAndSettle();

    Future<void> openRestore() async {
      final entry = find.text('גיבוי הנתונים');
      // This settings entry is below the fold in a narrow window.
      await tester.scrollUntilVisible(entry, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final restore = find.text('שחזור מקובץ גיבוי');
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      // The settings progress indicator keeps ticking behind the preview.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final warning = find.textContaining('חלקים בקובץ אינם ניתנים לקריאה');
      await tester.ensureVisible(warning);
      expect(warning, findsOneWidget);
    }

    Future<void> confirm() async {
      await tester.tap(find.text('שחזר'));
      await tester.pump();
      // The import awaits the storage queue while this test drives frames.
      for (var attempt = 0; attempt < 30; attempt++) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
    }

    await openRestore();
    await confirm();
    expect(find.text('שחזור הגיבוי לא הושלם. אפשר לנסות שוב.'), findsOneWidget);
    expect(await storage.loadPayments(), isEmpty);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await openRestore();
    await confirm();
    expect((await storage.loadPayments()).single.id, payment.id);
    expect(find.textContaining('1 תשלומים'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
