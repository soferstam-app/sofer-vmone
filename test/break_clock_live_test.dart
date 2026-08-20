// The clock has to keep ticking through a break.
//
// Reported: "השעון לא חי, רק שאני נכנס למסך אחר וחוזר הוא מתעדכן" — the break
// clock stood still and only jumped when navigating away and back.
//
// The cause was in `pause()`, which cancelled the ticker. That was right for as
// long as a break had nothing on screen that moved: writing time is banked at
// the pause and does not change. The break clock does change, and with no ticks
// nothing asked the screen to redraw — so the number only caught up when a
// rebuild happened for some unrelated reason.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/logic/timer_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// The wall clock does not move when a test pumps, so it is handed one that
  /// does — otherwise a break measured against DateTime.now() is always zero.
  DateTime fake = DateTime(2026, 8, 13, 9);

  testWidgets('a paused sitting still ticks', (tester) async {
    var ticks = 0;
    final clock = TimerController(onTick: () => ticks++, now: () => fake);

    clock.start();
    await tester.pump(const Duration(seconds: 3));
    final whileRunning = ticks;
    expect(whileRunning, greaterThan(0), reason: 'sanity: it ticks when run');

    clock.pause();
    ticks = 0;
    await tester.pump(const Duration(seconds: 3));

    expect(ticks, greaterThan(0),
        reason: 'the break clock needs a redraw every second');
    clock.dispose();
  });

  testWidgets('and the break time it reports actually grows', (tester) async {
    final clock = TimerController(onTick: () {}, now: () => fake);

    clock.start();
    clock.pause();
    final atOnce = clock.breakElapsed;
    fake = fake.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));

    expect(clock.breakElapsed, greaterThan(atOnce));
    clock.dispose();
  });

  testWidgets('stopping ends the ticking', (tester) async {
    var ticks = 0;
    final clock = TimerController(onTick: () => ticks++, now: () => fake);

    clock.start();
    clock.pause();
    clock.stop();
    ticks = 0;
    await tester.pump(const Duration(seconds: 3));

    expect(ticks, 0, reason: 'nothing is running, nothing should redraw');
    clock.dispose();
  });
}
