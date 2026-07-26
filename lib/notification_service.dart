import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'storage_service.dart';

class NotificationService {
  static NotificationService? _instance;

  factory NotificationService() {
    _instance ??= NotificationService._internal();
    return _instance!;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final StorageService _storage = StorageService();

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));
    } catch (e) {
      tz.setLocalLocation(tz.local);
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> scheduleDailyReminder() async {
    if (!Platform.isAndroid) return;

    if (!await _storage.getNotificationEnabled()) {
      await cancelDailyReminder();
      return;
    }

    final TimeOfDay time = await _storage.getNotificationTime();

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        0,
        'תזכורת כתיבה 📜',
        'האם עמדת ביעד הכתיבה היומי שלך? זה הזמן להשלים!',
        _nextInstanceOfTime(time),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder_channel',
            'תזכורות יומיות',
            channelDescription: 'תזכורת יומית לכתיבה',
            importance: Importance.max,
            priority: Priority.high,
            // sound: RawResourceAndroidNotificationSound('shofar'),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint("Error scheduling notification: $e");
    }
  }

  Future<void> cancelDailyReminder() async {
    if (!Platform.isAndroid) return;

    await flutterLocalNotificationsPlugin.cancel(0);
  }

  /// Schedules a one-time notification "סיום הפסקה – חזור לכתיבה" after [minutes].
  /// Uses notification id 1 (daily reminder uses 0).
  Future<void> scheduleBreakReminder(int minutes) async {
    if (!Platform.isAndroid || minutes < 1) return;
    cancelBreakReminder();
    try {
      final tz.TZDateTime when = tz.TZDateTime.now(tz.local).add(
        Duration(minutes: minutes),
      );
      await flutterLocalNotificationsPlugin.zonedSchedule(
        1,
        'סיום הפסקה ☕',
        'הזמן שהקצבת להפסקה הסתיים – חזור לכתיבה',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'break_reminder_channel',
            'תזכורת הפסקה',
            channelDescription: 'תזכורת כשזמן ההפסקה שהקצבת הסתיים',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint("Error scheduling break reminder: $e");
    }
  }

  Future<void> cancelBreakReminder() async {
    if (!Platform.isAndroid) return;
    await flutterLocalNotificationsPlugin.cancel(1);
  }

  tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
