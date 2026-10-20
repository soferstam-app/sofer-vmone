import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';

/// Simulates a platform returning false after SharedPreferences has already
/// updated its in-process cache. Durable values must be reloaded on failure.
class RefusingPreferences extends SharedPreferencesStorePlatform {
  final Map<String, Object> durable;
  Set<int> refuseOperations = {};
  int operations = 0;
  RefusingPreferences(Map<String, Object> values) : durable = {...values};
  @override
  Future<bool> clear() async {
    durable.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => {...durable};
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (refuseOperations.remove(++operations)) return false;
    durable[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (refuseOperations.remove(++operations)) return false;
    durable.remove(key);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.setMockInitialValues({});
    StorageService.demoStore = null;
    StorageService.onChanged = null;
  });
  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = previous;
  });
  final p = Project(
      id: 'p',
      name: 'בדיקה',
      type: ProjectType.tefillin,
      price: 1200,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0);
  final work = WorkSession(
      id: 's',
      projectId: 'p',
      startTime: DateTime(2026, 10, 15, 9),
      endTime: DateTime(2026, 10, 15, 10),
      amount: 1,
      startLine: 0,
      endLine: 0,
      pairIndex: 1,
      parshiya: 1,
      tefillinType: 'head',
      description: 'קדש',
      isManual: true);

  test('C9 false history acknowledgement reloads the cached old value',
      () async {
    final original = jsonEncode([work.toJson()]);
    final platform = RefusingPreferences({'flutter.history': original})
      ..refuseOperations = {1};
    SharedPreferencesStorePlatform.instance = platform;
    final storage = StorageService();
    await expectLater(storage.saveHistory([work.copyWith(isInvalid: true)]),
        throwsStateError);
    expect((await storage.loadHistory()).single.isInvalid, isFalse);
    expect(platform.durable['flutter.history'], original);
    await storage.saveHistory([work.copyWith(isInvalid: true)]);
    expect((await storage.loadHistory()).single.isInvalid, isTrue);
  });

  for (var step = 1; step <= 4; step++) {
    test(
        'C4 false platform acknowledgement at step $step rolls back cache and disk',
        () async {
      final projects = jsonEncode([p.toJson()]);
      final history = jsonEncode([work.toJson()]);
      final platform = RefusingPreferences(
          {'flutter.projects': projects, 'flutter.history': history})
        ..refuseOperations = {step};
      SharedPreferencesStorePlatform.instance = platform;
      final storage = StorageService();
      await expectLater(
          storage.saveWorkSnapshot(projects: [
            p.copyWith(tefillinFlags: {'1:head:1': 'void'})
          ], history: [
            work.copyWith(isInvalid: true)
          ]),
          throwsStateError);
      expect((await storage.loadProjects()).single.tefillinFlags, isEmpty);
      expect((await storage.loadHistory()).single.isInvalid, isFalse);
      expect(platform.durable,
          {'flutter.projects': projects, 'flutter.history': history});
    });
  }

  test('C10 false checkpoint acknowledgement retains the owners previous timer',
      () async {
    final original =
        jsonEncode({'isPaused': true, 'accumulatedElapsedSeconds': 600});
    final platform = RefusingPreferences({'flutter.timer_state': original})
      ..refuseOperations = {1};
    SharedPreferencesStorePlatform.instance = platform;
    await expectLater(
        StorageService().saveTimerState({'isPaused': false}), throwsStateError);
    expect(
        (await StorageService().getTimerState())['accumulatedElapsedSeconds'],
        600);
    expect((await StorageService().getTimerState())['isPaused'], isTrue);
  });
}
