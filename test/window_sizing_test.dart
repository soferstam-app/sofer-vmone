// How large the window opens.
//
// The rule that needs a test is the second one: a size remembered from a large
// monitor must not be imposed on a small screen. A window wider than the
// display puts its own title bar out of reach, and a mouse cannot get it back.

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/window_sizing.dart';

void main() {
  // Screens a sofer plausibly opens this on.
  const laptop = Size(1366, 728); // 1366x768 less a taskbar
  const desktop = Size(1920, 1040);
  const big = Size(3840, 2120);
  const tiny = Size(1024, 600); // an old netbook

  group('a first launch', () {
    test('opens at the stated default when there is room', () {
      final size = WindowSizing.startup(remembered: null, available: desktop);
      expect(size, const Size(1280, 720));
    });

    test('never opens larger than the default, whatever the screen', () {
      for (final screen in [desktop, big]) {
        final size = WindowSizing.startup(remembered: null, available: screen);
        expect(size.width, lessThanOrEqualTo(WindowSizing.preferred.width));
        expect(size.height, lessThanOrEqualTo(WindowSizing.preferred.height));
      }
    });

    test('shrinks below the default on a screen that cannot hold it', () {
      final size = WindowSizing.startup(remembered: null, available: tiny);
      expect(size.width, lessThan(1280));
      expect(size.height, lessThan(720));
    });
  });

  group('the size the writer left it at', () {
    test('comes back', () {
      final size =
          WindowSizing.startup(remembered: const Size(1000, 800), available: desktop);
      expect(size, const Size(1000, 800));
    });

    test('may be larger than the default, because he chose it', () {
      final size =
          WindowSizing.startup(remembered: const Size(1700, 950), available: desktop);
      expect(size.width, greaterThan(WindowSizing.preferred.width));
    });

    test('is cut down to a smaller screen', () {
      // Remembered on the 4K monitor, opened on the laptop that evening.
      final size =
          WindowSizing.startup(remembered: const Size(3200, 1800), available: laptop);
      expect(size.width, lessThan(laptop.width));
      expect(size.height, lessThan(laptop.height));
    });
  });

  group('what must be true on every screen', () {
    final screens = [tiny, laptop, desktop, big];
    final remembered = [
      null,
      const Size(1, 1),
      const Size(800, 600),
      const Size(9999, 9999),
      const Size(3200, 1800),
    ];

    test('the window always fits the display', () {
      for (final screen in screens) {
        for (final was in remembered) {
          final size = WindowSizing.startup(remembered: was, available: screen);
          expect(size.width, lessThanOrEqualTo(screen.width),
              reason: 'was $was on $screen');
          expect(size.height, lessThanOrEqualTo(screen.height),
              reason: 'was $was on $screen');
        }
      }
    });

    test('and never opens unusably small', () {
      for (final screen in screens) {
        for (final was in remembered) {
          final size = WindowSizing.startup(remembered: was, available: screen);
          expect(size.width,
              greaterThanOrEqualTo(min(WindowSizing.minimum.width, screen.width)),
              reason: 'was $was on $screen');
        }
      }
    });

    test('and leaves some of the desktop showing', () {
      for (final screen in screens) {
        final size = WindowSizing.startup(remembered: null, available: screen);
        expect(size.width, lessThan(screen.width));
      }
    });
  });

  group('what is not worth storing', () {
    test('a minimised or collapsed window', () {
      expect(WindowSizing.worthRemembering(const Size(0, 0)), isFalse);
      expect(WindowSizing.worthRemembering(const Size(120, 90)), isFalse);
      // The floating timer window, which is not the main window's size.
      expect(WindowSizing.worthRemembering(const Size(320, 260)), isFalse);
    });

    test('an ordinary one is', () {
      expect(WindowSizing.worthRemembering(const Size(1280, 720)), isTrue);
      expect(WindowSizing.worthRemembering(WindowSizing.minimum), isTrue);
    });
  });
}

double min(double a, double b) => a < b ? a : b;
