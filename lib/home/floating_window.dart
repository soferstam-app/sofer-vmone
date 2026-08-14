import 'package:flutter/material.dart';

import '../format.dart';
import '../logic/timer_controller.dart';
import '../theme/app_theme.dart';

/// The timer as a small always-on-top window, for writing at a desk.
///
/// A sofer at a computer wants the clock visible and everything else out of the
/// way, so on Windows the whole app shrinks to this. It needs nothing from the
/// home screen but the clock and four things to do with it, which is why it can
/// stand on its own — it was seventy lines in the middle of a screen it has
/// nothing else to do with.
///
/// It used to be exempt from the themes on the argument that a control surface
/// wants contrast rather than character. That reasoning does not survive
/// contact with the thing: a writer who chose parchment and shrank the window
/// got a deep purple box on his desk, belonging to no app he recognised. The
/// palettes are already built for reading at length, so each of them has a
/// paper and an ink that carry across a desk perfectly well — and the one that
/// does not want a bright box in the corner is exactly the writer who chose
/// the night theme.
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
    required Color foreground,
  }) =>
      IconButton.filled(
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    return Material(
      color: t.paper,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatClock(clock.elapsed),
                style: TextStyle(
                  color: t.ink,
                  fontFamily: t.numeralFamily,
                  fontSize: 42,
                  fontWeight: FontWeight.w300,
                  // Tabular figures, or the digits shift the whole clock
                  // sideways every time a 1 goes by.
                  fontFeatures: const [FontFeature.tabularFigures()],
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
                    background: t.caution,
                    foreground: t.paper,
                  ),
                  _button(
                    onPressed: onStop,
                    icon: Icons.stop,
                    tooltip: "סיום",
                    background: t.danger,
                    foreground: t.paper,
                  ),
                  // Marking a line finished means nothing during a break: the
                  // time it would report is time nobody was writing.
                  if (!clock.isPaused)
                    _button(
                      onPressed: onLap,
                      icon: Icons.flag,
                      tooltip: "סיום שורה",
                      background: t.accent,
                      foreground: t.paper,
                    ),
                  _button(
                    onPressed: onRestore,
                    icon: Icons.open_in_full,
                    tooltip: "החזר חלון",
                    // The way out, not an action on the sitting — drawn as part
                    // of the surface rather than as a fourth coloured button.
                    background: t.rule,
                    foreground: t.ink,
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
