// The version number, in one place rather than three.
//
// It lived in pubspec.yaml and in two "about" dialogs, kept in step by hand.
// They had already drifted: the app reported 0.3.0 for the whole of 0.4.0's
// development, so the number a user would quote in a bug report was the wrong
// one — and nothing anywhere would have said so.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/version.dart';

void main() {
  /// `version: 0.4.0+2` → ('0.4.0', 2)
  ({String name, int code}) declaredInPubspec() {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final value = line.split(':')[1].trim();
    final parts = value.split('+');
    return (name: parts.first, code: int.parse(parts[1]));
  }

  test('the app reports the version it was built as', () {
    expect(appVersion, declaredInPubspec().name);
  });

  test('and the changelog documents it', () {
    // A released version with nothing written about it is a version whose
    // users cannot find out what changed.
    final changelog = File('CHANGELOG.md').readAsStringSync();
    expect(changelog, contains(appVersion));
  });

  test('the build number is above every one already published', () {
    // Android refuses to install an update whose versionCode has not
    // increased — INSTALL_FAILED_VERSION_DOWNGRADE — and the writer sees only
    // "cannot install". The published APKs were read to get this number:
    // 0.3.0 shipped as 1 and 0.3.1 as 2, so anything at or below 2 cannot
    // reach a single existing user.
    expect(declaredInPubspec().code, greaterThan(2),
        reason: '0.3.1 is already installed as build 2');
  });
}
