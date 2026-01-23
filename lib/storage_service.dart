import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class StorageService {
  static const String _keyProjects = 'projects';
  static const String _keyHistory = 'history';

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

  // פונקציה לקריאת הנתונים הגולמיים לצורך תצוגה או גיבוי
  Future<String> getRawExport() async {
    final prefs = await SharedPreferences.getInstance();
    final projects = prefs.getString(_keyProjects) ?? "[]";
    final history = prefs.getString(_keyHistory) ?? "[]";
    return '{"projects": $projects, "history": $history}';
  }
}
