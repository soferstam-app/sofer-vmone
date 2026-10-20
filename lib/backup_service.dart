import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'logic/legacy_import.dart';
import 'logic/merge_service.dart';
import 'logic/json_compat.dart';
import 'models.dart';
import 'platform_support.dart';
import 'storage_service.dart';
import 'version.dart' as version;

/// How a backup export ended, so the UI can report precisely.
enum BackupOutcome { success, cancelled, failed }

class _BackupDestinationConflict implements Exception {
  @override
  String toString() =>
      'The destination contains a backup with records missing from this installation. Import it first or choose another folder.';
}

/// A backup file that has been read and validated but not yet applied.
///
/// Import is deliberately two steps: the user sees what a file contains and
/// confirms before anything touches their data.
class BackupPreview {
  final List<Project> projects;
  final List<WorkSession> history;
  final List<Expense> expenses;
  final List<Proofread> proofreads;
  final List<Payment> payments;
  final List<Order> orders;
  final Map<String, dynamic> settings;
  final Map<String, dynamic> lastPositions;

  /// When the file was exported, and from which platform. Null on files that
  /// predate those fields.
  final DateTime? exportedAt;
  final String? exportedFrom;
  final String fileName;

  /// Records in the file this build could not read. Shown before the writer
  /// confirms, so a partial restore is never mistaken for a whole one.
  final int unreadable;

  const BackupPreview({
    required this.projects,
    required this.history,
    required this.expenses,
    this.proofreads = const [],
    this.payments = const [],
    this.orders = const [],
    required this.settings,
    required this.lastPositions,
    required this.fileName,
    this.exportedAt,
    this.exportedFrom,
    this.unreadable = 0,
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

  /// An independent queue/status for isolated storage and widget tests.
  @visibleForTesting
  BackupService.forTesting();

  /// Bump when the payload shape changes incompatibly. The importer will use
  /// this to decide whether it can read a given file.
  static const int formatVersion = 1;

  static const String appId = 'sofer_vmone';
  static const String liveBackupFileName = 'sofer-vmone-live.json';
  static const MethodChannel _androidChannel =
      MethodChannel('com.example.stamsofer/live_backup');

  /// Taken from the one place the version is written down. It used to be a
  /// second copy here, which is a copy that gets forgotten.
  static const String appVersion = version.appVersion;

  final StorageService _storage = StorageService();
  final ValueNotifier<Map<String, dynamic>> autoBackupStatus =
      ValueNotifier({});
  Future<void> _autoBackupQueue = Future<void>.value();

  Future<bool> writeAutoBackup({DateTime? now}) {
    final result = _autoBackupQueue.then((_) => _backupWithStatus(now: now));
    _autoBackupQueue = result.then<void>((_) {}, onError: (Object error) {});
    return result;
  }

  Future<bool> _backupWithStatus({DateTime? now}) async {
    var ok = false;
    String? folder;
    String? error;
    var needsImport = false;
    try {
      folder = await _storage.getAutoBackupFolder();
      if (folder == null) return false;
      ok = await _writeAutoBackupOnce(now: now);
      if (!ok) error = 'Backup file could not be written or verified';
    } catch (failure) {
      error = '$failure';
      needsImport = failure is _BackupDestinationConflict;
    }
    Map<String, dynamic> previous = {};
    try {
      final stored = await _storage.getAutoBackupStatus();
      if (stored['folder'] == folder) previous = stored;
    } catch (failure) {
      debugPrint('Could not read backup status: $failure');
    }
    final status = <String, dynamic>{
      ...previous,
      'folder': folder,
      'lastAttempt': (now ?? DateTime.now()).toIso8601String(),
      'error': error,
      'needsImport': needsImport,
      'failures': ok
          ? 0
          : (previous['failures'] is num
                  ? (previous['failures'] as num).toInt()
                  : 0) +
              1,
      if (ok) 'lastSuccess': (now ?? DateTime.now()).toIso8601String(),
    };
    autoBackupStatus.value = status;
    try {
      await _storage.saveAutoBackupStatus(status);
    } catch (failure) {
      debugPrint('Could not store backup status: $failure');
    }
    return ok;
  }

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
        'proofreads': (data['proofreads'] as List).length,
        'payments': (data['payments'] as List).length,
        'orders': (data['orders'] as List).length,
      },
      ...data,
    };

    // The checksum covers the complete document except this field.  It lets
    // the live writer verify a read-back before replacing the previous copy,
    // while keeping the file useful as ordinary JSON for manual restore.
    final unsigned = jsonEncode(document);
    document['checksum'] = sha256.convert(utf8.encode(unsigned)).toString();
    return const JsonEncoder.withIndent('  ').convert(document);
  }

  /// `sofer-vmone-backup-2026-07-29_1435.json` — sorts chronologically and
  /// never collides with an earlier export.
  String suggestedFileName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    // Seconds too. The stamp claimed never to collide and stopped at minutes,
    // so two exports in the same minute were handed the same name.
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'sofer-vmone-backup-$stamp.json';
  }

  /// Kept as a compatibility API for callers from the dated-file version.
  String autoBackupFileName(DateTime day) => liveBackupFileName;

  /// Writes a copy of everything into the folder the writer chose, if any.
  ///
  /// The whole of "automatic backup": he names a folder he already syncs —
  /// Dropbox, OneDrive — and the app leaves a file in it. No sync engine, no
  /// account, no server, and nothing that can be lost by this app failing.
  ///
  /// There is exactly one file in that folder. A new snapshot is written to a
  /// temporary name, read back and verified, and only then replaces the old
  /// snapshot. This keeps the migration folder small without turning a crash
  /// halfway through a write into an empty backup.
  ///
  /// Returns quietly on any failure. The folder may have been moved, unmounted
  /// or renamed since it was chosen, and none of that is a reason to interrupt
  /// someone who has just finished writing.
  Future<bool> _writeAutoBackupOnce({DateTime? now}) async {
    final folder = await _storage.getAutoBackupFolder();
    if (folder == null) return false;

    try {
      final content = await buildBackupJson();
      // Validate the document before handing it to either platform. Android
      // verifies the same checksum after reading the temporary SAF document
      // back, so a provider that truncates a write cannot replace the last
      // good migration snapshot.
      if (!_hasValidChecksum(content)) return false;
      final checksum = (jsonDecode(content) as Map)['checksum'] as String;
      if (Platform.isAndroid) {
        final previous = await _androidChannel.invokeMethod<String>(
            'readLiveBackup',
            {'folderUri': folder, 'fileName': liveBackupFileName});
        _assertSafeReplacement(previous, content);
        return await _androidChannel.invokeMethod<bool>('writeLiveBackup', {
              'folderUri': folder,
              'fileName': liveBackupFileName,
              'content': content,
              'checksum': checksum,
            }) ??
            false;
      }

      final dir = Directory(folder);
      if (!await dir.exists()) return false;
      final target = File('${dir.path}${Platform.pathSeparator}'
          '$liveBackupFileName');
      final temporary = File('${dir.path}${Platform.pathSeparator}'
          '.$liveBackupFileName.tmp');
      final previous = File('${dir.path}${Platform.pathSeparator}'
          '.$liveBackupFileName.previous');
      // Recover a valid snapshot if the process died after moving the old
      // target aside but before the replacement received its final name.
      if (!await target.exists() && await previous.exists()) {
        await previous.rename(target.path);
      }
      _assertSafeReplacement(
          await target.exists() ? await target.readAsString() : null, content);
      await temporary.writeAsString(content, flush: true);
      final written = await temporary.readAsString();
      if (written != content || !_hasValidChecksum(written)) return false;
      // Keep the last good snapshot until the replacement has completed. A
      // delete-then-rename left the migration copy empty when the process or
      // drive failed in that tiny window.
      if (await previous.exists()) await previous.delete();
      if (await target.exists()) await target.rename(previous.path);
      try {
        await temporary.rename(target.path);
      } catch (_) {
        if (await previous.exists() && !await target.exists()) {
          await previous.rename(target.path);
        }
        rethrow;
      }
      if (await previous.exists()) await previous.delete();
      await _removeLegacyDailyFiles(dir);
      return true;
    } catch (e) {
      debugPrint('Auto backup failed: $e');
      rethrow;
    }
  }

  Future<void> _removeLegacyDailyFiles(Directory dir) async {
    final legacy = RegExp(r'^sofer-vmone-\d{4}-\d{2}-\d{2}\.json$');
    await for (final entity in dir.list()) {
      if (entity is File && legacy.hasMatch(entity.uri.pathSegments.last)) {
        try {
          await entity.delete();
        } catch (_) {
          // A stale synced file is not allowed to make the fresh snapshot fail.
        }
      }
    }
  }

  bool _hasValidChecksum(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map || decoded['checksum'] is! String) return false;
      final copy = Map<String, dynamic>.from(decoded)..remove('checksum');
      final expected = sha256.convert(utf8.encode(jsonEncode(copy))).toString();
      return expected == decoded['checksum'];
    } catch (_) {
      return false;
    }
  }

  /// A folder selected by a fresh or different installation may already hold
  /// the only copy of older work. Never replace it by a subset of its records.
  /// Missing records must first be imported/merged on this device.
  void _assertSafeReplacement(String? previous, String next) {
    if (previous == null) return;
    if (!_hasValidChecksum(previous)) throw _BackupDestinationConflict();
    final oldData = jsonDecode(previous) as Map;
    final newData = jsonDecode(next) as Map;
    if (oldData['app'] != appId ||
        (JsonCompat.intOrNull(oldData['formatVersion']) ?? 0) > formatVersion) {
      throw _BackupDestinationConflict();
    }
    for (final key in const [
      'projects',
      'history',
      'expenses',
      'proofreads',
      'payments',
      'orders'
    ]) {
      final oldRows = oldData[key] ?? const [];
      final newRows = newData[key];
      if (oldRows is! List || newRows is! List) {
        throw _BackupDestinationConflict();
      }
      final newIds = {
        for (final row in newRows)
          if (row is Map && row['id'] is String) row['id']
      };
      final rawRows = newRows.map(jsonEncode).toSet();
      for (final row in oldRows) {
        final id = row is Map ? row['id'] : null;
        if (id is String
            ? !newIds.contains(id)
            : !rawRows.contains(jsonEncode(row))) {
          throw _BackupDestinationConflict();
        }
      }
    }
  }

  /// Opens Android's Storage Access Framework. The returned tree URI is a
  /// durable user grant, unlike a guessed `/storage/...` path.
  Future<String?> pickAutoBackupFolder({String? title}) async {
    if (Platform.isAndroid) {
      return _androidChannel.invokeMethod<String>('pickBackupFolder');
    }
    return FilePicker.platform.getDirectoryPath(dialogTitle: title);
  }

  /// Lets the user pick a location and writes the backup there.
  ///
  /// Desktop shows the native save dialog. Android opens the system document
  /// picker, so the file lands somewhere the user can reach over USB or in
  /// their file manager.
  Future<BackupResult> saveToDevice({bool english = false}) async {
    try {
      final content = await buildBackupJson();
      final bytes = utf8.encode(content);
      final fileName = suggestedFileName();

      final String? path = await FilePicker.platform.saveFile(
        dialogTitle: english ? 'Save backup file' : 'שמירת קובץ גיבוי',
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
  Future<BackupReadResult> readBackupFile({bool english = false}) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: english ? 'Select backup file' : 'בחירת קובץ גיבוי',
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

      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map<String, dynamic>) {
        return const BackupReadResult.failed(BackupReadError.notOurFormat);
      }

      // A file an older version left on disk rather than a backup it wrote.
      // Versions up to 0.3.1 had no backup screen, so this is the only thing
      // those writers can bring with them — see LegacyImport.
      final legacy = LegacyImport.looksLikeStore(raw);
      final decoded = legacy
          ? LegacyImport.toBackup(raw,
              appId: appId, formatVersion: formatVersion)
          : raw;

      if (decoded['app'] != appId) {
        return const BackupReadResult.failed(BackupReadError.notOurFormat);
      }
      // A file written by a newer version may use fields this build does not
      // understand; refusing is safer than importing it partially.
      final version = JsonCompat.intOrNull(decoded['formatVersion']) ?? 0;
      if (version > formatVersion) {
        return const BackupReadResult.failed(BackupReadError.tooNew);
      }
      // Every modern export carries an integrity hash. Legacy store-shaped
      // files remain accepted for compatibility, but a file claiming to be a
      // modern backup must not be merged after truncation or hand-editing.
      if (!legacy &&
          (decoded['checksum'] is! String ||
              !_hasValidChecksum(jsonEncode(decoded)))) {
        return const BackupReadResult.failed(BackupReadError.unreadable);
      }

      // Records the file holds and this build cannot read. Skipping them is
      // right — one bad record must not cost the whole file — but doing it
      // silently is not: a partial restore looked like a complete one, and a
      // writer who then deleted the original lost what was skipped.
      var unreadable = 0;

      List<T> parse<T>(String key, T Function(Map<String, dynamic>) fromJson) {
        final raw = decoded[key];
        if (raw is! List) return <T>[];
        final out = <T>[];
        for (final item in raw) {
          try {
            if (item is Map) {
              out.add(fromJson(Map<String, dynamic>.from(item)));
            } else {
              unreadable++;
            }
          } catch (_) {
            unreadable++;
          }
        }
        return out;
      }

      return BackupReadResult.ok(BackupPreview(
        projects: parse('projects', Project.fromJson),
        history: parse('history', WorkSession.fromJson),
        expenses: parse('expenses', Expense.fromJson),
        proofreads: parse('proofreads', Proofread.fromJson),
        payments: parse('payments', Payment.fromJson),
        orders: parse('orders', Order.fromJson),
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
        exportedFrom: decoded['exportedFrom'] is String
            ? decoded['exportedFrom'] as String
            : null,
        unreadable: unreadable,
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
  /// Portable user settings are restored with the records. Device-specific
  /// paths, window geometry, onboarding markers and transient timer state stay
  /// local to the receiving installation.
  Future<MergeOutcome> applyBackup(BackupPreview preview) async {
    final outcome = MergeService.mergeBackup(
      localProjects: await _storage.loadProjects(),
      localHistory: await _storage.loadHistory(),
      localExpenses: await _storage.loadExpenses(),
      incomingProjects: preview.projects,
      incomingHistory: preview.history,
      incomingExpenses: preview.expenses,
      localProofreads: await _storage.loadProofreads(),
      incomingProofreads: preview.proofreads,
      localPayments: await _storage.loadPayments(),
      incomingPayments: preview.payments,
      localOrders: await _storage.loadOrders(),
      incomingOrders: preview.orders,
    );

    await _storage.saveImportedSnapshot(
      projects: outcome.projects,
      history: outcome.history,
      expenses: outcome.expenses,
      proofreads: outcome.proofreads,
      payments: outcome.payments,
      orders: outcome.orders,
      lastPositions: preview.lastPositions,
      settings: preview.settings,
    );
    return outcome;
  }

  /// Puts the writer back where he was in each commission.
  ///
  /// The position lives beside the records rather than in them, so the merge
  /// above does not carry it — and it was read out of the file, held on the
  /// preview, and then dropped. A writer who restored two hundred pages of work
  /// got all of it back and was returned to page one, line one: the entry form
  /// suggested it and the smart workflow resumed from it, over work already
  /// done. It is the one thing a writer coming from a version with no backup
  /// screen cannot simply retype from his own records.
  ///
  /// Only ever forward, which is the rule the rest of the app already follows:
  /// an older file says nothing about where he has got to since.
  /// Writes the backup to a temporary file and hands it to the OS share sheet
  /// (WhatsApp, mail, any cloud app the user already has).
  Future<BackupResult> shareBackup({bool english = false}) async {
    File? tempFile;
    try {
      final content = await buildBackupJson();
      final dir = await getTemporaryDirectory();
      tempFile = File('${dir.path}/${suggestedFileName()}');
      await tempFile.writeAsString(content, flush: true);

      final result = await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: 'application/json')],
        subject: english ? 'Sofer v’Mone backup' : 'גיבוי סופר ומונה',
        text: english
            ? 'Backup file from the Sofer v’Mone app'
            : 'קובץ גיבוי של אפליקציית סופר ומונה',
      );

      // The temporary copy holds everything the writer has ever recorded, and
      // it was left in the temp directory after the share sheet closed.
      try {
        await tempFile.delete();
      } catch (_) {
        // The receiving app may still be reading it; the OS clears temp anyway.
      }

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
