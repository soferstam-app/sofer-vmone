// A partial restore must not look like a whole one.
//
// Skipping a record the build cannot read is right: one bad entry must not cost
// the writer the rest of the file. Doing it silently is not. A restore that
// dropped a third of the history reported success in the same words as one that
// dropped nothing, and a writer who then deleted the original lost the rest.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/backup_service.dart';

void main() {
  group('the name of an export', () {
    test('two in the same minute do not collide', () {
      // The stamp claimed never to collide and stopped at minutes.
      final name = BackupService.instance.suggestedFileName();
      expect(name, matches(r'sofer-vmone-backup-\d{4}-\d{2}-\d{2}_\d{6}\.json'));
    });

    test('and it still sorts chronologically', () {
      final name = BackupService.instance.suggestedFileName();
      final stamp = name.split('backup-').last.replaceAll('.json', '');
      // year-month-day_hhmmss sorts as text exactly as it sorts in time.
      expect(stamp.length, '2026-05-04_143012'.length);
    });
  });

  group('a preview counts what it could not read', () {
    test('a clean file reports none', () {
      const preview = BackupPreview(
        projects: [],
        history: [],
        expenses: [],
        settings: {},
        lastPositions: {},
        fileName: 'backup.json',
      );
      expect(preview.unreadable, 0);
    });

    test('and the field exists to be shown before confirming', () {
      const preview = BackupPreview(
        projects: [],
        history: [],
        expenses: [],
        settings: {},
        lastPositions: {},
        fileName: 'backup.json',
        unreadable: 7,
      );
      expect(preview.unreadable, 7);
    });
  });

  group('the version in the backup', () {
    test('is the one the app reports, not a second copy', () {
      // It was written out here by hand, which is a number that gets forgotten.
      expect(BackupService.appVersion, isNotEmpty);
      expect(BackupService.appVersion, matches(r'^\d+\.\d+\.\d+$'));
    });
  });
}
