import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';

import 'update_service.dart';

/// Hands an authenticated artifact to the operating system, or stages a
/// rollback-capable replacement for the portable Windows package.
class UpdateInstaller {
  static const MethodChannel _androidChannel =
      MethodChannel('com.example.stamsofer/update');

  const UpdateInstaller();

  Future<void> install(DownloadedUpdate update, {bool english = false}) async {
    if (Platform.isAndroid) {
      await _installAndroid(update, english: english);
      return;
    }
    if (Platform.isWindows) {
      await _installWindows(update, english: english);
      return;
    }
    throw UpdateException(english
        ? 'Direct updates are currently supported only on Android and Windows'
        : 'עדכון ישיר נתמך כרגע רק ב־Android וב־Windows');
  }

  Future<void> _installAndroid(DownloadedUpdate update,
      {required bool english}) async {
    try {
      await _androidChannel.invokeMethod<void>(
        'installApk',
        <String, Object>{'path': update.file.path},
      );
    } on PlatformException catch (error) {
      throw UpdateException(
        error.message ??
            (english
                ? 'Android could not open the update installer'
                : 'Android לא הצליח לפתוח את מתקין העדכון'),
        error,
      );
    } on MissingPluginException catch (error) {
      throw UpdateException(
          english
              ? 'The Android installer is unavailable in this version'
              : 'רכיב ההתקנה של Android אינו זמין בגרסה זו',
          error);
    }
  }

  Future<void> _installWindows(DownloadedUpdate update,
      {required bool english}) async {
    final root = update.workingDirectory;
    final staged =
        Directory('${root.path}${Platform.pathSeparator}staged-package');
    final backup =
        Directory('${root.path}${Platform.pathSeparator}previous-package');
    final acknowledgement =
        File('${root.path}${Platform.pathSeparator}new-version-ready');
    final errorLog =
        File('${root.path}${Platform.pathSeparator}update-error.txt');
    final scriptFile =
        File('${root.path}${Platform.pathSeparator}apply-update.ps1');

    try {
      await staged.create(recursive: true);
      await extractFileToDisk(
        update.file.path,
        staged.path,
        asyncWrite: true,
      );

      final currentExecutable = File(Platform.resolvedExecutable);
      final executableName = _baseName(currentExecutable.path);
      final stagedExecutable =
          await _findUniqueFile(staged, executableName, english: english);
      final packageRoot = stagedExecutable.parent;
      await _validateWindowsPackage(packageRoot, executableName,
          english: english);

      final installationDirectory = currentExecutable.parent;
      await _assertWritable(installationDirectory, english: english);

      final script = buildWindowsUpdateScript(
        sourceDirectory: packageRoot.path,
        targetDirectory: installationDirectory.path,
        backupDirectory: backup.path,
        workingDirectory: root.path,
        acknowledgementPath: acknowledgement.path,
        errorLogPath: errorLog.path,
        executableName: executableName,
        currentProcessId: pid,
      );

      // Windows PowerShell 5 reads a BOM-less UTF-8 script as the local ANSI
      // code page. The executable has a Hebrew name, so the BOM is functional,
      // not cosmetic.
      await scriptFile.writeAsBytes(
        <int>[0xef, 0xbb, 0xbf, ...utf8.encode(script)],
        flush: true,
      );

      await Process.start(
        'powershell.exe',
        <String>[
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          scriptFile.path,
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      // The detached process has its own copy of the paths and is now waiting
      // for this PID. Only now is it safe for the live application to leave.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      exit(0);
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException(
          english
              ? 'The Windows update could not be prepared. The existing installation was not changed'
              : 'לא ניתן להכין את עדכון Windows. ההתקנה הקיימת לא שונתה',
          error);
    }
  }

  static Future<File> _findUniqueFile(Directory directory, String fileName,
      {required bool english}) async {
    final matches = <File>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && _baseName(entity.path) == fileName) {
        matches.add(entity);
      }
    }
    if (matches.length != 1) {
      throw UpdateException(english
          ? 'The Windows package does not contain exactly one executable named $fileName'
          : 'חבילת Windows אינה מכילה קובץ הפעלה יחיד בשם $fileName');
    }
    return matches.single;
  }

  static Future<void> _validateWindowsPackage(
      Directory packageRoot, String executableName,
      {required bool english}) async {
    final separator = Platform.pathSeparator;
    for (final relative in <String>[
      executableName,
      'flutter_windows.dll',
      'data${separator}app.so',
      'data${separator}icudtl.dat',
    ]) {
      if (!await File('${packageRoot.path}$separator$relative').exists()) {
        throw UpdateException(english
            ? 'The Windows package is missing $relative'
            : 'חבילת Windows חסרה את $relative');
      }
    }
  }

  static Future<void> _assertWritable(Directory directory,
      {required bool english}) async {
    final probe = File(
        '${directory.path}${Platform.pathSeparator}.sofer-update-write-test-$pid');
    try {
      await probe.writeAsString('update preflight', flush: true);
      await probe.delete();
    } catch (error) {
      try {
        if (await probe.exists()) await probe.delete();
      } catch (_) {}
      throw UpdateException(
          english
              ? 'The app folder is not writable. Move the entire app folder to a regular location and try again'
              : 'אין הרשאת כתיבה לתיקיית התוכנה. העבר את כל תיקיית התוכנה למיקום רגיל ונסה שוב',
          error);
    }
  }

  static String _baseName(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}

String _powerShellLiteral(String value) => "'${value.replaceAll("'", "''")}'";

/// Builds the detached Windows updater.
///
/// It waits for the live process, backs up only package entries that are about
/// to be replaced, starts the new version, and accepts it only after that
/// version renders its first frame and writes the acknowledgement file. Any
/// failure restores the previous files and reopens the previous version.
String buildWindowsUpdateScript({
  required String sourceDirectory,
  required String targetDirectory,
  required String backupDirectory,
  required String workingDirectory,
  required String acknowledgementPath,
  required String errorLogPath,
  required String executableName,
  required int currentProcessId,
  int readinessTimeoutSeconds = 45,
}) {
  const template = r'''
$ErrorActionPreference = 'Stop'
$source = __SOURCE__
$target = __TARGET__
$backup = __BACKUP__
$working = __WORKING__
$acknowledgement = __ACK__
$errorLog = __ERROR_LOG__
$executableName = __EXE_NAME__
$currentProcessId = __PID__
$items = @()
$backupReady = $false
$newProcess = $null

try {
    $oldProcess = Get-Process -Id $currentProcessId -ErrorAction SilentlyContinue
    if ($null -ne $oldProcess) {
        $oldProcess | Wait-Process -Timeout 120 -ErrorAction SilentlyContinue
    }
    if ($null -ne (Get-Process -Id $currentProcessId -ErrorAction SilentlyContinue)) {
        throw 'The running application did not close in time.'
    }

    $items = @(Get-ChildItem -LiteralPath $source -Force)
    if ($items.Count -eq 0) {
        throw 'The staged update package is empty.'
    }

    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($item in $items) {
        $destination = Join-Path $target $item.Name
        if (Test-Path -LiteralPath $destination) {
            Copy-Item -LiteralPath $destination -Destination $backup -Recurse -Force
        }
    }
    $backupReady = $true

    foreach ($item in $items) {
        $destination = Join-Path $target $item.Name
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Recurse -Force
        }
        Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
    }

    $env:SOFER_UPDATE_READY = $acknowledgement
    $newExecutable = Join-Path $target $executableName
    $newProcess = Start-Process -FilePath $newExecutable -WorkingDirectory $target -PassThru
    $deadline = (Get-Date).AddSeconds(__READY_SECONDS__)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $acknowledgement)) {
        if ($newProcess.HasExited) { break }
        Start-Sleep -Milliseconds 250
        $newProcess.Refresh()
    }
    if (-not (Test-Path -LiteralPath $acknowledgement)) {
        throw 'The new version did not report a successful first frame.'
    }

    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $working -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}
catch {
    $failure = $_.Exception.Message
    try {
        if ($null -ne $newProcess -and -not $newProcess.HasExited) {
            Stop-Process -Id $newProcess.Id -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $newProcess.Id -Timeout 15 -ErrorAction SilentlyContinue
        }
        if ($backupReady) {
            foreach ($item in $items) {
                $destination = Join-Path $target $item.Name
                if (Test-Path -LiteralPath $destination) {
                    Remove-Item -LiteralPath $destination -Recurse -Force
                }
            }
            foreach ($item in @(Get-ChildItem -LiteralPath $backup -Force)) {
                Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
            }
        }
    }
    catch {
        $failure = $failure + [Environment]::NewLine + 'Rollback: ' + $_.Exception.Message
    }

    Set-Content -LiteralPath $errorLog -Value $failure -Encoding UTF8
    $env:SOFER_UPDATE_READY = $null
    $env:SOFER_UPDATE_ERROR = $errorLog
    $oldExecutable = Join-Path $target $executableName
    Start-Process -FilePath $oldExecutable -WorkingDirectory $target
    exit 1
}
''';

  return template
      .replaceAll('__SOURCE__', _powerShellLiteral(sourceDirectory))
      .replaceAll('__TARGET__', _powerShellLiteral(targetDirectory))
      .replaceAll('__BACKUP__', _powerShellLiteral(backupDirectory))
      .replaceAll('__WORKING__', _powerShellLiteral(workingDirectory))
      .replaceAll('__ACK__', _powerShellLiteral(acknowledgementPath))
      .replaceAll('__ERROR_LOG__', _powerShellLiteral(errorLogPath))
      .replaceAll('__EXE_NAME__', _powerShellLiteral(executableName))
      .replaceAll('__PID__', currentProcessId.toString())
      .replaceAll('__READY_SECONDS__', readinessTimeoutSeconds.toString());
}
