import 'dart:io';
import 'package:flutter/foundation.dart';
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
  /// Android only. Guarded with [kIsWeb] first because `Platform` throws
  /// there rather than answering, which took the whole app down at startup —
  /// a white screen before the first frame, from a getter asking which OS it
  /// was on.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

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

  /// Android's own interface to the plugin, or null off Android.
  AndroidFlutterLocalNotificationsPlugin? get _android =>
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Asks for the permissions a reminder needs, and reports whether it got the
  /// one that lets it fire at a chosen minute.
  ///
  /// Called when the writer turns reminders on, which is the only moment a
  /// permission prompt makes sense: he has just said he wants this.
  ///
  /// Two separate permissions. Posting a notification at all is the first, and
  /// without it nothing arrives. Scheduling an *exact* alarm is the second, and
  /// Android 12 and later withhold it until it is asked for — so the app
  /// declared SCHEDULE_EXACT_ALARM in the manifest, scheduled with
  /// exactAllowWhileIdle, never asked, and let the resulting exception fall
  /// into a catch. The setting said reminders were on and none could be booked.
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;
    final android = _android;
    if (android == null) return false;

    await android.requestNotificationsPermission();
    final exact = await android.requestExactAlarmsPermission();
    return exact ?? false;
  }

  /// Whether this device will let the reminder fire at the minute asked for.
  ///
  /// False is not a failure: the reminder still goes out, within a window
  /// Android chooses. A writer told "about eight" and reminded at ten past is
  /// served; a writer told nothing and reminded never is not.
  Future<bool> canScheduleExactly() async {
    if (!isSupported) return false;
    return (await _android?.canScheduleExactNotifications()) ?? false;
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

    // Exact where the device allows it, roughly where it does not. Scheduling
    // exactly without permission throws, and the catch below would have
    // swallowed every day of the week one at a time.
    final mode = await canScheduleExactly()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    for (final moment in when) {
      // Whether this booking lands on today's working day — nothing more.
      //
      // It used to count the first booking as today's whatever day it fell on,
      // and once the hour had passed the first booking is *tomorrow's*. So a
      // writer who met his target in the evening had tomorrow's reminder
      // dropped as though it were tonight's, and the day after arrived with a
      // message about a day already gone.
      final isToday = ReminderPlan.workingDay(moment, dayStart) == today;
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
          androidScheduleMode: mode,
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
  /// The writer's working day, not the civil one. After midnight and before
  /// his day turns over, meeting the target for the day he is still working
  /// cancelled the id belonging to the new calendar date — a reminder for a day
  /// he had not started yet.
  Future<void> cancelTodaysReminder() async {
    if (!isSupported) return;
    final dayStart = await _storage.getDayStart();
    final today = ReminderPlan.workingDay(DateTime.now(), dayStart);
    await flutterLocalNotificationsPlugin.cancel(ReminderSchedule.idFor(today));
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
      // Same fallback as the daily one: a coffee break that ends a few minutes
      // late is a coffee break; one that never ends is a lost sitting.
      final mode = await canScheduleExactly()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
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
        androidScheduleMode: mode,
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

  /// Books the end of the sitting selected on the home-additions screen.
  /// Notification id 2 is kept separate from both the daily ring and breaks.
  Future<void> scheduleWritingEndAlert(DateTime when) async {
    if (!isSupported || !when.isAfter(DateTime.now())) return;
    await cancelWritingEndAlert();
    try {
      final mode = await canScheduleExactly()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      await flutterLocalNotificationsPlugin.zonedSchedule(
        2,
        'זמן הכתיבה הסתיים',
        'הגעת לשעת הסיום שקבעת לישיבה',
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'writing_end_channel',
            'שעת סיום כתיבה',
            channelDescription: 'התראה בשעת הסיום שנבחרה לישיבת כתיבה',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('Error scheduling writing end alert: $e');
    }
  }

  Future<void> cancelWritingEndAlert() async {
    if (!isSupported) return;
    await flutterLocalNotificationsPlugin.cancel(2);
  }
}
