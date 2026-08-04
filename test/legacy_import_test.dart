// Reading the file an older version left on disk.
//
// Versions up to 0.3.1 had no backup screen at all. A writer moving to a new
// computer, or reinstalling after a wipe, had nothing to bring with him except
// the app's own store — which on Windows sits in plain sight at
// %APPDATA%\com.example\stamsofer\shared_preferences.json and could not be fed
// back in anywhere.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/legacy_import.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const appId = 'sofer_vmone';

  Map<String, dynamic> store({
    List<Map<String, dynamic>>? projects,
    List<Map<String, dynamic>>? history,
    List<Map<String, dynamic>>? expenses,
    Map<String, dynamic>? extra,
  }) =>
      {
        'flutter.projects': jsonEncode(projects ?? const []),
        'flutter.history': jsonEncode(history ?? const []),
        'flutter.expenses': jsonEncode(expenses ?? const []),
        'flutter.last_positions': jsonEncode({
          'p1': {'page': 12, 'line': 7}
        }),
        'flutter.app_theme': 'layla',
        'flutter.notification_enabled': false,
        'flutter.user_name': 'שאול',
        ...?extra,
      };

  Map<String, dynamic> convert(Map<String, dynamic> s) =>
      LegacyImport.toBackup(s, appId: appId, formatVersion: 1);

  final project = {
    'id': 'p1',
    'name': 'ספר תורה',
    'typeName': 'sefer',
    'price': 40000,
    'expenses': 0,
    'targetDaily': 1,
    'targetMonthly': 20,
    'totalPages': 245,
    'linesPerPage': 42,
  };

  group('telling a store file from a backup', () {
    test('the store is recognised by its prefix, not its name', () {
      // The writer has very likely renamed it while copying it off the old
      // machine, so the name proves nothing.
      expect(LegacyImport.looksLikeStore(store()), isTrue);
    });

    test('a real backup is left alone', () {
      expect(
        LegacyImport.looksLikeStore({
          'app': appId,
          'formatVersion': 1,
          'projects': const [],
        }),
        isFalse,
      );
    });
  });

  group('what comes across', () {
    test('the records, decoded out of their string values', () {
      final out = convert(store(projects: [project]));
      expect(out['app'], appId);
      expect((out['projects'] as List), hasLength(1));

      // And they are real records at the other end, not just JSON.
      final p = Project.fromJson(
          Map<String, dynamic>.from((out['projects'] as List).first as Map));
      expect(p.name, 'ספר תורה');
      expect(p.totalPages, 245);
    });

    test('the stored positions', () {
      final out = convert(store());
      expect((out['lastPositions'] as Map)['p1'], {'page': 12, 'line': 7});
    });

    test('the settings, unprefixed', () {
      final settings = convert(store())['settings'] as Map<String, dynamic>;
      expect(settings['app_theme'], 'layla');
      expect(settings['notification_enabled'], false);
      expect(settings['user_name'], 'שאול');
      expect(settings.containsKey('projects'), isFalse,
          reason: 'a record list is not a setting');
    });

    test('including a setting this build has never heard of', () {
      // A store written by a newer version must not lose keys on the way in.
      final out = convert(store(extra: {'flutter.something_new': 42}));
      expect((out['settings'] as Map)['something_new'], 42);
    });
  });

  group('what it refuses to invent', () {
    test('a date it was written on', () {
      // Nothing in the store says when. Claiming one would be making it up,
      // and the preview says "unknown" for a null.
      expect(convert(store())['exportedAt'], isNull);
    });
  });

  group('a store that is damaged', () {
    test('gives up only the part that is unreadable', () {
      // A writer restoring a broken file wants whatever survived it. Refusing
      // the file hands him nothing at all.
      final broken = store(projects: [project]);
      broken['flutter.history'] = '{not json at all';

      final out = convert(broken);
      expect((out['projects'] as List), hasLength(1));
      expect((out['history'] as List), isEmpty);
    });

    test('a missing list is an empty one', () {
      final out = convert({'flutter.app_theme': 'klaf'});
      expect((out['projects'] as List), isEmpty);
      expect((out['history'] as List), isEmpty);
      expect((out['expenses'] as List), isEmpty);
    });

    test('a list that is not a list', () {
      final out = convert({'flutter.projects': jsonEncode({'not': 'a list'})});
      expect((out['projects'] as List), isEmpty);
    });
  });

  group('the real thing', () {
    test('a store shaped like the one an 0.3.1 install leaves', () {
      // The shape read off an actual installation: three encoded lists,
      // positions, and a scattering of settings of mixed types.
      final real = {
        'flutter.projects': jsonEncode([project]),
        'flutter.history': jsonEncode([
          {
            'id': '1769959534632_1',
            'projectId': 'p1',
            'startTime': '2026-02-01T09:00:00.000',
            'endTime': '2026-02-01T12:00:00.000',
            'amount': 5,
            'startLine': 1,
            'endLine': 42,
            'description': 'עמוד ה',
            'isManual': false,
          }
        ]),
        'flutter.smart_workflow_enabled': true,
        'flutter.friday_motzei_half_day': false,
        'flutter.work_calendar_rules': '{"schemaVersion":2,"inIsrael":true}',
      };

      final out = convert(real);
      expect((out['history'] as List), hasLength(1));

      final s = WorkSession.fromJson(
          Map<String, dynamic>.from((out['history'] as List).first as Map));
      expect(s.amount, 5);
      expect(s.description, 'עמוד ה');
      // A record from before these fields existed still reads.
      expect(s.timeRecorded, isTrue);
      expect(s.timeOfDayKnown, isTrue);

      final settings = out['settings'] as Map<String, dynamic>;
      expect(settings['smart_workflow_enabled'], true);
      expect(settings['work_calendar_rules'], isA<String>());
    });
  });
}
