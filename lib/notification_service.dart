import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'storage_service.dart';
import 'logic/reminder_schedule.dart';
import 'logic/reminder_plan.dart';

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

  /// Whether this platform has reminders at all.
  ///
  /// Only Android. Windows has no notification plugin here and never had one,
  /// and a desktop writer has the app open in front of him — so rather than
  /// showing a setting that quietly does nothing, there is no setting.
  static bool get isSupported => Platform.isAndroid;

  Future<void> init() async {
    if (!isSupported) return;
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

  /// Books the next week of reminders, one notification per day.
  ///
  /// Called on every app open and after every entry, which keeps the queue
  /// full. Booking rather than repeating is what lets a single day be dropped;
  /// see [ReminderSchedule].
  Future<void> scheduleDailyReminder() async {
    if (!isSupported) return;

    // Clears the ring before refilling it, so a changed hour does not leave
    // yesterday's booking standing at the old time.
    await cancelDailyReminder();
    if (!await _storage.getNotificationEnabled()) return;

    final TimeOfDay time = await _storage.getNotificationTime();
    final smart = await _storage.getSmartReminder();
    final dayStart = await _storage.getDayStart();

    // Everything the reminder knows, it knows now. Nothing runs when it fires.
    final history =
        (await _storage.loadHistory()).where((s) => !s.isDeleted).toList();
    final projects = await _storage.loadProjects();
    final project = ReminderPlan.mostRecent(projects, history);
    final today = ReminderPlan.workingDay(DateTime.now(), dayStart);

    final hour = ReminderPlan.hourFor(
      smart: smart,
      chosenHour: time.hour,
      history: history,
      dayStart: dayStart,
    );

    final when = ReminderSchedule.upcoming(
      from: DateTime.now(),
      hour: hour,
      minute: smart ? 0 : time.minute,
    );

    for (final moment in when) {
      // The first booking is the only one that can be about today, and so the
      // only one that can say anything specific. The rest land on days nothing
      // is known about yet, and a guess made now would be stale on arrival.
      final isToday = ReminderPlan.workingDay(moment, dayStart) == today ||
          moment == when.first;
      final body = isToday
          ? ReminderPlan.todaysMessage(
              project: project,
              history: history,
              day: ReminderPlan.workingDay(moment, dayStart),
              dayStart: dayStart,
            )
          : ReminderPlan.generalMessage;

      // Nothing to remind him of tonight if he has already done it.
      if (isToday &&
          !ReminderPlan.isWorthSending(
            project: project,
            history: history,
            day: today,
            dayStart: dayStart,
          )) {
        continue;
      }

      try {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          ReminderSchedule.idFor(moment),
          'סופר ומונה',
          body,
          tz.TZDateTime.from(moment, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'daily_reminder_channel',
              'תזכורות יומיות',
              channelDescription: 'תזכורת יומית לרישום העבודה',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (e) {
        // One day failing to book must not cost the rest of the week.
        debugPrint("Error scheduling reminder for $moment: $e");
      }
    }
  }

  /// Drops today's reminder, leaving the rest of the week standing.
  ///
  /// For when the day's target has already been met: there is nothing to remind
  /// anyone of tonight, and there is everything to remind them of tomorrow.
  Future<void> cancelTodaysReminder() async {
    if (!isSupported) return;
    await flutterLocalNotificationsPlugin
        .cancel(ReminderSchedule.idFor(DateTime.now()));
  }

  /// Clears the whole queue — for the setting being turned off, and before it
  /// is refilled.
  Future<void> cancelDailyReminder() async {
    if (!isSupported) return;

    for (final id in ReminderSchedule.allIds) {
      await flutterLocalNotificationsPlugin.cancel(id);
    }
    // The single repeating reminder this replaced. Cancelled once so that an
    // app updated from an older build does not keep firing it for ever beside
    // the new ones — nothing here can reach it after this.
    await flutterLocalNotificationsPlugin.cancel(0);
  }

  /// Schedules a one-time notification "סיום הפסקה – חזור לכתיבה" after [minutes].
  /// Uses notification id 1 (daily reminder uses 0).
  Future<void> scheduleBreakReminder(int minutes) async {
    if (!isSupported || minutes < 1) return;
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
    if (!isSupported) return;
    await flutterLocalNotificationsPlugin.cancel(1);
  }
}
