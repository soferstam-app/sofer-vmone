// Which key does what, and which key is not allowed to.
//
// The hazard a shortcut carries in an app with text fields is that the writer
// types a page number and the timer stops. Everything here exists to make that
// impossible: bare letters cannot be bound, modifiers are matched exactly, and
// the listener stands down while a field has focus.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/keyboard_shortcuts.dart';

void main() {
  ShortcutBinding of(LogicalKeyboardKey k,
          {bool ctrl = false, bool shift = false, bool alt = false}) =>
      ShortcutBinding(
          keyId: k.keyId, control: ctrl, shift: shift, alt: alt);

  KeyEvent down(LogicalKeyboardKey k) => KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: k,
        timeStamp: Duration.zero,
      );

  group('what may be bound', () {
    test('a bare letter may not — it would fire while typing', () {
      expect(of(LogicalKeyboardKey.keyS).isUsable, isFalse);
    });

    test('the same letter with a modifier may', () {
      expect(of(LogicalKeyboardKey.keyS, ctrl: true).isUsable, isTrue);
      expect(of(LogicalKeyboardKey.keyS, alt: true).isUsable, isTrue);
    });

    test('a function key may, bare — nothing types one', () {
      expect(of(LogicalKeyboardKey.f2).isUsable, isTrue);
      expect(of(LogicalKeyboardKey.f12).isUsable, isTrue);
    });

    test('a bare digit may not', () {
      expect(of(LogicalKeyboardKey.digit1).isUsable, isFalse);
    });

    test('space and enter may — they are what a stopwatch uses', () {
      expect(of(LogicalKeyboardKey.space).isUsable, isTrue);
      expect(of(LogicalKeyboardKey.enter).isUsable, isTrue);
      expect(of(LogicalKeyboardKey.numpadEnter).isUsable, isTrue);
    });

    test('and they are flagged as also pressing whatever has focus', () {
      // Not a reason to forbid them, a reason to hear them carefully.
      expect(of(LogicalKeyboardKey.space).mayActivateFocusedControl, isTrue);
      expect(of(LogicalKeyboardKey.enter).mayActivateFocusedControl, isTrue);
      // With a modifier there is nothing to confuse them with.
      expect(of(LogicalKeyboardKey.space, ctrl: true).mayActivateFocusedControl,
          isFalse);
      expect(of(LogicalKeyboardKey.f2).mayActivateFocusedControl, isFalse);
    });
  });

  group('matching an actual key press', () {
    test('the plain key fires when nothing else is held', () {
      expect(of(LogicalKeyboardKey.f2).matches(down(LogicalKeyboardKey.f2),
          pressed: {LogicalKeyboardKey.f2}),
          isTrue);
    });

    test('and does not when a modifier is', () {
      // Ctrl+F2 is a different combination, and a writer who bound F2 alone
      // should not have it fire when he meant something else.
      expect(
          of(LogicalKeyboardKey.f2).matches(down(LogicalKeyboardKey.f2),
              pressed: {LogicalKeyboardKey.f2, LogicalKeyboardKey.controlLeft}),
          isFalse);
    });

    test('modifiers are matched exactly, not merely present', () {
      final ctrlS = of(LogicalKeyboardKey.keyS, ctrl: true);
      expect(
          ctrlS.matches(down(LogicalKeyboardKey.keyS),
              pressed: {LogicalKeyboardKey.keyS, LogicalKeyboardKey.controlLeft}),
          isTrue);
      expect(
          ctrlS.matches(down(LogicalKeyboardKey.keyS), pressed: {
            LogicalKeyboardKey.keyS,
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.shiftLeft,
          }),
          isFalse,
          reason: 'Ctrl+Shift+S is not Ctrl+S');
    });

    test('either side of a modifier counts', () {
      final ctrlS = of(LogicalKeyboardKey.keyS, ctrl: true);
      expect(
          ctrlS.matches(down(LogicalKeyboardKey.keyS), pressed: {
            LogicalKeyboardKey.keyS,
            LogicalKeyboardKey.controlRight,
          }),
          isTrue);
    });
  });

  group('a modifier on its own', () {
    test('is half a combination, not one', () {
      for (final k in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.shiftRight,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        expect(ShortcutBinding.isModifierKey(k), isTrue, reason: '$k');
      }
      expect(ShortcutBinding.isModifierKey(LogicalKeyboardKey.f2), isFalse);
    });
  });

  group('the map', () {
    test('the defaults are three keys that sit under one hand', () {
      final d = ShortcutMap.defaults;
      expect(d[ShortcutAction.startStop]!.key, LogicalKeyboardKey.f2);
      expect(d[ShortcutAction.takeBreak]!.key, LogicalKeyboardKey.f3);
      expect(d[ShortcutAction.markLine]!.key, LogicalKeyboardKey.f4);
    });

    test('every default is one the app would accept', () {
      for (final b in ShortcutMap.defaults.bindings.values) {
        expect(b.isUsable, isTrue);
      }
    });

    test('finds the action a key press means', () {
      final action = ShortcutMap.defaults.actionFor(down(LogicalKeyboardKey.f3),
          pressed: {LogicalKeyboardKey.f3});
      expect(action, ShortcutAction.takeBreak);
    });

    test('and nothing for a key that means nothing', () {
      expect(
          ShortcutMap.defaults.actionFor(down(LogicalKeyboardKey.keyQ),
              pressed: {LogicalKeyboardKey.keyQ}),
          isNull);
    });
  });

  group('one combination cannot mean two things', () {
    test('a clash is reported, and names the action it already means', () {
      final clash = ShortcutMap.defaults
          .conflictWith(of(LogicalKeyboardKey.f3), except: ShortcutAction.markLine);
      expect(clash, ShortcutAction.takeBreak);
    });

    test('rebinding an action to what it already has is not a clash', () {
      final clash = ShortcutMap.defaults.conflictWith(of(LogicalKeyboardKey.f3),
          except: ShortcutAction.takeBreak);
      expect(clash, isNull);
    });

    test('a free combination is free', () {
      expect(
          ShortcutMap.defaults
              .conflictWith(of(LogicalKeyboardKey.keyS, ctrl: true)),
          isNull);
    });
  });

  group('surviving a restart', () {
    test('a binding comes back the same', () {
      final b = of(LogicalKeyboardKey.keyS, ctrl: true, alt: true);
      expect(ShortcutBinding.decode(b.encode()), b);
    });

    test('the whole map does', () {
      final map = ShortcutMap.defaults
          .withBinding(ShortcutAction.markLine, of(LogicalKeyboardKey.keyL, ctrl: true));
      final back = ShortcutMap.decode(map.encode());
      expect(back[ShortcutAction.markLine], map[ShortcutAction.markLine]);
      expect(back[ShortcutAction.startStop], map[ShortcutAction.startStop]);
    });

    test('nothing stored means the defaults', () {
      expect(ShortcutMap.decode(null)[ShortcutAction.startStop],
          ShortcutMap.defaults[ShortcutAction.startStop]);
    });

    test('one unreadable entry costs one shortcut, not three', () {
      final back = ShortcutMap.decode({
        'startStop': 'rubbish',
        'markLine': of(LogicalKeyboardKey.keyL, ctrl: true).encode(),
      });
      expect(back[ShortcutAction.startStop],
          ShortcutMap.defaults[ShortcutAction.startStop]);
      expect(back[ShortcutAction.markLine]!.key, LogicalKeyboardKey.keyL);
      expect(back[ShortcutAction.takeBreak],
          ShortcutMap.defaults[ShortcutAction.takeBreak]);
    });
  });

  group('how it reads', () {
    test('in the order a person says it', () {
      expect(of(LogicalKeyboardKey.keyS, ctrl: true, shift: true).label,
          'Ctrl + Shift + S');
      expect(of(LogicalKeyboardKey.f2).label, 'F2');
      expect(of(LogicalKeyboardKey.space).label, 'רווח');
      expect(of(LogicalKeyboardKey.enter, ctrl: true).label, 'Ctrl + Enter');
    });
  });
}
