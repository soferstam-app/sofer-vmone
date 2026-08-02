import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../format.dart';
import '../logic/timer_controller.dart';

/// The timer as a small always-on-top window, for writing at a desk.
///
/// A sofer at a computer wants the clock visible and everything else out of the
/// way, so on Windows the whole app shrinks to this. It needs nothing from the
/// home screen but the clock and four things to do with it, which is why it can
/// stand on its own — it was seventy lines in the middle of a screen it has
/// nothing else to do with.
///
/// Deliberately not themed. The ruled and night palettes are for reading a
/// page; this is a control surface glanced at from across a desk, and wants
/// contrast rather than character.
class FloatingTimerWindow extends StatelessWidget {
  final TimerController clock;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onLap;
  final VoidCallback onRestore;

  const FloatingTimerWindow({
    super.key,
    required this.clock,
    required this.onStart,
    required this.onPause,
    required this.onStop,
    required this.onLap,
    required this.onRestore,
  });

  Widget _button({
    required VoidCallback onPressed,
    required IconData icon,
    required String tooltip,
    required Color background,
  }) =>
      IconButton.filled(
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: Colors.white,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.deepPurple.shade900,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatClock(clock.elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w200,
                  // Tabular figures, or the digits shift the whole clock
                  // sideways every time a 1 goes by.
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8,
                children: [
                  _button(
                    onPressed: clock.isPaused ? onStart : onPause,
                    icon: clock.isPaused ? Icons.play_arrow : Icons.pause,
                    tooltip: clock.isPaused ? "המשך" : "הפסקה",
                    background: Colors.orange.shade700,
                  ),
                  _button(
                    onPressed: onStop,
                    icon: Icons.stop,
                    tooltip: "סיום",
                    background: Colors.red.shade700,
                  ),
                  // Marking a line finished means nothing during a break: the
                  // time it would report is time nobody was writing.
                  if (!clock.isPaused)
                    _button(
                      onPressed: onLap,
                      icon: Icons.flag,
                      tooltip: "סיום שורה",
                      background: Colors.blue.shade700,
                    ),
                  _button(
                    onPressed: onRestore,
                    icon: Icons.open_in_full,
                    tooltip: "החזר חלון",
                    background: Colors.white24,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
