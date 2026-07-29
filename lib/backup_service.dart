import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'platform_support.dart';
import 'storage_service.dart';

/// How a backup export ended, so the UI can report precisely.
enum BackupOutcome { success, cancelled, failed }

class BackupResult {
  final BackupOutcome outcome;

  /// Where the file was written, when the user saved to the device.
  final String? path;
  final String? error;

  const BackupResult(this.outcome, {this.path, this.error});

  bool get isSuccess => outcome == BackupOutcome.success;
}

/// Builds and exports a single backup file containing every piece of user data.
///
/// The same document is used for saving to the device and for sharing, and is
/// the format the (planned) import will read. Keep [formatVersion] in step with
/// any breaking change to the payload shape.
class BackupService {
  static final BackupService instance = BackupService._internal();
  BackupService._internal();

  /// Bump when the payload shape changes incompatibly. The importer will use
  /// this to decide whether it can read a given file.
  static const int formatVersion = 1;

  static const String appId = 'sofer_vmone';
  static const String appVersion = '0.4.0';

  final StorageService _storage = StorageService();

  /// The complete backup document, pretty-printed so a user who opens the file
  /// can see what it holds.
  Future<String> buildBackupJson() async {
    final data = await _storage.exportAll();

    final document = <String, dynamic>{
      'app': appId,
      'formatVersion': formatVersion,
      'appVersion': appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'exportedFrom': PlatformSupport.name,
      // Counts are metadata only — the importer must not trust them, but they
      // let a user sanity-check a file before restoring it.
      'counts': {
        'projects': (data['projects'] as List).length,
        'history': (data['history'] as List).length,
        'expenses': (data['expenses'] as List).length,
      },
      ...data,
    };

    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// `sofer-vmone-backup-2026-07-29_1435.json` — sorts chronologically and
  /// never collides with an earlier export.
  String suggestedFileName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}';
    return 'sofer-vmone-backup-$stamp.json';
  }

  /// Lets the user pick a location and writes the backup there.
  ///
  /// Desktop shows the native save dialog. Android opens the system document
  /// picker, so the file lands somewhere the user can reach over USB or in
  /// their file manager.
  Future<BackupResult> saveToDevice() async {
    try {
      final content = await buildBackupJson();
      final bytes = utf8.encode(content);
      final fileName = suggestedFileName();

      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: 'שמירת קובץ גיבוי',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        // Android needs the bytes up front; desktop returns a path and we
        // write it ourselves below.
        bytes: PlatformSupport.isMobile ? bytes : null,
      );

      if (path == null) return const BackupResult(BackupOutcome.cancelled);

      // On desktop file_picker only returns the chosen path.
      if (!PlatformSupport.isMobile) {
        final file = File(path);
        await file.writeAsBytes(bytes, flush: true);
      }

      return BackupResult(BackupOutcome.success, path: path);
    } catch (e) {
      debugPrint('Backup saveToDevice failed: $e');
      return BackupResult(BackupOutcome.failed, error: e.toString());
    }
  }

  /// Writes the backup to a temporary file and hands it to the OS share sheet
  /// (WhatsApp, mail, any cloud app the user already has).
  Future<BackupResult> shareBackup() async {
    File? tempFile;
    try {
      final content = await buildBackupJson();
      final dir = await getTemporaryDirectory();
      tempFile = File('${dir.path}/${suggestedFileName()}');
      await tempFile.writeAsString(content, flush: true);

      final result = await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: 'application/json')],
        subject: 'גיבוי סופר ומונה',
        text: 'קובץ גיבוי של אפליקציית סופר ומונה',
      );

      if (result.status == ShareResultStatus.dismissed) {
        return const BackupResult(BackupOutcome.cancelled);
      }
      return BackupResult(BackupOutcome.success, path: tempFile.path);
    } catch (e) {
      debugPrint('Backup shareBackup failed: $e');
      return BackupResult(BackupOutcome.failed, error: e.toString());
    }
  }
}
