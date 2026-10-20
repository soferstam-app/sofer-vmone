import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'logic/json_compat.dart';

/// Top-level callback for the foreground task (required by the plugin).
@pragma('vm:entry-point')
void startTimerForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(TimerTaskHandler());
}

/// Task handler that updates the notification every second with elapsed time.
class TimerTaskHandler extends TaskHandler {
  DateTime? _sessionStart;
  int _accumulatedSeconds = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final sessionStartStr =
        await FlutterForegroundTask.getData(key: 'timerSessionStartTime');
    final accumulated =
        await FlutterForegroundTask.getData(key: 'timerAccumulatedSeconds');
    // The foreground plugin stores an untyped Object. A stale or hand-edited
    // value must not crash the service (and stop the clock notification).
    if (sessionStartStr is String) {
      _sessionStart = DateTime.tryParse(sessionStartStr);
    }
    _accumulatedSeconds = JsonCompat.intOrNull(accumulated) ?? 0;
    _sessionStart ??= timestamp;
    _updateNotification();
  }

  void _updateNotification() {
    if (_sessionStart == null) return;
    final elapsed = _accumulatedSeconds +
        DateTime.now().difference(_sessionStart!).inSeconds;
    final h = elapsed ~/ 3600;
    final m = (elapsed % 3600) ~/ 60;
    final s = elapsed % 60;
    final text =
        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    FlutterForegroundTask.updateService(notificationText: text);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _updateNotification();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
