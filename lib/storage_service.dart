import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logic/currency.dart';
import 'logic/hebrew_clock.dart';
import 'logic/hebrew_work_calendar.dart';
import 'logic/keyboard_shortcuts.dart';
import 'logic/home_additions.dart';
import 'logic/writing_journal.dart';
import 'entry/entry_draft.dart';
import 'models.dart';
import 'theme/app_theme.dart';

/// The handful of preference operations the app actually performs.
///
/// Introduced so a demo build can be given a store that is provably not the
/// disk. shared_preferences' own test hook was tried first and does not hold
/// in a release build on Windows: the app went on reading and writing the real
/// file, which is the one thing a demo must never do.
abstract class KeyValueStore {
  String? getString(String key);
  bool? getBool(String key);
  int? getInt(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
  Future<void> setInt(String key, int value);
  Future<void> remove(String key);
}

class _DiskStore implements KeyValueStore {
  final SharedPreferences _prefs;
  const _DiskStore(this._prefs);

  @override
  String? getString(String key) => _prefs.getString(key);
  @override
  bool? getBool(String key) => _prefs.getBool(key);
  @override
  int? getInt(String key) => _prefs.getInt(key);
  Future<void> _write(String key, Future<bool> Function() action) async {
    try {
      if (!await action()) throw StateError('Could not store $key');
    } catch (_) {
      // SharedPreferences changes its memory cache before the platform write.
      // Reload durable values so a failed write cannot masquerade as success
      // on a subsequent read in the same process.
      try {
        await _prefs.reload();
      } catch (error) {
        debugPrint('Reload after failed preference write: $error');
      }
      rethrow;
    }
  }

  @override
  Future<void> setString(String key, String value) =>
      _write(key, () => _prefs.setString(key, value));
  @override
  Future<void> setBool(String key, bool value) =>
      _write(key, () => _prefs.setBool(key, value));
  @override
  Future<void> setInt(String key, int value) =>
      _write(key, () => _prefs.setInt(key, value));
  @override
  Future<void> remove(String key) => _write(key, () => _prefs.remove(key));
}

/// A store that lives and dies with the process. Demo builds only.
class MemoryStore implements KeyValueStore {
  final Map<String, Object> _values;
  MemoryStore(Map<String, Object> initial) : _values = {...initial};

  @override
  String? getString(String key) =>
      _values[key] is String ? _values[key] as String : null;
  @override
  bool? getBool(String key) =>
      _values[key] is bool ? _values[key] as bool : null;
  @override
  int? getInt(String key) => _values[key] is int ? _values[key] as int : null;
  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;
  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;
  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;
  @override
  Future<void> remove(String key) async => _values.remove(key);
}

/// Adds one post-write hook to the preference store.  Keeping this below the
/// screens means a new save path cannot accidentally forget the live backup.
class _ObservedStore implements KeyValueStore {
  final KeyValueStore _delegate;
  final Future<void> Function() _changed;
  const _ObservedStore(this._delegate, this._changed);

  @override
  String? getString(String key) => _delegate.getString(key);
  @override
  bool? getBool(String key) => _delegate.getBool(key);
  @override
  int? getInt(String key) => _delegate.getInt(key);

  @override
  Future<void> setString(String key, String value) =>
      StorageService._enqueue(() async {
        await _delegate.setString(key, value);
        await StorageService._afterChanged(_changed);
      });

  @override
  Future<void> setBool(String key, bool value) =>
      StorageService._enqueue(() async {
        await _delegate.setBool(key, value);
        await StorageService._afterChanged(_changed);
      });

  @override
  Future<void> setInt(String key, int value) =>
      StorageService._enqueue(() async {
        await _delegate.setInt(key, value);
        await StorageService._afterChanged(_changed);
      });

  @override
  Future<void> remove(String key) => StorageService._enqueue(() async {
        await _delegate.remove(key);
        await StorageService._afterChanged(_changed);
      });
}

/// Recovery must stop writes without preventing an actionable startup screen.
class WorkRecoveryException implements Exception {
  final Object cause;
  const WorkRecoveryException(this.cause);
  @override
  String toString() => 'Writing data needs recovery: $cause';
}

class StorageService {
  /// Set once, by a demo build, before anything reads a setting. While it is
  /// set nothing in the app opens the preferences file at all.
  static MemoryStore? demoStore;

  /// Installed by the application root.  Tests and demo builds leave it
  /// unset, so storage remains independent of the filesystem.
  static Future<void> Function()? onChanged;

  /// All preference writes share one queue. A fast pair of line completions
  /// must not read the same old JSON and then overwrite one another, and a
  /// live-backup callback must observe a complete snapshot.
  static Future<void> _writeQueue = Future<void>.value();
  static Completer<void>? _workBarrier;
  static Future<void>? _workRecovery;
  static const _keyWorkJournal = 'pending_work_mutation';

  static Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writeQueue.then((_) => operation());
    _writeQueue = next.catchError((_) {});
    return next;
  }

  static Future<KeyValueStore> _open({bool observed = true}) async {
    if (observed && _workBarrier != null) await _workBarrier!.future;
    final demo = demoStore;
    final store = demo ?? _DiskStore(await SharedPreferences.getInstance());
    final String? journal;
    try {
      journal = store.getString(_keyWorkJournal);
    } catch (error) {
      throw WorkRecoveryException(error);
    }
    if (_workBarrier == null && journal != null) {
      _workRecovery ??= _recoverWorkJournal(store);
      try {
        await _workRecovery;
      } catch (error) {
        throw WorkRecoveryException(error);
      } finally {
        _workRecovery = null;
      }
    }
    final changed = onChanged;
    return !observed || changed == null
        ? store
        : _ObservedStore(store, changed);
  }

  static const String _keyProjects = 'projects';
  static const String _keyHistory = 'history';
  static const String _keyNotificationEnabled = 'notification_enabled';
  static const String _keyNotificationTime = 'notification_time';
  static const String _keySmartWorkflowEnabled = 'smart_workflow_enabled';
  static const String _keyLastPositions = 'last_positions';
  static const String _keyTimerState = 'timer_state';
  static const String _keyDayRolloverHour = 'day_rollover_hour';
  static const String _keyFridayMotzeiHalfDay = 'friday_motzei_half_day';
  static const String _keyUseGregorianDates = 'use_gregorian_dates';
  static const String _keyExpenses = 'expenses';
  static const String _keyProofreads = 'proofreads';
  static const String _keyOnboardingSeen = 'onboarding_seen';
  static const String _keyAskBreakLength = 'ask_break_length';
  static const String _keyBreakChime = 'break_chime';
  static const String _keyPayments = 'payments';
  static const String _keyOrders = 'orders';
  static const String _keySoferName = 'sofer_name';
  static const String _keyWorkCalendarRules = 'work_calendar_rules';
  static const String _keyDayStart = 'day_start';
  static const String _keyAppTheme = 'app_theme';
  static const String _keyAppLanguage = 'app_language';
  static const String _keyAutoNightTheme = 'auto_night_theme';
  static const String _keyCurrency = 'currency';
  static const String _keyAutoBackupFolder = 'auto_backup_folder';
  static const String _keySmartReminder = 'smart_reminder';
  static const String _keyLastProject = 'last_project';
  static const String _keyWindowSize = 'window_size';
  static const String _keyShortcuts = 'keyboard_shortcuts';
  static const String _keyHomeAdditions = 'home_additions';
  static const String _keyWritingJournal = 'writing_journal';
  static const String _keyInterfaceTextScale = 'interface_text_scale_percent';
  static const String _keyPendingEntry = 'pending_entry';
  static const String _keyLastRunAppVersion = 'last_run_app_version';

  Future<void> saveProjects(List<Project> projects) =>
      _saveList(_keyProjects, projects.map((p) => p.toJson()).toList());

  Future<void> ensureWorkRecovered() async {
    await _open(observed: false);
  }

  /// Language is independent of the interrupted work transaction, and can be
  /// read safely before the recovery screen without opening the work lists.
  Future<String?> recoveryLanguageCode() async {
    try {
      final store =
          demoStore ?? _DiskStore(await SharedPreferences.getInstance());
      final code = store.getString(_keyAppLanguage);
      return code == 'he' || code == 'en' ? code : null;
    } catch (_) {
      return null;
    }
  }

  /// Emergency export deliberately bypasses recovery and JSON decoding. It
  /// contains the damaged journal, original stored strings and local settings.
  Future<Map<String, dynamic>> exportRecoveryData() async {
    if (_workBarrier != null) await _workBarrier!.future;
    final demo = demoStore;
    final Map<String, Object?> values;
    if (demo != null) {
      values = {...demo._values};
    } else {
      final prefs = await SharedPreferences.getInstance();
      values = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    }
    return {
      'kind': 'sofer-vmone-recovery',
      'capturedAt': DateTime.now().toIso8601String(),
      'preferences': values,
    };
  }

  /// Explicit recovery from a validated backup. Preserve every original
  /// preference before replacing the journal, then let the normal idempotent
  /// recovery protocol restore the selected pair of lists. A crash leaves
  /// either the old journal or this complete, resumable recovery request.
  Future<void> recoverWorkFromBackup({
    required List<Project> projects,
    required List<WorkSession> history,
    required Map<String, dynamic> lastPositions,
  }) =>
      _enqueue(() async {
        final archive = await exportRecoveryData();
        // Earlier rescue copies already have their own durable keys. Avoid
        // nesting them inside each new copy after a failed recovery attempt.
        (archive['preferences'] as Map).removeWhere((key, _) =>
            key is String && key.startsWith('work_recovery_archive_'));
        final store =
            demoStore ?? _DiskStore(await SharedPreferences.getInstance());
        final barrier = Completer<void>();
        _workBarrier = barrier;
        try {
          await store.setString(
              'work_recovery_archive_${DateTime.now().microsecondsSinceEpoch}',
              jsonEncode(archive));
          await store.setString(
              _keyWorkJournal,
              jsonEncode({
                'before': {
                  _keyProjects:
                      jsonEncode(projects.map((p) => p.toJson()).toList()),
                  _keyHistory:
                      jsonEncode(history.map((s) => s.toJson()).toList()),
                },
                'recoveryPositions': lastPositions,
                'archiveOpenSitting': true,
              }));
          await _recoverWorkJournal(store);
        } finally {
          _workBarrier = null;
          barrier.complete();
        }
        // Do not overwrite a good live backup with a manually recovered snapshot.
        // The next ordinary successful save resumes the live-backup hook.
      });

  static Future<void> _recoverWorkJournal(KeyValueStore store) async {
    final raw = store.getString(_keyWorkJournal);
    if (raw == null) return;
    final journal = jsonDecode(raw);
    if (journal is! Map || journal['before'] is! Map) {
      throw const FormatException('Unreadable work recovery journal');
    }
    final before = journal['before'] as Map;
    if (journal['archiveOpenSitting'] == true &&
        journal['recoveryPositions'] is! Map) {
      throw const FormatException('Unreadable recovery positions');
    }
    for (final key in const [_keyProjects, _keyHistory]) {
      if (!before.containsKey(key) ||
          (before[key] != null && before[key] is! String)) {
        throw const FormatException('Incomplete work recovery journal');
      }
      _rawEntriesForWrite(before[key] as String?, key);
    }
    for (final key in const [_keyProjects, _keyHistory]) {
      final value = before[key];
      if (value == null) {
        await store.remove(key);
      } else if (value is String) {
        await store.setString(key, value);
      } else {
        throw const FormatException('Unreadable work recovery value');
      }
    }
    if (journal['archiveOpenSitting'] == true) {
      final positions = journal['recoveryPositions'];
      await store.setString(_keyLastPositions, jsonEncode(positions));
      await store.remove(_keyTimerState);
      await store.remove(_keyPendingEntry);
    }
    await store.remove(_keyWorkJournal);
  }

  /// History and flags commit together. The before-image is durable first;
  /// interrupted operations roll back on the next read, before any UI or
  /// backup can observe the partial mutation. Unknown records remain intact.
  Future<void> saveWorkSnapshot(
          {required List<Project> projects,
          required List<WorkSession> history}) =>
      _enqueue(() async {
        final store = await _open(observed: false);
        // Refuse corrupt data before writing the recovery journal.
        _rawEntriesForWrite(store.getString(_keyProjects), _keyProjects);
        _rawEntriesForWrite(store.getString(_keyHistory), _keyHistory);
        final before = {
          for (final key in const [_keyProjects, _keyHistory])
            key: store.getString(key)
        };
        final barrier = Completer<void>();
        _workBarrier = barrier;
        try {
          await store.setString(
              _keyWorkJournal, jsonEncode({'before': before}));
          await _writeListPreservingUnknown(
              store, _keyProjects, projects.map((p) => p.toJson()).toList());
          await _writeListPreservingUnknown(
              store, _keyHistory, history.map((s) => s.toJson()).toList());
          await store.remove(_keyWorkJournal);
        } catch (_) {
          // Leave the journal in place if rollback itself fails. A later open
          // retries recovery and never silently presents a partially saved set.
          if (store.getString(_keyWorkJournal) != null) {
            await _recoverWorkJournal(store);
          }
          rethrow;
        } finally {
          _workBarrier = null;
          barrier.complete();
        }
        await _notifyChanged();
      });

  Future<void> saveProofreads(List<Proofread> records) =>
      _saveList(_keyProofreads, records.map((r) => r.toJson()).toList());

  Future<List<Proofread>> loadProofreads() async {
    final prefs = await _open();
    return _parseList(prefs.getString(_keyProofreads), Proofread.fromJson);
  }

  Future<void> savePayments(List<Payment> records) =>
      _saveList(_keyPayments, records.map((r) => r.toJson()).toList());

  Future<List<Payment>> loadPayments() async {
    final prefs = await _open();
    return _parseList(prefs.getString(_keyPayments), Payment.fromJson);
  }

  Future<void> saveOrders(List<Order> records) =>
      _saveList(_keyOrders, records.map((r) => r.toJson()).toList());

  Future<List<Order>> loadOrders() async {
    final prefs = await _open();
    return _parseList(prefs.getString(_keyOrders), Order.fromJson);
  }

  /// Writes records back, leaving every stored entry not among them alone.
  ///
  /// A save says "these records are now this"; it does not say "and nothing
  /// else exists". It used to say both, and that quietly undid the whole point
  /// of tombstones. Every screen holds the live records — deleted ones are
  /// filtered out on load — so saving from any screen rewrote the file without
  /// a single tombstone in it. A project sent to the recycle bin was marked
  /// deleted and then, two lines later, erased outright; its sessions went with
  /// it, so restoring from the bin gave back an empty project. And a deletion
  /// with no tombstone left behind is a deletion that another device, still
  /// holding a live copy, undoes at the next merge.
  ///
  /// A record leaves this app in exactly one way: a tombstone, which is a
  /// record like any other and is written like one. Absence is not information
  /// and never removes anything. [eraseList] is the deliberate exception.
  ///
  /// This also preserves what the build cannot read — a record from a newer
  /// version, or one reshaped by a hand repair — which needs no understanding
  /// of it, since the rule is the same rule: it was not written, so it stays.
  Future<void> _saveList(
    String key,
    List<Map<String, dynamic>> records,
  ) async {
    await _enqueue(() async {
      final prefs = await _open(observed: false);
      await _writeListPreservingUnknown(prefs, key, records);
      await _notifyChanged();
    });
  }

  /// Writes one list while refusing to overwrite a malformed top-level value.
  ///
  /// Returning an empty list for a malformed value is appropriate while
  /// reading (the app can still open), but dangerous while writing: the next
  /// ordinary save would silently replace the only copy of the old data. A
  /// failed save leaves the original value untouched and lets the caller show
  /// the existing storage-error recovery path.
  Future<void> _writeListPreservingUnknown(
    KeyValueStore prefs,
    String key,
    List<Map<String, dynamic>> records,
  ) async {
    final written = {
      for (final record in records)
        if (record['id'] is String) record['id'] as String,
    };

    final carried = <dynamic>[];
    for (final entry in _rawEntriesForWrite(prefs.getString(key), key)) {
      // An entry with no readable id cannot be matched against what is being
      // written, so it is kept: dropping it would be guessing that it was
      // meant to go, and the guess is unrecoverable.
      final id = entry is Map ? entry['id'] : null;
      if (id is String && written.contains(id)) continue;
      carried.add(entry);
    }

    await prefs.setString(key, jsonEncode([...records, ...carried]));
  }

  static List<dynamic> _rawEntriesForWrite(String? raw, String key) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {
      // Fall through to a descriptive error. The original value is still in
      // preferences because no write has happened yet.
    }
    throw FormatException('Cannot overwrite malformed stored list: $key');
  }

  static Future<void> _afterChanged(Future<void> Function() changed) async {
    try {
      await changed();
    } catch (error) {
      debugPrint('Post-save backup hook failed: $error');
    }
  }

  Future<void> _notifyChanged() async {
    final changed = onChanged;
    if (changed != null) await _afterChanged(changed);
  }

  /// Applies a merged backup as one queued storage operation.
  ///
  /// All record lists, forward-only positions and portable user preferences
  /// are prepared before the single backup callback runs. If a preference
  /// write fails, the original values are restored best-effort so the import
  /// cannot report a successful half-restore.
  Future<void> saveImportedSnapshot({
    required List<Project> projects,
    required List<WorkSession> history,
    required List<Expense> expenses,
    required List<Proofread> proofreads,
    required List<Payment> payments,
    required List<Order> orders,
    required Map<String, dynamic> lastPositions,
    required Map<String, dynamic> settings,
  }) async {
    await _enqueue(() async {
      final prefs = await _open(observed: false);
      final keys = <String>{
        _keyProjects,
        _keyHistory,
        _keyExpenses,
        _keyProofreads,
        _keyPayments,
        _keyOrders,
        _keyLastPositions,
        ..._portableSettingKeys,
      };
      final before = _capturePreferenceValues(prefs, keys);
      try {
        await _writeListPreservingUnknown(
            prefs, _keyProjects, projects.map((p) => p.toJson()).toList());
        await _writeListPreservingUnknown(
            prefs, _keyHistory, history.map((s) => s.toJson()).toList());
        await _writeListPreservingUnknown(
            prefs, _keyExpenses, expenses.map((e) => e.toJson()).toList());
        await _writeListPreservingUnknown(
            prefs, _keyProofreads, proofreads.map((r) => r.toJson()).toList());
        await _writeListPreservingUnknown(
            prefs, _keyPayments, payments.map((p) => p.toJson()).toList());
        await _writeListPreservingUnknown(
            prefs, _keyOrders, orders.map((o) => o.toJson()).toList());
        await _writePositionsPreservingForward(prefs, lastPositions);
        await _applyPortableSettings(prefs, settings);
        await _notifyChanged();
      } catch (_) {
        await _restorePreferenceValues(prefs, before);
        rethrow;
      }
    });
  }

  static const Set<String> _portableSettingKeys = {
    _keyNotificationEnabled,
    _keyNotificationTime,
    _keySmartWorkflowEnabled,
    _keyDayRolloverHour,
    _keyFridayMotzeiHalfDay,
    _keyUseGregorianDates,
    _keySoferName,
    _keyWorkCalendarRules,
    _keyDayStart,
    _keyAppTheme,
    _keyAppLanguage,
    _keyAutoNightTheme,
    _keyCurrency,
    _keySmartReminder,
    _keyHomeAdditions,
    _keyWritingJournal,
    _keyInterfaceTextScale,
    _keyAskBreakLength,
    _keyBreakChime,
    _keyShortcuts,
  };

  Map<String, Object?> _capturePreferenceValues(
      KeyValueStore prefs, Iterable<String> keys) {
    final out = <String, Object?>{};
    for (final key in keys) {
      Object? value;
      try {
        value = prefs.getString(key);
      } catch (_) {}
      if (value == null) {
        try {
          value = prefs.getBool(key);
        } catch (_) {}
      }
      if (value == null) {
        try {
          value = prefs.getInt(key);
        } catch (_) {}
      }
      out[key] = value;
    }
    return out;
  }

  Future<void> _restorePreferenceValues(
      KeyValueStore prefs, Map<String, Object?> values) async {
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null) {
        await prefs.remove(entry.key);
      } else if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      }
    }
  }

  Future<void> _writePositionsPreservingForward(
      KeyValueStore prefs, Map<String, dynamic> incoming) async {
    final raw = prefs.getString(_keyLastPositions);
    Map<String, dynamic> all = {};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          all = Map<String, dynamic>.from(decoded);
        } else {
          throw const FormatException('positions are not a map');
        }
      } catch (_) {
        throw const FormatException('Cannot overwrite malformed positions');
      }
    }

    for (final entry in incoming.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final page = value['page'];
      final line = value['line'];
      if (page is! num || line is! num || page < 1 || line < 1) continue;
      final existing = all[entry.key];
      final existingPage = existing is Map ? existing['page'] : null;
      final existingLine = existing is Map ? existing['line'] : null;
      final oldPage = existingPage is num ? existingPage.toInt() : 0;
      final oldLine = existingLine is num ? existingLine.toInt() : 0;
      final nextPage = page.toInt();
      final nextLine = line.toInt();
      if (nextPage > oldPage || (nextPage == oldPage && nextLine > oldLine)) {
        all[entry.key] = {'page': nextPage, 'line': nextLine};
      }
    }
    if (incoming.isNotEmpty) {
      await prefs.setString(_keyLastPositions, jsonEncode(all));
    }
  }

  Future<void> _applyPortableSettings(
      KeyValueStore prefs, Map<String, dynamic> settings) async {
    Future<void> boolSetting(String key) async {
      final value = settings[key];
      if (value is bool) await prefs.setBool(key, value);
    }

    await boolSetting(_keyNotificationEnabled);
    await boolSetting(_keySmartWorkflowEnabled);
    await boolSetting(_keyFridayMotzeiHalfDay);
    await boolSetting(_keyUseGregorianDates);
    await boolSetting(_keyAutoNightTheme);
    await boolSetting(_keySmartReminder);
    await boolSetting(_keyAskBreakLength);
    await boolSetting(_keyBreakChime);

    final notificationTime = settings[_keyNotificationTime];
    if (notificationTime is String && _validTimeString(notificationTime)) {
      await prefs.setString(_keyNotificationTime, notificationTime);
    }
    final rollover = settings[_keyDayRolloverHour];
    if (rollover is num) {
      await prefs.setInt(_keyDayRolloverHour, rollover.toInt().clamp(0, 23));
    }

    final stringKeys = <String>{
      _keySoferName,
      _keyWorkCalendarRules,
      _keyDayStart,
      _keyHomeAdditions,
      _keyWritingJournal,
    };
    for (final key in stringKeys) {
      final value = settings[key];
      if (value is! String || value.isEmpty) continue;
      if (key == _keyWorkCalendarRules ||
          key == _keyDayStart ||
          key == _keyHomeAdditions ||
          key == _keyWritingJournal) {
        try {
          if (jsonDecode(value) is! Map) continue;
        } catch (_) {
          continue;
        }
      }
      await prefs.setString(key, value);
    }

    final theme = settings[_keyAppTheme];
    if (theme is String && const {'modern', 'klaf', 'layla'}.contains(theme)) {
      await prefs.setString(_keyAppTheme, theme);
    }
    final language = settings[_keyAppLanguage];
    if (language == 'he' || language == 'en') {
      await prefs.setString(_keyAppLanguage, language as String);
    }
    final currency = settings[_keyCurrency];
    if (currency is String && currency.trim().isNotEmpty) {
      await prefs.setString(_keyCurrency, currency.trim());
    }
    final scale = settings[_keyInterfaceTextScale];
    if (scale is num && const {100, 125, 160, 200}.contains(scale.toInt())) {
      await prefs.setInt(_keyInterfaceTextScale, scale.toInt());
    }
    final shortcuts = settings[_keyShortcuts];
    if (shortcuts is String) {
      try {
        if (jsonDecode(shortcuts) is Map) {
          await prefs.setString(_keyShortcuts, shortcuts);
        }
      } catch (_) {}
    }
  }

  bool _validTimeString(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return false;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    return hour != null &&
        minute != null &&
        hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59;
  }

  /// Empties a stored list outright, tombstones and all.
  ///
  /// The one way to remove a record rather than mark it removed, and it exists
  /// for exactly one caller: the writer asking to erase everything. Nothing
  /// here is recoverable afterwards, which is what makes it the wrong tool for
  /// anything smaller.
  Future<void> eraseList(String key) async {
    await _enqueue(() async {
      final prefs = await _open(observed: false);
      await prefs.remove(key);
      final changed = onChanged;
      if (changed != null) await _afterChanged(changed);
    });
  }

  /// Erases every record the app holds, and every piece of state that points
  /// at one. See [eraseList].
  ///
  /// The four lists alone were not "all the data". A running timer, the last
  /// commission chosen and the stored writing positions all survived the reset
  /// and went on referring to projects that no longer existed — so a writer who
  /// had just erased everything could reopen the app to a clock still counting
  /// against a commission he had deleted.
  Future<void> eraseAllRecords() async {
    await eraseList(_keyProjects);
    await eraseList(_keyHistory);
    await eraseList(_keyExpenses);
    await eraseList(_keyProofreads);
    await eraseList(_keyPayments);
    await eraseList(_keyOrders);

    // State that names a record. Settings are left alone: how the writer set
    // the app up for himself is not data about his work.
    await eraseList(_keyTimerState);
    await eraseList(_keyPendingEntry);
    await eraseList(_keyLastPositions);
    await eraseList(_keyLastProject);
  }

  /// The stored entries of a list, without trying to understand any of them.
  List<dynamic> _rawEntries(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  /// How many stored records this build cannot read, across every list.
  ///
  /// They are kept and written back untouched, but they take no part in any
  /// figure the app shows — so the app has to be able to say they are there
  /// rather than quietly reporting totals that are short.
  Future<int> unreadableRecordCount() async {
    final prefs = await _open();
    var count = 0;
    void tally<T>(String key, T Function(Map<String, dynamic>) fromJson) {
      for (final entry in _rawEntries(prefs.getString(key))) {
        if (entry is! Map) continue;
        try {
          fromJson(Map<String, dynamic>.from(entry));
        } catch (_) {
          count++;
        }
      }
    }

    tally(_keyProjects, Project.fromJson);
    tally(_keyHistory, WorkSession.fromJson);
    tally(_keyExpenses, Expense.fromJson);
    tally(_keyProofreads, Proofread.fromJson);
    tally(_keyPayments, Payment.fromJson);
    tally(_keyOrders, Order.fromJson);
    return count;
  }

  /// Parses a stored list, dropping only the records that cannot be read.
  ///
  /// One malformed entry — from a partial write, a hand-edited file, or a field
  /// a future version shaped differently — must not cost the user everything
  /// else in the list. This mirrors what the backup importer already does.
  List<T> _parseList<T>(
      String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null || raw.isEmpty) return <T>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <T>[];
      final out = <T>[];
      for (final item in decoded) {
        try {
          if (item is Map) out.add(fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          // Skip this record and keep the rest.
        }
      }
      return out;
    } catch (_) {
      return <T>[];
    }
  }

  Future<List<Project>> loadProjects() async {
    final prefs = await _open();
    return _parseList(prefs.getString(_keyProjects), Project.fromJson);
  }

  Future<void> saveHistory(List<WorkSession> history) =>
      _saveList(_keyHistory, history.map((s) => s.toJson()).toList());

  Future<List<WorkSession>> loadHistory() async {
    final prefs = await _open();
    return _parseList(prefs.getString(_keyHistory), WorkSession.fromJson);
  }

  /// Every user-owned value in one map: all data lists plus all
  /// settings. Open work is retained separately for review during migration;
  /// an ordinary backup merge must never resume a timer from another device.
  Future<Map<String, dynamic>> exportAll() async {
    final prefs = await _open();

    // Decoded rather than embedded as raw strings so the backup file is one
    // well-formed document that an importer can validate field by field.
    List<dynamic> decodeList(String key) {
      final raw = prefs.getString(key);
      if (raw == null) return const [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      } catch (_) {}
      throw FormatException('Cannot export damaged storage: $key');
    }

    Map<String, dynamic> decodeMap(String key) {
      final raw = prefs.getString(key);
      if (raw == null) return const {};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
      throw FormatException('Cannot export damaged storage: $key');
    }

    return {
      'projects': decodeList(_keyProjects),
      'history': decodeList(_keyHistory),
      'expenses': decodeList(_keyExpenses),
      'proofreads': decodeList(_keyProofreads),
      'payments': decodeList(_keyPayments),
      'orders': decodeList(_keyOrders),
      'lastPositions': decodeMap(_keyLastPositions),
      // Raw strings retain an unsubmitted form or an interrupted timer even
      // when this version cannot parse them. These are migration evidence,
      // not portable settings: the ordinary importer never activates them.
      'migrationRecovery': {
        'schemaVersion': 1,
        'requiresReview': true,
        'timerStateRaw': prefs.getString(_keyTimerState),
        'pendingEntryRaw': prefs.getString(_keyPendingEntry),
      },
      'settings': {
        _keyNotificationEnabled: prefs.getBool(_keyNotificationEnabled),
        _keyNotificationTime: prefs.getString(_keyNotificationTime),
        _keySmartWorkflowEnabled: prefs.getBool(_keySmartWorkflowEnabled),
        _keyDayRolloverHour: prefs.getInt(_keyDayRolloverHour),
        _keyFridayMotzeiHalfDay: prefs.getBool(_keyFridayMotzeiHalfDay),
        _keyUseGregorianDates: prefs.getBool(_keyUseGregorianDates),
        _keySoferName: prefs.getString(_keySoferName),
        _keyWorkCalendarRules: prefs.getString(_keyWorkCalendarRules),
        _keyDayStart: prefs.getString(_keyDayStart),
        _keyAppTheme: prefs.getString(_keyAppTheme),
        _keyAppLanguage: prefs.getString(_keyAppLanguage),
        _keyAutoNightTheme: prefs.getBool(_keyAutoNightTheme),
        _keyCurrency: prefs.getString(_keyCurrency),
        // Deliberately *not* restored on another device — see BackupService.
        // A path from one machine means nothing on another.
        _keyAutoBackupFolder: prefs.getString(_keyAutoBackupFolder),
        _keySmartReminder: prefs.getBool(_keySmartReminder),
        // The selected project and onboarding/version markers are local UI
        // state, not portable work preferences. The backup importer therefore
        // deliberately leaves them on the receiving device.
        _keyHomeAdditions: prefs.getString(_keyHomeAdditions),
        _keyWritingJournal: prefs.getString(_keyWritingJournal),
        _keyInterfaceTextScale: prefs.getInt(_keyInterfaceTextScale),
        _keyAskBreakLength: prefs.getBool(_keyAskBreakLength),
        _keyBreakChime: prefs.getBool(_keyBreakChime),
        _keyShortcuts: prefs.getString(_keyShortcuts),
      },
    };
  }

  Future<bool> getNotificationEnabled() async {
    final prefs = await _open();
    return prefs.getBool(_keyNotificationEnabled) ?? true;
  }

  Future<void> setNotificationEnabled(bool enabled) async {
    final prefs = await _open();
    await prefs.setBool(_keyNotificationEnabled, enabled);
  }

  Future<TimeOfDay> getNotificationTime() async {
    final prefs = await _open();
    final timeStr = prefs.getString(_keyNotificationTime);
    if (timeStr != null) {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null &&
            minute != null &&
            hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    }
    // Preferences can survive a hand-edited backup or an interrupted older
    // write. Settings must remain usable even when that one value is corrupt.
    return const TimeOfDay(hour: 20, minute: 0);
  }

  Future<void> setNotificationTime(TimeOfDay time) async {
    final prefs = await _open();
    await prefs.setString(_keyNotificationTime, '${time.hour}:${time.minute}');
  }

  Future<bool> getSmartWorkflowEnabled() async {
    final prefs = await _open();
    return prefs.getBool(_keySmartWorkflowEnabled) ?? false;
  }

  Future<void> setSmartWorkflowEnabled(bool enabled) async {
    final prefs = await _open();
    await prefs.setBool(_keySmartWorkflowEnabled, enabled);
  }

  /// Where the writer left off, or empty when nothing usable is stored.
  ///
  /// Guarded like [getTimerState] beside it, and for a reason this one has that
  /// the other does not: the app now accepts a file chosen by the user — a
  /// backup, or the store an older installation left on disk — and a stored
  /// position that is not the shape this expects threw on the way to the entry
  /// form. Not being able to suggest a page is a shrug; not being able to open
  /// the form is not.
  /// The size the desktop window was last left at, or null.
  ///
  /// Stored as two plain numbers rather than a serialised object: whatever a
  /// later version keeps about the window, these two still read.
  Future<Size?> getWindowSize() async {
    final prefs = await _open();
    final raw = prefs.getString(_keyWindowSize);
    if (raw == null) return null;
    final parts = raw.split('x');
    if (parts.length != 2) return null;
    final w = double.tryParse(parts[0]);
    final h = double.tryParse(parts[1]);
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return Size(w, h);
  }

  Future<void> setWindowSize(Size size) async {
    final prefs = await _open();
    await prefs.setString(
        _keyWindowSize, '${size.width.round()}x${size.height.round()}');
  }

  /// Which key does what. Falls back per action to the default, so one
  /// unreadable entry costs one shortcut rather than all three.
  Future<ShortcutMap> getShortcuts() async {
    final prefs = await _open();
    final raw = prefs.getString(_keyShortcuts);
    if (raw == null) return ShortcutMap.defaults;
    try {
      final decoded = jsonDecode(raw);
      return ShortcutMap.decode(
          decoded is Map ? Map<String, dynamic>.from(decoded) : null);
    } catch (_) {
      return ShortcutMap.defaults;
    }
  }

  Future<void> setShortcuts(ShortcutMap map) async {
    final prefs = await _open();
    await prefs.setString(_keyShortcuts, jsonEncode(map.encode()));
  }

  Future<Map<String, dynamic>> getLastPosition(String projectId) async {
    final prefs = await _open();
    final String? data = prefs.getString(_keyLastPositions);
    if (data == null) return {};
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return {};
      final position = decoded[projectId];
      return position is Map ? Map<String, dynamic>.from(position) : {};
    } catch (_) {
      return {};
    }
  }

  /// Pages and lines are counted from one, so neither is ever stored as zero —
  /// a zero would come back out and be displayed as "עמוד 0".
  Future<void> saveLastPosition(String projectId, int page, int line) async {
    await _enqueue(() async {
      final prefs = await _open(observed: false);
      final String? data = prefs.getString(_keyLastPositions);
      Map<String, dynamic> allPositions = {};
      if (data != null) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map) {
            allPositions = Map<String, dynamic>.from(decoded);
          } else {
            throw const FormatException('positions are not a map');
          }
        } catch (_) {
          // Do not replace the only copy of a corrupt position map. The caller
          // can retry after recovering the file, while the original remains
          // untouched.
          rethrow;
        }
      }
      allPositions[projectId] = {
        'page': page < 1 ? 1 : page,
        'line': line < 1 ? 1 : line,
      };
      await prefs.setString(_keyLastPositions, jsonEncode(allPositions));
      final changed = onChanged;
      if (changed != null) await _afterChanged(changed);
    });
  }

  Future<void> saveTimerState(Map<String, dynamic> state) async {
    final prefs = await _open();
    await prefs.setString(_keyTimerState, jsonEncode(state));
  }

  Future<Map<String, dynamic>> getTimerState() async {
    final prefs = await _open();
    final String? data = prefs.getString(_keyTimerState);
    if (data == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(data));
    } catch (_) {
      return {};
    }
  }

  Future<void> clearTimerState() async {
    final prefs = await _open();
    await prefs.remove(_keyTimerState);
  }

  Future<void> savePendingEntry(EntryDraft draft) async {
    final prefs = await _open();
    await prefs.setString(_keyPendingEntry, jsonEncode(draft.toJson()));
  }

  Future<EntryDraft?> getPendingEntry() async {
    final prefs = await _open();
    final raw = prefs.getString(_keyPendingEntry);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return EntryDraft.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingEntry() async {
    final prefs = await _open();
    await prefs.remove(_keyPendingEntry);
  }

  Future<int> getDayRolloverHour() async {
    final prefs = await _open();
    return prefs.getInt(_keyDayRolloverHour) ?? 0;
  }

  Future<void> setDayRolloverHour(int hour) async {
    final prefs = await _open();
    await prefs.setInt(_keyDayRolloverHour, hour.clamp(0, 23));
  }

  /// When a new working day starts — midnight, sunset, nightfall or a chosen
  /// hour.
  ///
  /// Falls back to the standalone rollover hour this replaced, so a device that
  /// had set 02:00 keeps that boundary without the user touching anything.
  Future<DayStart> getDayStart() async {
    final prefs = await _open();
    final raw = prefs.getString(_keyDayStart);
    if (raw != null && raw.isNotEmpty) {
      final decoded = _decodeSettings(raw);
      if (decoded != null) return DayStart.fromJson(decoded);
    }
    return DayStart.fromRolloverHour(prefs.getInt(_keyDayRolloverHour) ?? 0);
  }

  Future<void> setDayStart(DayStart dayStart) async {
    final prefs = await _open();
    await prefs.setString(_keyDayStart, jsonEncode(dayStart.toJson()));
    // Kept in step so a build that predates this setting still reads a sensible
    // hour instead of reverting the user to midnight.
    await prefs.setInt(_keyDayRolloverHour,
        dayStart.boundary == DayBoundary.fixedHour ? dayStart.hour : 0);
  }

  /// Decodes a stored settings blob, returning null rather than throwing.
  ///
  /// Corrupt or unexpectedly shaped settings must never stop the app from
  /// opening — the caller falls back to defaults.
  Map<String, dynamic>? _decodeSettings(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// Which days count as writing days, for every completion estimate the app
  /// makes.
  ///
  /// Migrates the single `friday_motzei_half_day` flag this replaced: when it
  /// was on, Friday counted as half a day and Saturday night as the other
  /// half. When it was off — the old default, which nobody had to choose — the
  /// new defaults apply instead, since a full Friday of writing was never a
  /// deliberate setting.
  Future<WorkCalendarRules> getWorkCalendarRules() async {
    final prefs = await _open();
    final raw = prefs.getString(_keyWorkCalendarRules);
    if (raw != null && raw.isNotEmpty) {
      final decoded = _decodeSettings(raw);
      // fromJson migrates any schema this app has ever written.
      if (decoded != null) return WorkCalendarRules.fromJson(decoded);
    }

    if (prefs.getBool(_keyFridayMotzeiHalfDay) == true) {
      return const WorkCalendarRules(
        friday: DayWeight.half,
        motzeiShabbat: DayWeight.half,
      );
    }
    return WorkCalendarRules.standard;
  }

  Future<void> setWorkCalendarRules(WorkCalendarRules rules) async {
    await _enqueue(() async {
      final prefs = await _open(observed: false);
      await prefs.setString(_keyWorkCalendarRules, jsonEncode(rules.toJson()));
      await _notifyChanged();
    });
  }

  /// The currency the *next* amount is entered in.
  ///
  /// Only that. Every stored amount carries its own, so changing this settles
  /// nothing about what is already recorded — which is the whole point: a
  /// setting that reached backwards would relabel every price the writer ever
  /// agreed, silently and irreversibly.
  Future<Currency> getCurrency() async {
    final prefs = await _open();
    return Currency.fromJson(prefs.getString(_keyCurrency));
  }

  Future<void> setCurrency(Currency currency) async {
    final prefs = await _open();
    await prefs.setString(_keyCurrency, currency.code);
  }

  /// Every currency any record is actually in, so the app can say when a figure
  /// would be adding two of them together.
  Future<Set<Currency>> currenciesInUse() async {
    final projects = await loadProjects();
    final expenses = await loadExpenses();
    return {
      for (final p in projects)
        if (!p.isDeleted) p.currency,
      for (final e in expenses)
        if (!e.isDeleted) e.currency,
    };
  }

  /// Where a copy of everything is written after each sitting, or null when
  /// the writer has not asked for one.
  ///
  /// A folder he already syncs — Dropbox, OneDrive — which is what makes this
  /// "automatic backup" without the app growing a sync engine of its own.
  Future<String?> getAutoBackupFolder() async {
    final prefs = await _open();
    final path = prefs.getString(_keyAutoBackupFolder);
    return path == null || path.isEmpty ? null : path;
  }

  Future<Map<String, dynamic>> getAutoBackupStatus() async {
    final prefs = await _open(observed: false);
    final raw = prefs.getString('auto_backup_status');
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  /// Local diagnostic state, never observed or included in portable backup:
  /// an observed write here would recursively trigger the same backup hook.
  Future<void> saveAutoBackupStatus(Map<String, dynamic> value) async {
    final prefs = await _open(observed: false);
    await prefs.setString('auto_backup_status', jsonEncode(value));
  }

  Future<void> setAutoBackupFolder(String? path) async {
    final prefs = await _open();
    if (path == null || path.isEmpty) {
      await prefs.remove(_keyAutoBackupFolder);
    } else {
      await prefs.setString(_keyAutoBackupFolder, path);
    }
  }

  /// Whether the reminder should follow the writer's own habits rather than
  /// the hour he named. Off until he asks: a reminder that moves on its own is
  /// a surprise, and a surprise from a reminder is not a good one.
  Future<bool> getSmartReminder() async {
    final prefs = await _open();
    return prefs.getBool(_keySmartReminder) ?? false;
  }

  Future<void> setSmartReminder(bool value) async {
    final prefs = await _open();
    await prefs.setBool(_keySmartReminder, value);
  }

  /// The commission the entry form was last used on.
  ///
  /// Offered as the default next time, because a sofer works on one job for
  /// weeks and being asked to pick it out of a list every single time is asking
  /// him to answer a question the app already knows the answer to.
  Future<String?> getLastProjectId() async {
    final prefs = await _open();
    final id = prefs.getString(_keyLastProject);
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> setLastProjectId(String id) async {
    final prefs = await _open();
    await prefs.setString(_keyLastProject, id);
  }

  Future<bool> getUseGregorianDates() async {
    final prefs = await _open();
    return prefs.getBool(_keyUseGregorianDates) ?? false;
  }

  Future<void> setUseGregorianDates(bool value) async {
    final prefs = await _open();
    await prefs.setBool(_keyUseGregorianDates, value);
  }

  /// Which of the three looks the writer picked. Unknown names — from a newer
  /// build that added a fourth — fall back to the modern one rather than
  /// leaving the app unthemed.
  Future<AppTheme> getAppTheme() async {
    final prefs = await _open();
    return AppTheme.fromName(prefs.getString(_keyAppTheme));
  }

  Future<void> setAppTheme(AppTheme theme) async {
    final prefs = await _open();
    await prefs.setString(_keyAppTheme, theme.name);
  }

  /// The explicit interface language, or null for an installation that has
  /// never chosen one. Null is intentionally distinct from Hebrew: the opening
  /// flow uses it to offer a bilingual choice only on a genuinely fresh app.
  Future<String?> getAppLanguageCode() async {
    final prefs = await _open();
    final code = prefs.getString(_keyAppLanguage);
    return code == 'he' || code == 'en' ? code : null;
  }

  Future<void> setAppLanguageCode(String code) async {
    if (code != 'he' && code != 'en') {
      throw ArgumentError.value(code, 'code', 'unsupported app language');
    }
    final prefs = await _open();
    await prefs.setString(_keyAppLanguage, code);
  }

  /// Whether the app dresses for night on its own between nightfall and dawn.
  /// Whether the opening explanation has been shown.
  ///
  /// Absent reads as false, so a settings file written by a version that never
  /// heard of this fails towards showing it rather than towards hiding it —
  /// and [shouldShowOnboarding] then declines anyway for anyone with work in
  /// the app, which is who a stale file belongs to.
  Future<bool> getOnboardingSeen() async {
    final prefs = await _open();
    return prefs.getBool(_keyOnboardingSeen) ?? false;
  }

  Future<void> setOnboardingSeen(bool value) async {
    final prefs = await _open();
    await prefs.setBool(_keyOnboardingSeen, value);
  }

  /// Version seen after the opening flow last completed. This is bookkeeping;
  /// the migration backup check must never depend on this version marker.
  Future<String?> getLastRunAppVersion() async {
    final prefs = await _open();
    final value = prefs.getString(_keyLastRunAppVersion);
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setLastRunAppVersion(String value) async {
    final prefs = await _open();
    await prefs.setString(_keyLastRunAppVersion, value);
  }

  /// Whether pressing "הפסקת קפה" asks how long the break should be.
  ///
  /// On by default, because that is what the app already did. Off means the
  /// break simply starts — and with no way left to name a length there is no
  /// countdown, no chime and no overrun, which is the writer's own rule.
  Future<bool> getAskBreakLength() async {
    final prefs = await _open();
    return prefs.getBool(_keyAskBreakLength) ?? true;
  }

  Future<void> setAskBreakLength(bool value) async {
    final prefs = await _open();
    await prefs.setBool(_keyAskBreakLength, value);
  }

  /// Whether the end of a break is announced with a sound.
  ///
  /// Set from inside the break dialog rather than from settings, so it can be
  /// decided in the moment — a writer stepping out of the room wants it, the
  /// same writer stretching at his desk does not. Remembered between breaks so
  /// the usual answer is already there. Off until asked for: an app that makes
  /// a noise nobody chose is an app that gets muted.
  Future<bool> getBreakChime() async {
    final prefs = await _open();
    return prefs.getBool(_keyBreakChime) ?? false;
  }

  Future<void> setBreakChime(bool value) async {
    final prefs = await _open();
    await prefs.setBool(_keyBreakChime, value);
  }

  /// Optional home tools are stored together so a newer build can add another
  /// one without scattering more keys through the preferences file.
  Future<HomeAdditionsSettings> getHomeAdditions() async {
    final prefs = await _open();
    final raw = prefs.getString(_keyHomeAdditions);
    if (raw == null || raw.isEmpty) return HomeAdditionsSettings.defaults;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? HomeAdditionsSettings.fromJson(Map<String, dynamic>.from(decoded))
          : HomeAdditionsSettings.defaults;
    } catch (_) {
      return HomeAdditionsSettings.defaults;
    }
  }

  Future<void> setHomeAdditions(HomeAdditionsSettings value) async {
    final prefs = await _open();
    await prefs.setString(_keyHomeAdditions, jsonEncode(value.toJson()));
  }

  Future<WritingJournalSettings> getWritingJournalSettings() async {
    final prefs = await _open();
    final raw = prefs.getString(_keyWritingJournal);
    if (raw == null || raw.isEmpty) return WritingJournalSettings.defaults;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? WritingJournalSettings.fromJson(Map<String, dynamic>.from(decoded))
          : WritingJournalSettings.defaults;
    } catch (_) {
      return WritingJournalSettings.defaults;
    }
  }

  Future<void> setWritingJournalSettings(WritingJournalSettings value) async {
    final prefs = await _open();
    await prefs.setString(_keyWritingJournal, jsonEncode(value.toJson()));
  }

  Future<int?> getInterfaceTextScalePercent() async {
    final prefs = await _open();
    return prefs.getInt(_keyInterfaceTextScale);
  }

  Future<void> setInterfaceTextScalePercent(int percent) async {
    if (!const {100, 125, 160, 200}.contains(percent)) {
      throw ArgumentError.value(percent, 'percent', 'unsupported text size');
    }
    final prefs = await _open();
    await prefs.setInt(_keyInterfaceTextScale, percent);
  }

  Future<bool> getAutoNightTheme() async {
    final prefs = await _open();
    return prefs.getBool(_keyAutoNightTheme) ?? false;
  }

  Future<void> setAutoNightTheme(bool value) async {
    final prefs = await _open();
    await prefs.setBool(_keyAutoNightTheme, value);
  }

  /// The writer's own name, used to sign the client update email.
  /// Empty when not set — the email then simply omits the signature.
  Future<String> getSoferName() async {
    final prefs = await _open();
    return prefs.getString(_keySoferName) ?? '';
  }

  Future<void> setSoferName(String name) async {
    final prefs = await _open();
    await prefs.setString(_keySoferName, name.trim());
  }

  Future<void> saveExpenses(List<Expense> expenses) =>
      _saveList(_keyExpenses, expenses.map((e) => e.toJson()).toList());

  Future<List<Expense>> loadExpenses() async {
    final prefs = await _open();
    return _parseList(prefs.getString(_keyExpenses), Expense.fromJson);
  }
}
