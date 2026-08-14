// A break with a length the writer named, and what the screen says about it.
//
// The break itself has always been measured. What was missing is the thing a
// person actually wants from a coffee break: not "you have been away for
// 14:02" but "you are four minutes over".

/// How a break is running against the time set for it.
class BreakCountdown {
  /// What the writer asked for, or null when he did not say.
  ///
  /// Null is not zero. No target means no countdown, no chime and no overrun —
  /// the break is simply open, which is what turning the question off means.
  final Duration? target;

  /// How long the break has actually run.
  final Duration elapsed;

  const BreakCountdown({required this.target, required this.elapsed});

  bool get hasTarget => target != null && target! > Duration.zero;

  /// Time left, negative once the break has run over.
  ///
  /// Null without a target, so a caller cannot accidentally render a countdown
  /// against a length nobody set.
  Duration? get remaining => hasTarget ? target! - elapsed : null;

  bool get isOverrun {
    final left = remaining;
    return left != null && left.isNegative;
  }

  /// What to put on screen, signed. Null when there is nothing to say.
  ///
  /// The minus is the whole point: a writer glancing over sees at once whether
  /// the number in front of him is time he still has or time he has taken.
  String? get label {
    final left = remaining;
    if (left == null) return null;
    final over = left.isNegative;
    final size = over ? -left : left;
    final minutes = size.inMinutes;
    final seconds = size.inSeconds.remainder(60);
    final clock =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    return over ? '-$clock' : clock;
  }

  /// Whether the chime is due at this tick and was not due at the previous one.
  ///
  /// Asked per tick rather than scheduled, so it holds while the app sleeps and
  /// wakes: a timer that fires on a dead isolate never sounds, and a break that
  /// ended while the screen was off should still be announced when it comes
  /// back. It sounds once — [previousElapsed] is what stops a chime every
  /// second for the rest of the break.
  bool chimeDue({required Duration previousElapsed, required bool enabled}) {
    if (!enabled || !hasTarget) return false;
    return elapsed >= target! && previousElapsed < target!;
  }
}
