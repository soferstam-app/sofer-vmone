// The clock behind a sitting.
//
// It was a dozen fields inside the home screen — two Stopwatches, a periodic
// Timer, two timestamps and a running count of seconds — and the arithmetic
// tying them together could only be checked by sitting and watching. With the
// clock injectable, an hour of writing takes no time at all to test.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/logic/timer_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late Duration mono;
  late TimerController clock;
  late int ticks;

  setUp(() {
    // start() and stop() clear the stored sitting.
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 7, 20, 9);
    mono = Duration.zero;
    ticks = 0;
    clock = TimerController(
        onTick: () => ticks++, now: () => now, monotonic: () => mono);
  });

  tearDown(() => clock.dispose());

  /// Ordinary time passing: both instruments agree.
  void pass(Duration d) {
    now = now.add(d);
    mono += d;
  }

  group('measuring a sitting', () {
    test('counts from the clock, not from a stopwatch', () {
      clock.start();
      pass(const Duration(minutes: 30));
      expect(clock.elapsed, const Duration(minutes: 30));
      expect(clock.isRunning, isTrue);
      expect(clock.isPaused, isFalse);
    });

    test('a pause banks what was written and stops counting', () {
      clock.start();
      pass(const Duration(minutes: 30));
      clock.pause();

      pass(const Duration(minutes: 15));
      expect(clock.elapsed, const Duration(minutes: 30),
          reason: 'a pause is not writing time');
      expect(clock.isPaused, isTrue);
      expect(clock.isRunning, isFalse);
      expect(clock.isActive, isTrue, reason: 'the sitting is still open');
    });

    test('resuming continues from what was banked', () {
      clock.start();
      pass(const Duration(minutes: 30));
      clock.pause();
      pass(const Duration(minutes: 15));
      clock.start();
      pass(const Duration(minutes: 10));

      expect(clock.elapsed, const Duration(minutes: 40));
    });

    test('starting an already running clock changes nothing', () {
      clock.start();
      pass(const Duration(minutes: 10));
      clock.start();
      pass(const Duration(minutes: 5));
      expect(clock.elapsed, const Duration(minutes: 15));
    });
  });

  group('breaks', () {
    test('are counted apart from writing time', () {
      clock.start();
      pass(const Duration(minutes: 20));
      clock.pause();
      pass(const Duration(minutes: 12));
      expect(clock.breakElapsed, const Duration(minutes: 12));
      clock.start();
      pass(const Duration(minutes: 20));

      final sitting = clock.stop();
      expect(sitting.worked, const Duration(minutes: 40));
      expect(sitting.onBreak, const Duration(minutes: 12));
    });

    test('a break still running when the sitting ends is counted', () {
      // Stopping straight out of a break is the ordinary way a sitting ends,
      // and it used to report no break at all.
      clock.start();
      pass(const Duration(minutes: 25));
      clock.pause();
      pass(const Duration(minutes: 10));

      final sitting = clock.stop();
      expect(sitting.worked, const Duration(minutes: 25));
      expect(sitting.onBreak, const Duration(minutes: 10));
    });

    test('can be forgotten, for a break that was not one', () {
      clock.start();
      pass(const Duration(minutes: 10));
      clock.pause();
      pass(const Duration(minutes: 5));
      clock.start();
      clock.clearBreaks();
      expect(clock.stop().onBreak, Duration.zero);
    });
  });

  group('ending a sitting', () {
    test('reports what it came to and leaves the clock at nothing', () {
      clock.start();
      pass(const Duration(hours: 1, minutes: 14));
      final sitting = clock.stop();

      expect(sitting.worked, const Duration(hours: 1, minutes: 14));
      expect(sitting.endedAt, now);
      expect(clock.lastSitting, sitting.worked,
          reason: 'the entry form states it afterwards');
      expect(clock.elapsed, Duration.zero);
      expect(clock.isActive, isFalse);
      expect(clock.endedAt, now);
    });

    test('the next sitting starts from nothing', () {
      clock.start();
      pass(const Duration(minutes: 40));
      clock.stop();

      clock.start();
      pass(const Duration(minutes: 5));
      expect(clock.elapsed, const Duration(minutes: 5));
    });
  });

  group('marking a line finished', () {
    test('reports the time since the last one', () {
      clock.start();
      pass(const Duration(minutes: 4));
      expect(clock.recordLap(), const Duration(minutes: 4));

      pass(const Duration(minutes: 6));
      expect(clock.sinceLastLap, const Duration(minutes: 6));
      expect(clock.recordLap(), const Duration(minutes: 6));

      pass(const Duration(minutes: 3));
      expect(clock.recordLap(), const Duration(minutes: 3));
    });

    test('the current line survives a restart', () {
      clock.start();
      pass(const Duration(minutes: 4));
      clock.recordLap();
      pass(const Duration(minutes: 2));
      final stored = clock.toJson();

      final revived =
          TimerController(onTick: () {}, now: () => now, monotonic: () => mono);
      addTearDown(revived.dispose);
      pass(const Duration(minutes: 3));
      revived.restoreFrom(stored);

      expect(revived.sinceLastLap, const Duration(minutes: 5));
    });
  });

  group('surviving a restart', () {
    test('a running sitting picks up where the clock says it is', () {
      // The whole reason for timestamps: the process died, and the writer was
      // at the desk for another twenty minutes regardless.
      clock.start();
      pass(const Duration(minutes: 30));
      final stored = clock.toJson();

      final revived =
          TimerController(onTick: () {}, now: () => now, monotonic: () => mono);
      addTearDown(revived.dispose);
      pass(const Duration(minutes: 20));

      expect(revived.restoreFrom(stored), isTrue);
      expect(revived.elapsed, const Duration(minutes: 50));
      expect(revived.isRunning, isTrue);
    });

    test('a paused sitting comes back paused, and no time passes', () {
      clock.start();
      pass(const Duration(minutes: 30));
      clock.pause();
      final stored = clock.toJson();

      final revived =
          TimerController(onTick: () {}, now: () => now, monotonic: () => mono);
      addTearDown(revived.dispose);
      pass(const Duration(hours: 8));

      expect(revived.restoreFrom(stored), isFalse,
          reason: 'nothing to resume: the clock is not running');
      expect(revived.elapsed, const Duration(minutes: 30));
      expect(revived.isPaused, isTrue);
      expect(revived.breakElapsed, const Duration(hours: 8),
          reason: 'the break continues while the process is closed');
    });

    test('an empty state leaves the clock stopped at nothing', () {
      expect(clock.restoreFrom(const {}), isFalse);
      expect(clock.elapsed, Duration.zero);
      expect(clock.isActive, isFalse);
    });
  });

  group('a wall clock that jumps mid-sitting', () {
    // The failure this guards: the phone corrects its clock by NTP, or daylight
    // saving arrives, or the writer changes the time by hand — and an hour of
    // writing that never happened was added to the record with nothing left to
    // recover the truth from.
    test('does not add writing time that never happened', () {
      clock.start();
      mono += const Duration(minutes: 10);
      now = now.add(const Duration(hours: 1, minutes: 10));
      expect(clock.elapsed, const Duration(minutes: 10));
    });

    test('does not take writing time away either', () {
      clock.start();
      mono += const Duration(minutes: 40);
      now = now.subtract(const Duration(minutes: 30));
      expect(clock.elapsed, const Duration(minutes: 40));
      expect(clock.stop().worked, const Duration(minutes: 40));
    });

    test('still measures the stretch the app was closed for', () {
      // The one thing the wall clock is the only witness to.
      clock.start();
      pass(const Duration(minutes: 30));
      final stored = clock.toJson();

      final revived =
          TimerController(onTick: () {}, now: () => now, monotonic: () => mono);
      addTearDown(revived.dispose);
      now = now.add(const Duration(minutes: 45));

      expect(revived.restoreFrom(stored), isTrue);
      expect(revived.elapsed, const Duration(minutes: 75));
    });
  });

  group('the tick', () {
    test('runs while writing and stops with it', () {
      expect(ticks, 0);
      clock.start();
      // The periodic timer is real; what matters here is that it is armed while
      // the clock runs and disarmed when it does not.
      clock.pause();
      final atPause = ticks;
      clock.stop();
      expect(ticks, atPause);
    });
  });
}
