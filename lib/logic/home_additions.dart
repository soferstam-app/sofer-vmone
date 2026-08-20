/// Optional tools that may be added to the home screen.
///
/// The switches are deliberately off by default. A timer that changes meaning,
/// a sound that starts ticking, or a celebration that appears without being
/// asked for would all be surprising on an existing installation.
class HomeAdditionsSettings {
  static const defaults = HomeAdditionsSettings();

  final bool celebrateDailyGoal;
  final bool lineTargetEnabled;
  final int lineTargetSeconds;
  final bool metronomeEnabled;
  final int metronomeBpm;
  final bool writingTargetEnabled;
  final int writingTargetMinutes;
  final bool endTimeAlertEnabled;

  /// Minutes after midnight, independent of locale and 12/24-hour display.
  final int endTimeMinutes;

  const HomeAdditionsSettings({
    this.celebrateDailyGoal = false,
    this.lineTargetEnabled = false,
    this.lineTargetSeconds = 300,
    this.metronomeEnabled = false,
    this.metronomeBpm = 60,
    this.writingTargetEnabled = false,
    this.writingTargetMinutes = 90,
    this.endTimeAlertEnabled = false,
    this.endTimeMinutes = 18 * 60,
  });

  HomeAdditionsSettings copyWith({
    bool? celebrateDailyGoal,
    bool? lineTargetEnabled,
    int? lineTargetSeconds,
    bool? metronomeEnabled,
    int? metronomeBpm,
    bool? writingTargetEnabled,
    int? writingTargetMinutes,
    bool? endTimeAlertEnabled,
    int? endTimeMinutes,
  }) =>
      HomeAdditionsSettings(
        celebrateDailyGoal: celebrateDailyGoal ?? this.celebrateDailyGoal,
        lineTargetEnabled: lineTargetEnabled ?? this.lineTargetEnabled,
        lineTargetSeconds:
            (lineTargetSeconds ?? this.lineTargetSeconds).clamp(1, 24 * 3600),
        metronomeEnabled: metronomeEnabled ?? this.metronomeEnabled,
        metronomeBpm: (metronomeBpm ?? this.metronomeBpm).clamp(30, 180),
        writingTargetEnabled: writingTargetEnabled ?? this.writingTargetEnabled,
        writingTargetMinutes:
            (writingTargetMinutes ?? this.writingTargetMinutes)
                .clamp(1, 24 * 60),
        endTimeAlertEnabled: endTimeAlertEnabled ?? this.endTimeAlertEnabled,
        endTimeMinutes:
            (endTimeMinutes ?? this.endTimeMinutes).clamp(0, 24 * 60 - 1),
      );

  Map<String, dynamic> toJson() => {
        'celebrateDailyGoal': celebrateDailyGoal,
        'lineTargetEnabled': lineTargetEnabled,
        'lineTargetSeconds': lineTargetSeconds,
        'metronomeEnabled': metronomeEnabled,
        'metronomeBpm': metronomeBpm,
        'writingTargetEnabled': writingTargetEnabled,
        'writingTargetMinutes': writingTargetMinutes,
        'endTimeAlertEnabled': endTimeAlertEnabled,
        'endTimeMinutes': endTimeMinutes,
      };

  factory HomeAdditionsSettings.fromJson(Map<String, dynamic> json) {
    bool flag(String key) => json[key] is bool ? json[key] as bool : false;
    int number(String key, int fallback, int min, int max) =>
        ((json[key] as num?)?.toInt() ?? fallback).clamp(min, max);

    return HomeAdditionsSettings(
      celebrateDailyGoal: flag('celebrateDailyGoal'),
      lineTargetEnabled: flag('lineTargetEnabled'),
      lineTargetSeconds: number('lineTargetSeconds', 300, 1, 24 * 3600),
      metronomeEnabled: flag('metronomeEnabled'),
      metronomeBpm: number('metronomeBpm', 60, 30, 180),
      writingTargetEnabled: flag('writingTargetEnabled'),
      writingTargetMinutes: number('writingTargetMinutes', 90, 1, 24 * 60),
      endTimeAlertEnabled: flag('endTimeAlertEnabled'),
      endTimeMinutes: number('endTimeMinutes', 18 * 60, 0, 24 * 60 - 1),
    );
  }
}

/// A target expressed as a countdown, including the signed overrun requested
/// for the line clock.
class TargetCountdown {
  final Duration? target;
  final Duration elapsed;

  const TargetCountdown({required this.target, required this.elapsed});

  bool get isEnabled => target != null && target! > Duration.zero;
  bool get isOverrun => isEnabled && elapsed > target!;

  Duration? get difference {
    if (!isEnabled) return null;
    return isOverrun ? elapsed - target! : target! - elapsed;
  }

  String? get label {
    final d = difference;
    if (d == null) return null;
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final value = '$hours:$minutes:$seconds';
    return isOverrun ? '-$value' : value;
  }

  bool crossedSince(Duration previousElapsed) =>
      isEnabled && previousElapsed <= target! && elapsed > target!;
}

/// The next occurrence of a configured wall-clock time.
DateTime nextClockOccurrence(DateTime from, int minutesAfterMidnight) {
  final safe = minutesAfterMidnight.clamp(0, 24 * 60 - 1);
  var result = DateTime(
    from.year,
    from.month,
    from.day,
    safe ~/ 60,
    safe.remainder(60),
  );
  if (!result.isAfter(from)) result = result.add(const Duration(days: 1));
  return result;
}

Duration metronomeInterval(int bpm) => Duration(
    microseconds:
        (Duration.microsecondsPerMinute / bpm.clamp(30, 180)).round());
