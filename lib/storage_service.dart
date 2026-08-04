import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logic/currency.dart';
import 'logic/hebrew_clock.dart';
import 'logic/hebrew_work_calendar.dart';
import 'models.dart';
import 'theme/app_theme.dart';

class StorageService {
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
  static const String _keySoferName = 'sofer_name';
  static const String _keyWorkCalendarRules = 'work_calendar_rules';
  static const String _keyDayStart = 'day_start';
  static const String _keyAppTheme = 'app_theme';
  static const String _keyAutoNightTheme = 'auto_night_theme';
  static const String _keyCurrency = 'currency';
  static const String _keyAutoBackupFolder = 'auto_backup_folder';
  static const String _keySmartReminder = 'smart_reminder';

  Future<void> saveProjects(List<Project> projects) =>
      _saveList(_keyProjects, projects.map((p) => p.toJson()).toList());

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
    final prefs = await SharedPreferences.getInstance();
    final written = {
      for (final record in records)
        if (record['id'] is String) record['id'] as String,
    };

    final carried = <dynamic>[];
    for (final entry in _rawEntries(prefs.getString(key))) {
      // An entry with no readable id cannot be matched against what is being
      // written, so it is kept: dropping it would be guessing that it was meant
      // to go, and the guess is unrecoverable.
      final id = entry is Map ? entry['id'] : null;
      if (id is String && written.contains(id)) continue;
      carried.add(entry);
    }

    await prefs.setString(key, jsonEncode([...records, ...carried]));
  }

  /// Empties a stored list outright, tombstones and all.
  ///
  /// The one way to remove a record rather than mark it removed, and it exists
  /// for exactly one caller: the writer asking to erase everything. Nothing
  /// here is recoverable afterwards, which is what makes it the wrong tool for
  /// anything smaller.
  Future<void> eraseList(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// Erases every record the app holds. See [eraseList].
  Future<void> eraseAllRecords() async {
    await eraseList(_keyProjects);
    await eraseList(_keyHistory);
    await eraseList(_keyExpenses);
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

  /// How many stored records this build cannot read, across all three lists.
  ///
  /// They are kept and written back untouched, but they take no part in any
  /// figure the app shows — so the app has to be able to say they are there
  /// rather than quietly reporting totals that are short.
  Future<int> unreadableRecordCount() async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    return _parseList(prefs.getString(_keyProjects), Project.fromJson);
  }

  Future<void> saveHistory(List<WorkSession> history) =>
      _saveList(_keyHistory, history.map((s) => s.toJson()).toList());

  Future<List<WorkSession>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseList(prefs.getString(_keyHistory), WorkSession.fromJson);
  }

  /// Every user-owned value in one map: the three data lists plus all
  /// settings. This is the payload of a backup file — nothing else in the app
  /// holds state worth restoring (timer_state is deliberately excluded, it is
  /// per-device and transient).
  Future<Map<String, dynamic>> exportAll() async {
    final prefs = await SharedPreferences.getInstance();

    // Decoded rather than embedded as raw strings so the backup file is one
    // well-formed document that an importer can validate field by field.
    List<dynamic> decodeList(String? raw) {
      if (raw == null || raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        return decoded is List ? decoded : const [];
      } catch (_) {
        return const [];
      }
    }

    Map<String, dynamic> decodeMap(String? raw) {
      if (raw == null || raw.isEmpty) return const {};
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
      } catch (_) {
        return const {};
      }
    }

    return {
      'projects': decodeList(prefs.getString(_keyProjects)),
      'history': decodeList(prefs.getString(_keyHistory)),
      'expenses': decodeList(prefs.getString(_keyExpenses)),
      'lastPositions': decodeMap(prefs.getString(_keyLastPositions)),
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
        _keyAutoNightTheme: prefs.getBool(_keyAutoNightTheme),
        _keyCurrency: prefs.getString(_keyCurrency),
        // Deliberately *not* restored on another device — see BackupService.
        // A path from one machine means nothing on another.
        _keyAutoBackupFolder: prefs.getString(_keyAutoBackupFolder),
        _keySmartReminder: prefs.getBool(_keySmartReminder),
      },
    };
  }

  Future<bool> getNotificationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyNotificationEnabled) ?? true;
  }

  Future<void> setNotificationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyNotificationEnabled, enabled);
  }

  Future<TimeOfDay> getNotificationTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_keyNotificationTime);
    if (timeStr != null) {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    return const TimeOfDay(hour: 20, minute: 0);
  }

  Future<void> setNotificationTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNotificationTime, '${time.hour}:${time.minute}');
  }

  Future<bool> getSmartWorkflowEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySmartWorkflowEnabled) ?? false;
  }

  Future<void> setSmartWorkflowEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySmartWorkflowEnabled, enabled);
  }

  Future<Map<String, dynamic>> getLastPosition(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_keyLastPositions);
    if (data == null) return {};
    final Map<String, dynamic> allPositions = jsonDecode(data);
    return allPositions[projectId] != null
        ? Map<String, dynamic>.from(allPositions[projectId])
        : {};
  }

  /// Pages and lines are counted from one, so neither is ever stored as zero —
  /// a zero would come back out and be displayed as "עמוד 0".
  Future<void> saveLastPosition(String projectId, int page, int line) async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_keyLastPositions);
    Map<String, dynamic> allPositions = data != null ? jsonDecode(data) : {};
    allPositions[projectId] = {
      'page': page < 1 ? 1 : page,
      'line': line < 1 ? 1 : line,
    };
    await prefs.setString(_keyLastPositions, jsonEncode(allPositions));
  }

  Future<void> saveTimerState(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTimerState, jsonEncode(state));
  }

  Future<Map<String, dynamic>> getTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_keyTimerState);
    if (data == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(data));
    } catch (_) {
      return {};
    }
  }

  Future<void> clearTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTimerState);
  }

  Future<int> getDayRolloverHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyDayRolloverHour) ?? 0;
  }

  Future<void> setDayRolloverHour(int hour) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDayRolloverHour, hour.clamp(0, 23));
  }

  /// When a new working day starts — midnight, sunset, nightfall or a chosen
  /// hour.
  ///
  /// Falls back to the standalone rollover hour this replaced, so a device that
  /// had set 02:00 keeps that boundary without the user touching anything.
  Future<DayStart> getDayStart() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDayStart);
    if (raw != null && raw.isNotEmpty) {
      final decoded = _decodeSettings(raw);
      if (decoded != null) return DayStart.fromJson(decoded);
    }
    return DayStart.fromRolloverHour(prefs.getInt(_keyDayRolloverHour) ?? 0);
  }

  Future<void> setDayStart(DayStart dayStart) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDayStart, jsonEncode(dayStart.toJson()));
    // Kept in step so a build that predates this setting still reads a sensible
    // hour instead of reverting the user to midnight.
    await prefs.setInt(
        _keyDayRolloverHour,
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
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyWorkCalendarRules, jsonEncode(rules.toJson()));
  }

  /// The currency the *next* amount is entered in.
  ///
  /// Only that. Every stored amount carries its own, so changing this settles
  /// nothing about what is already recorded — which is the whole point: a
  /// setting that reached backwards would relabel every price the writer ever
  /// agreed, silently and irreversibly.
  Future<Currency> getCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return Currency.fromJson(prefs.getString(_keyCurrency));
  }

  Future<void> setCurrency(Currency currency) async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_keyAutoBackupFolder);
    return path == null || path.isEmpty ? null : path;
  }

  Future<void> setAutoBackupFolder(String? path) async {
    final prefs = await SharedPreferences.getInstance();
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySmartReminder) ?? false;
  }

  Future<void> setSmartReminder(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySmartReminder, value);
  }

  Future<bool> getUseGregorianDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseGregorianDates) ?? false;
  }

  Future<void> setUseGregorianDates(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseGregorianDates, value);
  }

  /// Which of the three looks the writer picked. Unknown names — from a newer
  /// build that added a fourth — fall back to the modern one rather than
  /// leaving the app unthemed.
  Future<AppTheme> getAppTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return AppTheme.fromName(prefs.getString(_keyAppTheme));
  }

  Future<void> setAppTheme(AppTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppTheme, theme.name);
  }

  /// Whether the app dresses for night on its own between nightfall and dawn.
  Future<bool> getAutoNightTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoNightTheme) ?? false;
  }

  Future<void> setAutoNightTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoNightTheme, value);
  }

  /// The writer's own name, used to sign the client update email.
  /// Empty when not set — the email then simply omits the signature.
  Future<String> getSoferName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySoferName) ?? '';
  }

  Future<void> setSoferName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySoferName, name.trim());
  }

  Future<void> saveExpenses(List<Expense> expenses) =>
      _saveList(_keyExpenses, expenses.map((e) => e.toJson()).toList());

  Future<List<Expense>> loadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseList(prefs.getString(_keyExpenses), Expense.fromJson);
  }
}
