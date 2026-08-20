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
/// Two instruments, each for what it is good at. A monotonic clock measures the
/// stretch the app has been running for, because it cannot be corrected,
/// changed by hand or moved by daylight saving in the middle of a sitting. The
/// wall clock records when the sitting began and takes over for exactly one
/// thing: the stretch the app was not running for, which nothing monotonic
/// survives — and a sofer who closes the app mid-sitting, or whose phone closes
/// it for him, must not lose the hour.
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

  /// A clock that only ever moves forward, used to measure the stretch the app
  /// has been running for.
  ///
  /// The wall clock is not a reliable instrument for measuring a duration. It
  /// gets corrected by the network, changed by hand, and moved by daylight
  /// saving — and any of those in the middle of a sitting silently added or
  /// removed writing time that never happened, with nothing left to recover it
  /// from. This one cannot jump. It also cannot survive the process dying,
  /// which is the one case that still falls back to the wall clock, and it does
  /// so exactly once, at [restoreFrom].
  final Duration Function() _monotonic;

  TimerController({
    required this.onTick,
    StorageService? storage,
    DateTime Function()? now,
    Duration Function()? monotonic,
  })  : _storage = storage ?? StorageService(),
        _now = now ?? DateTime.now,
        _monotonic = monotonic ?? _sinceProcessStart;

  Timer? _ticker;
  bool _isRunning = false;

  /// The monotonic reading when the current run began.
  Duration _runMark = Duration.zero;

  /// When the current break began, or null when the writer is not on one.
  /// A timestamp for the same reason the writing time is one.
  DateTime? _breakStartedAt;

  DateTime? _startedAt;
  DateTime? _endedAt;

  /// Writing time confirmed before the current run — banked at every pause, and
  /// once more at a restore for the stretch the app was not running for.
  Duration _banked = Duration.zero;
  bool _isPaused = false;
  Duration _lastLap = Duration.zero;
  Duration _lastSitting = Duration.zero;
  Duration _breakSoFar = Duration.zero;

  bool get isRunning => _isRunning;
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
  /// What was banked before the current run, plus what the monotonic clock has
  /// measured since it began.
  Duration get elapsed => _banked + _sinceRunStart;

  Duration get _sinceRunStart =>
      _isRunning ? _monotonic() - _runMark : Duration.zero;

  /// Time since the writer last marked a line finished.
  Duration get sinceLastLap {
    final since = elapsed - _lastLap;
    return since.isNegative ? Duration.zero : since;
  }

  void start() {
    _isPaused = false;
    if (isRunning) return;

    if (_breakStartedAt != null) {
      _breakSoFar += breakElapsed;
      _breakStartedAt = null;
    }
    _isRunning = true;
    _runMark = _monotonic();
    _startedAt ??= _now();
    _startTicking();
    _storage.clearTimerState();
  }

  void pause() {
    // Banked, so the time already written survives the pause and, through
    // toJson, the app being closed.
    _banked += _sinceRunStart;
    _isRunning = false;
    _startedAt = null;
    _isPaused = true;
    _breakStartedAt = _now();
    // The ticker keeps going. It used to be cancelled here, and that was right
    // while a break had nothing on screen that moved: the writing time is
    // banked and does not change. The break clock does, and a screen that only
    // catches up when the widget happens to rebuild is a screen that looks
    // frozen -- which is exactly how it was reported.
    _startTicking();
  }

  void _startTicking() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => onTick());
  }

  /// Ends the sitting and reports what it came to.
  StoppedSitting stop() {
    final worked = elapsed;
    // The break in progress counts too. Stopping straight out of a break used
    // to report the sitting as having had none, because only finished breaks
    // had been banked — and stopping from a break is the ordinary way a sitting
    // ends.
    final onBreak = _breakSoFar + breakElapsed;

    _isRunning = false;
    _ticker?.cancel();
    _breakStartedAt = null;
    _isPaused = false;
    _endedAt = _now();
    _lastSitting = worked;
    _lastLap = Duration.zero;
    _startedAt = null;
    _banked = Duration.zero;
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
        'accumulatedElapsedSeconds': _banked.inSeconds,
        'breakStartedAt': _breakStartedAt?.toIso8601String(),
        'accumulatedBreakSeconds': _breakSoFar.inSeconds,
        // The line clock is part of the sitting, not decoration. Without its
        // checkpoint a restored timer showed the whole sitting as the current
        // line until the next press of "סיימתי שורה".
        'lastLapElapsedSeconds': _lastLap.inSeconds,
      };

  /// Picks a sitting back up. Returns true when the clock is running again, so
  /// the screen knows to start its animation.
  bool restoreFrom(Map<String, dynamic> state) {
    final isPaused = state['isPaused'] == true;
    _banked = Duration(
        seconds: (state['accumulatedElapsedSeconds'] as num?)?.toInt() ?? 0);
    _lastLap = Duration(
        seconds: (state['lastLapElapsedSeconds'] as num?)?.toInt() ?? 0);
    _breakSoFar = Duration(
        seconds: (state['accumulatedBreakSeconds'] as num?)?.toInt() ?? 0);
    final started = state['sessionStartTime'] as String?;
    // A paused sitting has no start to count from: its time is all banked.
    final resumedFrom =
        started != null && !isPaused ? DateTime.tryParse(started) : null;
    _isPaused = isPaused;
    _startedAt = null;

    if (isPaused) {
      final breakStarted = state['breakStartedAt'] as String?;
      // New states retain the original wall-clock mark so a break continues
      // while the process is closed. An older state has no recoverable mark;
      // continue from restore time instead of inventing elapsed break time.
      _breakStartedAt = breakStarted == null
          ? _now()
          : DateTime.tryParse(breakStarted) ?? _now();
      _startTicking();
      return false;
    }

    if (resumedFrom == null) return false;

    // The stretch while the app was not running can only be measured by the
    // wall clock — nothing monotonic survives a process dying. It is folded
    // into the bank once, here, and the monotonic clock takes over from now on.
    final away = _now().difference(resumedFrom);
    if (away > Duration.zero) _banked += away;

    _startedAt = _now();
    _isRunning = true;
    _runMark = _monotonic();
    _startTicking();
    return true;
  }

  // --- Android: keeping time while the app is in the background -------------

  /// Android stops timers in a backgrounded app, so a sitting left running
  /// would freeze. A foreground service holds it, and shows the time in a
  /// notification while it does.
  Future<void> initForegroundService() async {
    if (!Platform.isAndroid) return;
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
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
      value: _banked.inSeconds,
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

/// One monotonic clock for the process, started the first time anything asks.
final Stopwatch _processClock = Stopwatch()..start();

Duration _sinceProcessStart() => _processClock.elapsed;
