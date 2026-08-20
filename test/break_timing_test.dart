// A break against the length the writer set for it.
//
// The rule the writer stated: no length means no chime and no minus. Turning
// the question off in settings removes the only way to name a length, so it
// removes both — which is why every one of these hangs off `target` being null
// rather than off a separate switch.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/break_timing.dart';

void main() {
  BreakCountdown at(int? targetMinutes, int elapsedSeconds) => BreakCountdown(
        target: targetMinutes == null ? null : Duration(minutes: targetMinutes),
        elapsed: Duration(seconds: elapsedSeconds),
      );

  group('without a length nothing is claimed', () {
    test('no countdown, no overrun, nothing on screen', () {
      final open = at(null, 600);
      expect(open.hasTarget, isFalse);
      expect(open.remaining, isNull);
      expect(open.isOverrun, isFalse);
      expect(open.label, isNull);
    });

    test('and no chime, however long it runs', () {
      expect(
        at(null, 3600).chimeDue(
            previousElapsed: const Duration(seconds: 3599), enabled: true),
        isFalse,
      );
    });

    test('zero is not a length either', () {
      expect(at(0, 60).hasTarget, isFalse);
      expect(at(0, 60).label, isNull);
    });
  });

  group('counting down', () {
    test('shows what is left', () {
      expect(at(10, 0).label, '10:00');
      expect(at(10, 90).label, '08:30');
      expect(at(10, 599).label, '00:01');
    });

    test('exactly on the mark is not yet over', () {
      final onTheDot = at(10, 600);
      expect(onTheDot.isOverrun, isFalse);
      expect(onTheDot.label, '00:00');
    });
  });

  group('over the mark', () {
    test('the clock turns negative, which is the whole point', () {
      final over = at(10, 610);
      expect(over.isOverrun, isTrue);
      expect(over.label, '-00:10');
    });

    test('and keeps counting up as a minus', () {
      expect(at(10, 845).label, '-04:05');
      expect(at(5, 1200).label, '-15:00');
    });
  });

  group('the chime', () {
    test('sounds on the tick that crosses the mark', () {
      expect(
        at(10, 600).chimeDue(
            previousElapsed: const Duration(seconds: 599), enabled: true),
        isTrue,
      );
    });

    test('and not again for the rest of the break', () {
      expect(
        at(10, 601).chimeDue(
            previousElapsed: const Duration(seconds: 600), enabled: true),
        isFalse,
      );
      expect(
        at(10, 900).chimeDue(
            previousElapsed: const Duration(seconds: 899), enabled: true),
        isFalse,
      );
    });

    test('not before the mark', () {
      expect(
        at(10, 599).chimeDue(
            previousElapsed: const Duration(seconds: 598), enabled: true),
        isFalse,
      );
    });

    test('not when the writer switched it off', () {
      expect(
        at(10, 600).chimeDue(
            previousElapsed: const Duration(seconds: 599), enabled: false),
        isFalse,
      );
    });

    test('a break that ended while the screen was off still sounds', () {
      // The chime is asked for per tick rather than scheduled, so a jump from
      // before the mark to well past it — the app asleep in between — still
      // crosses it exactly once.
      expect(
        at(10, 780).chimeDue(
            previousElapsed: const Duration(seconds: 120), enabled: true),
        isTrue,
      );
    });
  });
}
