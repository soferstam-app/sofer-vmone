// Comparing the running version against the newest published one.
//
// The whole of the update feature that can be wrong without anyone noticing.
// Compared as text, "0.10.0" is older than "0.9.0" — '1' sorts before '9' — so
// a writer would be told they were up to date for every release after the
// ninth. Nothing on the way to the screen would catch it, and the failure only
// begins months after the code is written.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/version_check.dart';

void main() {
  Version v(String s) => Version.tryParse(s)!;

  group('reading a tag', () {
    test('an ordinary one', () {
      expect(v('0.4.0'), const Version(0, 4, 0));
    });

    test('with the v half the world writes', () {
      expect(v('v1.2.3'), const Version(1, 2, 3));
      expect(v('V1.2.3'), const Version(1, 2, 3));
    });

    test('two parts mean the third is zero, which is what a person means', () {
      expect(v('1.2'), const Version(1, 2, 0));
    });

    test('a pre-release suffix is trimmed', () {
      expect(v('0.5.0-beta.2'), const Version(0, 5, 0));
    });

    test('anything that is not a version is refused, not guessed at', () {
      // This repository has a tag called APP. Guessing puts a wrong answer in
      // front of the writer; refusing puts none.
      expect(Version.tryParse('APP'), isNull);
      expect(Version.tryParse(''), isNull);
      expect(Version.tryParse('1.2.3.4'), isNull);
      expect(Version.tryParse('1.x.3'), isNull);
      expect(Version.tryParse('-1.0.0'), isNull);
    });
  });

  group('which is newer', () {
    test('ten is after nine, which text comparison gets backwards', () {
      expect(v('0.10.0').isNewerThan(v('0.9.0')), isTrue);
      expect(v('0.9.0').isNewerThan(v('0.10.0')), isFalse);
      expect(v('1.0.0').isNewerThan(v('0.99.99')), isTrue);
    });

    test('the same version is not newer than itself', () {
      expect(v('0.4.0').isNewerThan(v('0.4.0')), isFalse);
      expect(v('0.4.0'), v('0.4.0'));
    });

    test('a patch counts', () {
      expect(v('0.4.1').isNewerThan(v('0.4.0')), isTrue);
    });
  });

  group('what the writer is told', () {
    Map<String, dynamic> release({
      String tag = '0.5.0',
      bool draft = false,
      bool prerelease = false,
      String url = 'https://example.invalid/releases/tag/0.5.0',
      String? published = '2026-08-01T10:00:00Z',
    }) =>
        {
          'tag_name': tag,
          'draft': draft,
          'prerelease': prerelease,
          'html_url': url,
          'published_at': published,
        };

    UpdateStatus read(Map<String, dynamic> json, String running) =>
        readLatestRelease(json: json, running: Version.tryParse(running)!);

    test('a newer release, with somewhere to read about it', () {
      final status = read(release(), '0.4.0');
      expect(status, isA<UpdateAvailable>());
      final available = status as UpdateAvailable;
      expect(available.version, const Version(0, 5, 0));
      expect(available.pageUrl, contains('0.5.0'));
      expect(available.publishedAt, DateTime.utc(2026, 8, 1, 10));
    });

    test('the same version means up to date', () {
      expect(read(release(tag: '0.4.0'), '0.4.0'), isA<UpToDate>());
    });

    test('an older published release also means up to date', () {
      // Running a build newer than anything released — which is every day of
      // development — must not be reported as an update being available.
      expect(read(release(tag: '0.3.1'), '0.4.0'), isA<UpToDate>());
    });

    test('a pre-release is not offered to whoever pressed the button', () {
      expect(read(release(tag: '0.9.0', prerelease: true), '0.4.0'),
          isA<UpToDate>());
    });

    test('a draft is not a release at all', () {
      expect(read(release(tag: '0.9.0', draft: true), '0.4.0'),
          isA<UpdateCheckFailed>());
    });

    test('a tag nobody can parse is said so, not guessed at', () {
      final status = read(release(tag: 'APP'), '0.4.0');
      expect(status, isA<UpdateCheckFailed>());
      expect((status as UpdateCheckFailed).reason, contains('APP'));
    });

    test('a missing tag is a failure, not an update', () {
      expect(read({'draft': false}, '0.4.0'), isA<UpdateCheckFailed>());
    });

    test('a missing link falls back to the releases page', () {
      final status = read(release(url: ''), '0.4.0') as UpdateAvailable;
      expect(status.pageUrl, contains('releases'));
    });

    test('an unreadable date does not cost the update', () {
      final status =
          read(release(published: 'not a date'), '0.4.0') as UpdateAvailable;
      expect(status.publishedAt, isNull);
      expect(status.version, const Version(0, 5, 0));
    });
  });
}
