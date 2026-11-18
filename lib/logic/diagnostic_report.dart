import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sofer_voice_model/sofer_voice_model.dart'
    show voiceModelIncluded;

import '../platform_support.dart';
import '../storage_service.dart';
import '../version.dart';

enum DiagnosticEvent {
  appStarted,
  startupFailed,
  flutterError,
  unhandledDartError,
  planDayTapped,
  planDayDialogShown,
  planDaySaveStarted,
  planDaySaved,
  planDayFailed,
  entrySaveStarted,
  entrySaved,
  entrySaveFailed,
}

/// The files live outside the database so a damaged database can still be
/// diagnosed. There is one writer, and complete records are flushed before
/// entering the instrumented UI paths.
class DiagnosticJournal {
  DiagnosticJournal(this.directory, {this.maxFileBytes = 128 * 1024});

  final Directory directory;
  final int maxFileBytes;
  Future<void> _pending = Future.value();
  File get _current => File('${directory.path}/events.jsonl');
  File get _previous => File('${directory.path}/events.previous.jsonl');

  Future<void> record(DiagnosticEvent event,
      {Object? error, StackTrace? stack}) {
    final entry = jsonEncode({
      'at': DateTime.now().toUtc().toIso8601String(),
      'version': appVersion,
      'event': event.name,
      if (error != null) 'errorType': error.runtimeType.toString(),
      if (stack != null)
        'frames':
            stack.toString().split('\n').where(_isDartFrame).take(30).toList(),
    });
    // A leading newline also isolates the next record after a torn append.
    final bytes = utf8.encode('\n$entry\n');
    _pending = _pending.then((_) async {
      try {
        final current = _current;
        if (await current.exists() &&
            await current.length() + bytes.length > maxFileBytes) {
          final previous = _previous;
          if (await previous.exists()) await previous.delete();
          await current.rename(previous.path);
        }
        await current.writeAsBytes(bytes, mode: FileMode.append, flush: true);
      } on FileSystemException {
        // Diagnostics must not prevent or delay recovery from a storage error.
      }
    });
    return _pending;
  }

  static bool _isDartFrame(String line) =>
      line.length <= 512 &&
      (line.contains('(package:') || line.contains('(dart:'));

  Future<List<Map<String, dynamic>>> read() {
    final snapshot = _pending.then((_) async {
      final events = <Map<String, dynamic>>[];
      for (final file in [_previous, _current]) {
        if (!await file.exists()) continue;
        final text =
            utf8.decode(await file.readAsBytes(), allowMalformed: true);
        for (final line in const LineSplitter().convert(text)) {
          if (line.isEmpty) continue;
          try {
            final value = jsonDecode(line);
            if (value is Map<String, dynamic>) events.add(value);
          } on FormatException {
            // A process exit during a write can leave an incomplete record.
          }
        }
      }
      return events;
    });
    _pending =
        snapshot.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return snapshot;
  }
}

abstract final class Diagnostics {
  static DiagnosticJournal? _journal;
  static bool get supported =>
      PlatformSupport.isAndroid || PlatformSupport.isWindows;

  static Future<void> initialize() async {
    if (!supported || _journal != null) return;
    try {
      final support = await getApplicationSupportDirectory();
      final directory = await Directory('${support.path}/diagnostics')
          .create(recursive: true);
      _journal = DiagnosticJournal(directory);
    } catch (_) {
      return;
    }

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(record(DiagnosticEvent.flutterError,
          error: details.exception, stack: details.stack));
      previousFlutterHandler?.call(details);
    };
    final dispatcher = PlatformDispatcher.instance;
    final previousDartHandler = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      unawaited(record(DiagnosticEvent.unhandledDartError,
          error: error, stack: stack));
      return previousDartHandler?.call(error, stack) ?? false;
    };
    await record(DiagnosticEvent.appStarted);
  }

  static Future<void> record(DiagnosticEvent event,
          {Object? error, StackTrace? stack}) =>
      _journal?.record(event, error: error, stack: stack) ?? Future.value();

  static Future<Uint8List> export({required bool includeWorkData}) async {
    final workData = includeWorkData
        ? await StorageService().exportAllAfterPendingWrites()
        : null;
    final events = await _journal?.read();
    final nativeCrashes =
        PlatformSupport.isWindows ? await _windowsCrashes() : null;
    return Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'format': 'sofer-vmone-diagnostic-report',
      'formatVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'appVersion': appVersion,
      'appBuild': appBuildNumber,
      'platform': PlatformSupport.name,
      'osVersion': Platform.operatingSystemVersion,
      'withVoiceModel': voiceModelIncluded,
      'journalAvailable': events != null,
      'events': events ?? [],
      if (nativeCrashes != null) 'windowsCrashes': nativeCrashes,
      if (workData != null)
        'workData': {
          for (final key in const [
            'projects',
            'history',
            'expenses',
            'proofreads',
            'payments',
            'orders',
            'lastPositions',
            'migrationRecovery',
          ])
            key: workData[key],
          'settings': {...workData['settings'] as Map<String, dynamic>}
            ..remove('auto_backup_folder'),
        },
    })));
  }

  static Future<List<dynamic>?> _windowsCrashes() async {
    // Query by app name and export only technical fields. Application Error's
    // full XML would also include file paths, the computer name and other apps.
    const script = r'''
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$crashes = @(Get-WinEvent -FilterHashtable @{
  LogName='Application'; ProviderName='Application Error'; ID=1000
  StartTime=(Get-Date).AddDays(-14)
} -MaxEvents 300 -ErrorAction SilentlyContinue | ForEach-Object {
  $fields = @{}
  foreach ($field in ([xml]$_.ToXml()).Event.EventData.Data) {
    if ($field.Name) { $fields[$field.Name] = $field.'#text' }
  }
  if ($fields.AppName -eq $env:SOFER_DIAGNOSTIC_EXE) {
    [ordered]@{at=$_.TimeCreated.ToUniversalTime().ToString('o');
      appVersion=$fields.AppVersion; module=$fields.ModuleName;
      code=$fields.ExceptionCode; offset=$fields.FaultingOffset}
  }
} | Select-Object -First 10)
ConvertTo-Json -InputObject $crashes -Compress
''';
    try {
      final systemRoot = Platform.environment['SystemRoot'];
      if (systemRoot == null) return null;
      final result = await Process.run(
        '$systemRoot/System32/WindowsPowerShell/v1.0/powershell.exe',
        ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script],
        environment: {
          'SOFER_DIAGNOSTIC_EXE':
              File(Platform.resolvedExecutable).uri.pathSegments.last,
        },
        stdoutEncoding: utf8,
      ).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return null;
      final decoded = jsonDecode(result.stdout as String);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
