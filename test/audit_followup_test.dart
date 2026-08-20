// Findings from an independent audit, held down so they cannot come back.
//
// Each of these was verified against the code before it was fixed, and each is
// the kind of fault that leaves no trace on screen: a deletion that looks like
// it happened, a reset that looks complete, a date that cannot be corrected.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/backup_service.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a date entered by mistake can be taken back', () {
    // copyWith could not clear anything: a nullable field's "not given" and its
    // "set this to nothing" were the same value, so a send date typed into the
    // wrong batch could be changed but never removed.
    final r = Proofread(
      id: 'r1',
      projectId: 'p1',
      sentAt: DateTime(2026, 5, 1),
      returnedAt: DateTime(2026, 5, 9),
      findings: 4,
    );

    test('a send date clears', () {
      expect(r.copyWith(sentAt: null).sentAt, isNull);
    });

    test('a return date clears', () {
      expect(r.copyWith(returnedAt: null).returnedAt, isNull);
    });

    test('a correction count clears', () {
      expect(r.copyWith(findings: null).findings, isNull);
    });

    test('and leaving one out still leaves it alone', () {
      final edited = r.copyWith(notes: 'הערה');
      expect(edited.sentAt, DateTime(2026, 5, 1));
      expect(edited.returnedAt, DateTime(2026, 5, 9));
      expect(edited.findings, 4);
    });
  });

  group('contradictory dates are not a negative length of time', () {
    test('a return before the send reports nothing rather than minus nine days',
        () {
      final r = Proofread(
        id: 'r1',
        projectId: 'p1',
        sentAt: DateTime(2026, 5, 10),
        returnedAt: DateTime(2026, 5, 1),
      );
      expect(r.turnaround(), isNull);
    });

    test('an ordinary pair still measures', () {
      final r = Proofread(
        id: 'r1',
        projectId: 'p1',
        sentAt: DateTime(2026, 5, 1),
        returnedAt: DateTime(2026, 5, 11),
      );
      expect(r.turnaround()!.inDays, 10);
    });
  });

  group('erasing everything leaves nothing pointing at a record', () {
    test('the timer, the last commission and the stored positions all go',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.projects': '[]',
        'flutter.timer_state': '{"isPaused":false}',
        'flutter.last_project': 'p1',
        'flutter.last_positions': '{"p1":{"page":12,"line":7}}',
      });

      await storage.eraseAllRecords();

      // A clock still counting against a commission that no longer exists is
      // the state this prevents.
      expect(await storage.getTimerState(), isEmpty);
      expect(await storage.getLastProjectId(), isNull);
      expect(await storage.getLastPosition('p1'), isEmpty);
    });

    test('but the writer\'s own settings are left alone', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.projects': '[]',
        'flutter.sofer_name': 'שאול',
        'flutter.use_gregorian_dates': true,
      });

      await storage.eraseAllRecords();

      // How he set the app up for himself is not data about his work.
      expect(await storage.getSoferName(), 'שאול');
      expect(await storage.getUseGregorianDates(), isTrue);
    });
  });

  group('the backup says how much is in it', () {
    test('including the proofreading, which the count had missed', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.proofreads':
            '[{"id":"r1","projectId":"p1"},{"id":"r2","projectId":"p1"}]',
      });

      final json = await BackupService.instance.buildBackupJson();
      expect(json, contains('"proofreads": 2'));
    });
  });
}
