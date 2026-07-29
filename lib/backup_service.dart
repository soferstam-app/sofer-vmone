import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'logic/merge_service.dart';
import 'models.dart';
import 'platform_support.dart';
import 'storage_service.dart';

/// How a backup export ended, so the UI can report precisely.
enum BackupOutcome { success, cancelled, failed }

/// A backup file that has been read and validated but not yet applied.
///
/// Import is deliberately two steps: the user sees what a file contains and
/// confirms before anything touches their data.
class BackupPreview {
  final List<Project> projects;
  final List<WorkSession> history;
  final List<Expense> expenses;
  final Map<String, dynamic> settings;
  final Map<String, dynamic> lastPositions;

  /// When the file was exported, and from which platform. Null on files that
  /// predate those fields.
  final DateTime? exportedAt;
  final String? exportedFrom;
  final String fileName;

  const BackupPreview({
    required this.projects,
    required this.history,
    required this.expenses,
    required this.settings,
    required this.lastPositions,
    required this.fileName,
    this.exportedAt,
    this.exportedFrom,
  });
}

/// Why reading a backup file failed, so the user gets a usable message rather
/// than a stack trace.
enum BackupReadError { cancelled, unreadable, notOurFormat, tooNew }

class BackupReadResult {
  final BackupPreview? preview;
  final BackupReadError? error;

  const BackupReadResult.ok(this.preview) : error = null;
  const BackupReadResult.failed(this.error) : preview = null;

  bool get isOk => preview != null;
}

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

  /// Lets the user pick a backup file and validates it, without changing
  /// anything yet.
  Future<BackupReadResult> readBackupFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'בחירת קובץ גיבוי',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        return const BackupReadResult.failed(BackupReadError.cancelled);
      }

      final file = picked.files.first;
      final bytes = file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (bytes == null) {
        return const BackupReadResult.failed(BackupReadError.unreadable);
      }

      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        return const BackupReadResult.failed(BackupReadError.notOurFormat);
      }
      if (decoded['app'] != appId) {
        return const BackupReadResult.failed(BackupReadError.notOurFormat);
      }
      // A file written by a newer version may use fields this build does not
      // understand; refusing is safer than importing it partially.
      final version = (decoded['formatVersion'] as num?)?.toInt() ?? 0;
      if (version > formatVersion) {
        return const BackupReadResult.failed(BackupReadError.tooNew);
      }

      List<T> parse<T>(String key, T Function(Map<String, dynamic>) fromJson) {
        final raw = decoded[key];
        if (raw is! List) return <T>[];
        final out = <T>[];
        for (final item in raw) {
          // One malformed record must not lose the whole file.
          try {
            if (item is Map) out.add(fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
        return out;
      }

      return BackupReadResult.ok(BackupPreview(
        projects: parse('projects', Project.fromJson),
        history: parse('history', WorkSession.fromJson),
        expenses: parse('expenses', Expense.fromJson),
        settings: decoded['settings'] is Map
            ? Map<String, dynamic>.from(decoded['settings'])
            : const {},
        lastPositions: decoded['lastPositions'] is Map
            ? Map<String, dynamic>.from(decoded['lastPositions'])
            : const {},
        fileName: file.name,
        exportedAt: decoded['exportedAt'] is String
            ? DateTime.tryParse(decoded['exportedAt'])
            : null,
        exportedFrom: decoded['exportedFrom'] as String?,
      ));
    } catch (e) {
      debugPrint('Backup readBackupFile failed: $e');
      return const BackupReadResult.failed(BackupReadError.unreadable);
    }
  }

  /// Merges a previewed backup into the stored data.
  ///
  /// This is a merge, never a replacement: records the device already has are
  /// kept, records only in the file are added, and a record present in both is
  /// resolved by whichever was edited last. Nothing local is dropped because it
  /// is missing from the file.
  ///
  /// Settings are deliberately *not* restored — they describe how this device
  /// is set up, and silently changing them while importing work records would
  /// surprise the user.
  Future<MergeOutcome> applyBackup(BackupPreview preview) async {
    final outcome = MergeService.mergeBackup(
      localProjects: await _storage.loadProjects(),
      localHistory: await _storage.loadHistory(),
      localExpenses: await _storage.loadExpenses(),
      incomingProjects: preview.projects,
      incomingHistory: preview.history,
      incomingExpenses: preview.expenses,
    );

    await _storage.saveProjects(outcome.projects);
    await _storage.saveHistory(outcome.history);
    await _storage.saveExpenses(outcome.expenses);
    return outcome;
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
