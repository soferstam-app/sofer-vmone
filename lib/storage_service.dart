import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

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

  Future<void> saveProjects(List<Project> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(projects.map((p) => p.toJson()).toList());
    await prefs.setString(_keyProjects, data);
  }

  Future<List<Project>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_keyProjects);
    if (data == null) return [];
    final List<dynamic> jsonList = jsonDecode(data);
    return jsonList.map((json) => Project.fromJson(json)).toList();
  }

  Future<void> saveHistory(List<WorkSession> history) async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(history.map((s) => s.toJson()).toList());
    await prefs.setString(_keyHistory, data);
  }

  Future<List<WorkSession>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_keyHistory);
    if (data == null) return [];
    final List<dynamic> jsonList = jsonDecode(data);
    return jsonList.map((json) => WorkSession.fromJson(json)).toList();
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

  Future<void> saveLastPosition(String projectId, int page, int line) async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_keyLastPositions);
    Map<String, dynamic> allPositions = data != null ? jsonDecode(data) : {};
    allPositions[projectId] = {'page': page, 'line': line};
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

  Future<bool> getFridayMotzeiHalfDay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFridayMotzeiHalfDay) ?? false;
  }

  Future<void> setFridayMotzeiHalfDay(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFridayMotzeiHalfDay, value);
  }

  Future<bool> getUseGregorianDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseGregorianDates) ?? false;
  }

  Future<void> setUseGregorianDates(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseGregorianDates, value);
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

  Future<void> saveExpenses(List<Expense> expenses) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _keyExpenses, jsonEncode(expenses.map((e) => e.toJson()).toList()));
  }

  Future<List<Expense>> loadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_keyExpenses);
    if (data == null) return [];
    final List<dynamic> list = jsonDecode(data);
    return list
        .map((e) => Expense.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
