// What the release manifest has to declare.
//
// Flutter puts INTERNET in the debug and profile manifests for its own tooling
// and leaves the release one alone, which is right for an app that makes no
// requests. This one makes exactly one — asking GitHub whether a newer release
// exists — and it was declared nowhere that a release build could see it.
//
// The failure was invisible by construction: the check throws a SocketException,
// UpdateService catches everything on purpose, and the writer is told it could
// not check right now. A good part of this audience is behind content filtering
// where that message is the ordinary truth, so nobody would ever have thought to
// look. The permission is asserted here because no test of Dart code can reach
// it and no build step complains.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  String source() {
    expect(manifest.existsSync(), isTrue,
        reason: 'run from the project root: ${manifest.path}');
    return manifest.readAsStringSync();
  }

  bool declares(String permission) =>
      source().contains('android:name="android.permission.$permission"');

  group('the release manifest', () {
    test('declares INTERNET, which the update check needs', () {
      // Not in the debug manifest — that one is not in a release APK.
      expect(declares('INTERNET'), isTrue);
    });

    test('still declares what the timer and the reminder need', () {
      for (final permission in [
        'RECEIVE_BOOT_COMPLETED',
        'SCHEDULE_EXACT_ALARM',
        'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_DATA_SYNC',
        'VIBRATE',
      ]) {
        expect(declares(permission), isTrue, reason: permission);
      }
    });

    test('asks for nothing that reads the writer or the device', () {
      // Every permission here shows in the installer, and a sideloaded app is
      // judged on that list before anything else. Nothing in this app needs
      // any of these, and one arriving by way of a plugin should be a decision
      // rather than a surprise.
      for (final permission in [
        'READ_CONTACTS',
        'READ_EXTERNAL_STORAGE',
        'WRITE_EXTERNAL_STORAGE',
        'ACCESS_FINE_LOCATION',
        'ACCESS_COARSE_LOCATION',
        'CAMERA',
        'RECORD_AUDIO',
        'READ_PHONE_STATE',
        'QUERY_ALL_PACKAGES',
      ]) {
        expect(declares(permission), isFalse, reason: permission);
      }
    });
  });
}
