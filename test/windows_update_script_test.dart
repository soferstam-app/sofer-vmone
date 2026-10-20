import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/update_installer.dart';

void main() {
  test('the Windows updater waits for first frame and can roll back', () {
    final script = buildWindowsUpdateScript(
      sourceDirectory: r'C:\Temp\new package',
      targetDirectory: r'C:\Users\Writer\Sofer',
      backupDirectory: r'C:\Temp\backup',
      workingDirectory: r'C:\Temp\work',
      acknowledgementPath: r'C:\Temp\work\ready',
      errorLogPath: r'C:\Temp\work\error.txt',
      executableName: 'סופר ומונה.exe',
      currentProcessId: 1234,
    );

    expect(script, contains(r'Wait-Process -Timeout 120'));
    expect(script, contains(r'$env:SOFER_UPDATE_READY'));
    expect(script, contains('successful first frame'));
    expect(script, contains(r'if ($backupReady)'));
    expect(script, contains(r'$env:SOFER_UPDATE_ERROR'));
    expect(script, contains(r'$currentProcessId = 1234'));
  });

  test('PowerShell paths are literals even when a folder has an apostrophe',
      () {
    final script = buildWindowsUpdateScript(
      sourceDirectory: r"C:\Users\O'Brien\new",
      targetDirectory: r'C:\App',
      backupDirectory: r'C:\Backup',
      workingDirectory: r'C:\Work',
      acknowledgementPath: r'C:\Work\ready',
      errorLogPath: r'C:\Work\error.txt',
      executableName: 'סופר ומונה.exe',
      currentProcessId: 9,
    );

    expect(script, contains(r"$source = 'C:\Users\O''Brien\new'"));
  });

  test('the detached script replaces a package that acknowledges startup',
      () async {
    if (!Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('sofer-update-test-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final target = await Directory('${root.path}\\target').create();
    final working = await Directory('${root.path}\\working').create();
    final source = await Directory('${working.path}\\source').create();
    final backup = Directory('${working.path}\\backup');
    final acknowledgement = '${working.path}\\ready';
    final errorLog = '${working.path}\\error.txt';

    await File('${target.path}\\app.cmd').writeAsString('@exit /b 0\r\n');
    await File('${target.path}\\payload.txt').writeAsString('old');
    await File('${source.path}\\app.cmd').writeAsString(
      '@echo off\r\n> "%SOFER_UPDATE_READY%" echo ready\r\nexit /b 0\r\n',
    );
    await File('${source.path}\\payload.txt').writeAsString('new');

    final script = buildWindowsUpdateScript(
      sourceDirectory: source.path,
      targetDirectory: target.path,
      backupDirectory: backup.path,
      workingDirectory: working.path,
      acknowledgementPath: acknowledgement,
      errorLogPath: errorLog,
      executableName: 'app.cmd',
      currentProcessId: 2147483000,
      readinessTimeoutSeconds: 3,
    );
    final scriptFile = File('${working.path}\\apply.ps1');
    await scriptFile.writeAsBytes(
      <int>[0xef, 0xbb, 0xbf, ...utf8.encode(script)],
      flush: true,
    );

    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
      ],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(await File('${target.path}\\payload.txt').readAsString(), 'new');
  });

  test('the detached script restores the old package when startup fails',
      () async {
    if (!Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('sofer-rollback-test-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final target = await Directory('${root.path}\\target').create();
    final working = await Directory('${root.path}\\working').create();
    final source = await Directory('${working.path}\\source').create();
    final backup = Directory('${working.path}\\backup');
    final acknowledgement = '${working.path}\\ready';
    final errorLog = '${working.path}\\error.txt';

    await File('${target.path}\\app.cmd').writeAsString(
      '@echo off\r\n> "%~dp0old-reopened" echo old\r\nexit /b 0\r\n',
    );
    await File('${target.path}\\payload.txt').writeAsString('old');
    await File('${source.path}\\app.cmd')
        .writeAsString('@echo off\r\nexit /b 1\r\n');
    await File('${source.path}\\payload.txt').writeAsString('new');

    final script = buildWindowsUpdateScript(
      sourceDirectory: source.path,
      targetDirectory: target.path,
      backupDirectory: backup.path,
      workingDirectory: working.path,
      acknowledgementPath: acknowledgement,
      errorLogPath: errorLog,
      executableName: 'app.cmd',
      currentProcessId: 2147483000,
      readinessTimeoutSeconds: 2,
    );
    final scriptFile = File('${working.path}\\apply.ps1');
    await scriptFile.writeAsBytes(
      <int>[0xef, 0xbb, 0xbf, ...utf8.encode(script)],
      flush: true,
    );

    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
      ],
    );
    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(await File('${target.path}\\payload.txt').readAsString(), 'old');
    expect(await File(errorLog).exists(), isTrue);

    final reopened = File('${target.path}\\old-reopened');
    for (var attempt = 0; attempt < 20 && !await reopened.exists(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await reopened.exists(), isTrue);
  });
}
