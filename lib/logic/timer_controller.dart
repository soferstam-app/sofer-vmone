import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../format.dart';
import '../storage_service.dart';
import '../timer_foreground_task.dart';

/// What a finished sitting produced.
class StoppedSitting {
  /// Time actually spent writing.
  final Duration worked;

  /// Time spent on breaks during it, which is excluded from the writing
  /// average — a cup of coffee is not slow writing.
  final Duration onBreak;

  /// When the sitting ended, which is what dates the record.
  final DateTime endedAt;

  const StoppedSitting({
    required this.worked,
    required this.onBreak,
    required this.endedAt,
  });
}

/// The stopwatch behind a sitting.
///
/// Time is kept as timestamps and not as a [Stopwatch]'s own count. A Stopwatch
/// stops when the process is killed, and a sofer who closes the app mid-sitting
/// — or whose phone decides to close it for him — must not lose the hour. The
/// Stopwatch that is here answers only whether the clock is running.
///
/// Pulled out of the home screen, where it was tangled with the entry form and
/// the smart workflow through a dozen fields nobody could hold in their head at
/// once. It knows nothing about widgets: the screen gives it a callback to
/// rebuild on, and reads the state back.
class TimerController {
  /// Called once a second while the clock runs, for the screen to rebuild on.
  final VoidCallback onTick;

  final StorageService _storage;

  /// Injectable so the arithmetic can be tested without waiting for real
  /// seconds to pass.
  final DateTime Function() _now;

  TimerController({
    required this.onTick,
    StorageService? storage,
    DateTime Function()? now,
  })  : _storage = storage ?? StorageService(),
        _now = now ?? DateTime.now;

  final Stopwatch _running = Stopwatch();
  Timer? _ticker;

  /// When the current break began, or null when the writer is not on one.
  /// A timestamp for the same reason the writing time is one.
  DateTime? _breakStartedAt;

  DateTime? _startedAt;
  DateTime? _endedAt;
  int _accumulatedSeconds = 0;
  bool _isPaused = false;
  Duration _lastLap = Duration.zero;
  Duration _lastSitting = Duration.zero;
  Duration _breakSoFar = Duration.zero;

  bool get isRunning => _running.isRunning;
  bool get isPaused => _isPaused;

  /// Running or paused — a sitting is under way either way.
  bool get isActive => isRunning || _isPaused;

  DateTime? get startedAt => _startedAt;

  /// When the last sitting ended. What dates a record made from it.
  DateTime? get endedAt => _endedAt;

  /// How long the last sitting ran, kept after [stop] so the entry form can
  /// state it.
  Duration get lastSitting => _lastSitting;

  /// How long the current break has been running.
  Duration get breakElapsed {
    final since = _breakStartedAt;
    return since == null ? Duration.zero : _now().difference(since);
  }

  /// Time written so far in this sitting.
  ///
  /// The accumulated seconds from before the last pause, plus however long it
  /// has been running since — worked out from the clock, so it stays right
  /// across a restart.
  Duration get elapsed {
    final started = _startedAt;
    final since = started == null ? 0 : _now().difference(started).inSeconds;
    return Duration(seconds: _accumulatedSeconds + since);
  }

  /// Time since the writer last marked a line finished.
  Duration get sinceLastLap => elapsed - _lastLap;

  void start() {
    _isPaused = false;
    if (isRunning) return;

    if (_breakStartedAt != null) {
      _breakSoFar += breakElapsed;
      _breakStartedAt = null;
    }
    _running.start();
    _startedAt ??= _now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => onTick());
    _storage.clearTimerState();
  }

  void pause() {
    final started = _startedAt;
    if (started != null) {
      // Banked, so that the time already written survives the pause without
      // depending on a Stopwatch that a restart would reset.
      _accumulatedSeconds += _now().difference(started).inSeconds;
      _startedAt = null;
    }
    _running.stop();
    _ticker?.cancel();
    _isPaused = true;
    _breakStartedAt = _now();
  }

  /// Ends the sitting and reports what it came to.
  StoppedSitting stop() {
    final worked = elapsed;
    // The break in progress counts too. Stopping straight out of a break used
    // to report the sitting as having had none, because only finished breaks
    // had been banked — and stopping from a break is the ordinary way a sitting
    // ends.
    final onBreak = _breakSoFar + breakElapsed;

    _running.stop();
    _running.reset();
    _ticker?.cancel();
    _breakStartedAt = null;
    _isPaused = false;
    _endedAt = _now();
    _lastSitting = worked;
    _lastLap = Duration.zero;
    _startedAt = null;
    _accumulatedSeconds = 0;
    _breakSoFar = Duration.zero;

    _storage.clearTimerState();
    return StoppedSitting(worked: worked, onBreak: onBreak, endedAt: _endedAt!);
  }

  /// Marks a line finished, and reports how long it took.
  Duration recordLap() {
    final now = elapsed;
    final lap = now - _lastLap;
    _lastLap = now;
    return lap;
  }

  /// Forgets the break time banked so far, for a break the writer says was not
  /// one.
  void clearBreaks() => _breakSoFar = Duration.zero;

  // --- Surviving a restart --------------------------------------------------

  /// The timer's own part of the stored sitting. The screen adds what it knows
  /// — which commission, and where in it — and stores the two together.
  Map<String, dynamic> toJson() => {
        'isPaused': _isPaused,
        'sessionStartTime': _startedAt?.toIso8601String(),
        'accumulatedElapsedSeconds': _accumulatedSeconds,
      };

  /// Picks a sitting back up. Returns true when the clock is running again, so
  /// the screen knows to start its animation.
  bool restoreFrom(Map<String, dynamic> state) {
    final isPaused = state['isPaused'] == true;
    _accumulatedSeconds =
        (state['accumulatedElapsedSeconds'] as num?)?.toInt() ?? 0;
    final started = state['sessionStartTime'] as String?;
    // A paused sitting has no start to count from: its time is all banked.
    _startedAt =
        started != null && !isPaused ? DateTime.tryParse(started) : null;
    _isPaused = isPaused;

    if (_startedAt == null) return false;
    _running.start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => onTick());
    return true;
  }

  // --- Android: keeping time while the app is in the background -------------

  /// Android stops timers in a backgrounded app, so a sitting left running
  /// would freeze. A foreground service holds it, and shows the time in a
  /// notification while it does.
  Future<void> initForegroundService() async {
    if (!Platform.isAndroid) return;
    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sofer_vmone_timer',
        channelName: 'טיימר סופר ומונה',
        channelDescription: 'התראה כשהטיימר רץ ברקע',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
  }

  Future<void> startForegroundService() async {
    final started = _startedAt;
    if (!Platform.isAndroid || started == null) return;
    await FlutterForegroundTask.saveData(
      key: 'timerSessionStartTime',
      value: started.toIso8601String(),
    );
    await FlutterForegroundTask.saveData(
      key: 'timerAccumulatedSeconds',
      value: _accumulatedSeconds,
    );
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'סופר ומונה – טיימר פעיל',
      notificationText: formatClock(elapsed),
      callback: startTimerForegroundCallback,
    );
  }

  Future<void> stopForegroundService() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.stopService();
  }

  void dispose() => _ticker?.cancel();
}
