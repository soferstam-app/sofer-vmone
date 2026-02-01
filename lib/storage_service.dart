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
  static const String _keyDayRolloverHour = 'day_rollover_hour';
  static const String _keyFridayMotzeiHalfDay = 'friday_motzei_half_day';
  static const String _keyUseGregorianDates = 'use_gregorian_dates';
  static const String _keyExpenses = 'expenses';

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

  Future<String> getRawExport() async {
    final prefs = await SharedPreferences.getInstance();
    final projects = prefs.getString(_keyProjects) ?? "[]";
    final history = prefs.getString(_keyHistory) ?? "[]";
    return '{"projects": $projects, "history": $history}';
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
