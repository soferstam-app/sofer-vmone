import 'package:flutter/services.dart';

/// The three things a sofer does with the clock while he is writing.
///
/// Deliberately three. A shortcut is worth learning only for something done
/// often enough to resent reaching for, and everything else in the app is done
/// once a sitting or once a month.
enum ShortcutAction {
  startStop,
  takeBreak,
  markLine;

  String get label => switch (this) {
        ShortcutAction.startStop => 'התחלה ועצירה',
        ShortcutAction.takeBreak => 'הפסקה והמשך',
        ShortcutAction.markLine => 'סיימתי שורה',
      };

  String get describe => switch (this) {
        ShortcutAction.startStop =>
          'מתחיל ישיבה, ובאמצע ישיבה מסיים ושומר אותה',
        ShortcutAction.takeBreak => 'יוצא להפסקה, ובהפסקה חוזר לכתוב',
        ShortcutAction.markLine => 'מסמן שורה שהסתיימה ומודד את זמנה',
      };
}

/// One key and the modifiers held with it.
///
/// Stored rather than the raw event so a binding survives a restart, and
/// compared by value so two bindings that mean the same combination are the
/// same combination.
class ShortcutBinding {
  /// The logical key's id — what `LogicalKeyboardKey.keyId` gives. A number
  /// rather than a name because it is what the framework compares on, and
  /// because a name would have to be translated back on the way in.
  final int keyId;

  final bool control;
  final bool shift;
  final bool alt;

  const ShortcutBinding({
    required this.keyId,
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  LogicalKeyboardKey get key => LogicalKeyboardKey(keyId);

  /// Whether this key can stand on its own, without a modifier.
  ///
  /// The hazard a bare key carries is being typed rather than pressed: a writer
  /// entering a page number would stop his own timer. Text fields are already
  /// guarded separately — the listener stands down entirely while one has focus
  /// — so what is refused here is narrower than it first looks.
  ///
  /// Space and Enter are allowed, and should be: they are what every stopwatch
  /// uses, and nobody types either into a number. They carry a different
  /// hazard, which is that they also activate whatever control has focus, and
  /// that is handled where the key is heard rather than by forbidding them.
  ///
  /// A bare letter or digit is still refused. Not because of text fields, but
  /// because a dropdown jumps to an entry when one is typed at it, and that is
  /// a focus this app cannot recognise from the outside.
  bool get isSafeAlone {
    final k = key;
    return isFunctionKey ||
        k == LogicalKeyboardKey.escape ||
        k == LogicalKeyboardKey.pause ||
        activatesControls;
  }

  bool get isFunctionKey {
    final label = key.keyLabel;
    return label.length >= 2 &&
        label.length <= 3 &&
        label.startsWith('F') &&
        int.tryParse(label.substring(1)) != null;
  }

  /// Keys the framework uses to press whatever has focus.
  ///
  /// Bound bare, one of these means two things at once when a button holds
  /// focus — the button fires and the shortcut fires. Where the key is heard,
  /// that is settled by only acting when nothing else has taken the focus.
  bool get activatesControls {
    final k = key;
    return k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter;
  }

  /// Whether pressing this could also press something on screen.
  bool get mayActivateFocusedControl => !hasModifier && activatesControls;

  bool get hasModifier => control || shift || alt;

  /// Whether this is a combination the app is willing to store.
  bool get isUsable => hasModifier || isSafeAlone;

  /// How it reads on screen, in the order a person says it.
  String get label {
    final parts = <String>[
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      _keyName,
    ];
    return parts.join(' + ');
  }

  String get _keyName {
    final k = key;
    if (k == LogicalKeyboardKey.space) return 'רווח';
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      return 'Enter';
    }
    if (k == LogicalKeyboardKey.escape) return 'Esc';
    final label = k.keyLabel;
    return label.isEmpty ? '?' : label.toUpperCase();
  }

  /// Whether a key event is this combination.
  ///
  /// The modifiers are compared exactly: Ctrl+S is not Ctrl+Shift+S, and a
  /// writer who bound one should not have the other fire.
  bool matches(KeyEvent event, {required Set<LogicalKeyboardKey> pressed}) {
    if (event.logicalKey.keyId != keyId) return false;
    bool held(LogicalKeyboardKey a, LogicalKeyboardKey b) =>
        pressed.contains(a) || pressed.contains(b);
    return control ==
            held(LogicalKeyboardKey.controlLeft,
                LogicalKeyboardKey.controlRight) &&
        shift ==
            held(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight) &&
        alt == held(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight);
  }

  /// Reads a combination out of a key event.
  static ShortcutBinding fromEvent(KeyEvent event,
          {required Set<LogicalKeyboardKey> pressed}) =>
      ShortcutBinding(
        keyId: event.logicalKey.keyId,
        control: pressed.contains(LogicalKeyboardKey.controlLeft) ||
            pressed.contains(LogicalKeyboardKey.controlRight),
        shift: pressed.contains(LogicalKeyboardKey.shiftLeft) ||
            pressed.contains(LogicalKeyboardKey.shiftRight),
        alt: pressed.contains(LogicalKeyboardKey.altLeft) ||
            pressed.contains(LogicalKeyboardKey.altRight),
      );

  /// Modifier keys pressed on their own are not a shortcut, they are half of
  /// one — the writer is still choosing.
  static bool isModifierKey(LogicalKeyboardKey k) =>
      _modifierIds.contains(k.keyId);

  /// Compared by id: LogicalKeyboardKey overrides equality, so a const set of
  /// them is not one the language will build.
  static final Set<int> _modifierIds = {
    LogicalKeyboardKey.controlLeft.keyId,
    LogicalKeyboardKey.controlRight.keyId,
    LogicalKeyboardKey.shiftLeft.keyId,
    LogicalKeyboardKey.shiftRight.keyId,
    LogicalKeyboardKey.altLeft.keyId,
    LogicalKeyboardKey.altRight.keyId,
    LogicalKeyboardKey.metaLeft.keyId,
    LogicalKeyboardKey.metaRight.keyId,
  };

  String encode() => '$keyId:${control ? 1 : 0}${shift ? 1 : 0}${alt ? 1 : 0}';

  /// Reads a stored combination. Null for anything unusable, which is how a
  /// setting written by a later version fails safely rather than loudly.
  static ShortcutBinding? decode(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2 || parts[1].length != 3) return null;
    final id = int.tryParse(parts[0]);
    if (id == null) return null;
    return ShortcutBinding(
      keyId: id,
      control: parts[1][0] == '1',
      shift: parts[1][1] == '1',
      alt: parts[1][2] == '1',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ShortcutBinding &&
      other.keyId == keyId &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(keyId, control, shift, alt);

  @override
  String toString() => label;
}

/// What each action is bound to.
class ShortcutMap {
  final Map<ShortcutAction, ShortcutBinding> bindings;

  const ShortcutMap(this.bindings);

  /// Function keys, because nothing types them.
  ///
  /// A bare letter would stop the timer while the writer typed a page number,
  /// and a chord is one more thing to remember for something done every few
  /// minutes. F2, F3 and F4 sit together under one hand.
  static ShortcutMap get defaults => ShortcutMap({
        ShortcutAction.startStop:
            ShortcutBinding(keyId: LogicalKeyboardKey.f2.keyId),
        ShortcutAction.takeBreak:
            ShortcutBinding(keyId: LogicalKeyboardKey.f3.keyId),
        ShortcutAction.markLine:
            ShortcutBinding(keyId: LogicalKeyboardKey.f4.keyId),
      });

  ShortcutBinding? operator [](ShortcutAction action) => bindings[action];

  /// The action this event triggers, or null.
  ShortcutAction? actionFor(KeyEvent event,
      {required Set<LogicalKeyboardKey> pressed}) {
    for (final entry in bindings.entries) {
      if (entry.value.matches(event, pressed: pressed)) return entry.key;
    }
    return null;
  }

  /// The action already using [binding], ignoring [except].
  ///
  /// One combination cannot mean two things, and telling the writer which one
  /// it already means beats refusing without saying why.
  ShortcutAction? conflictWith(ShortcutBinding binding,
      {ShortcutAction? except}) {
    for (final entry in bindings.entries) {
      if (entry.key == except) continue;
      if (entry.value == binding) return entry.key;
    }
    return null;
  }

  ShortcutMap withBinding(ShortcutAction action, ShortcutBinding binding) =>
      ShortcutMap({...bindings, action: binding});

  Map<String, String> encode() =>
      {for (final e in bindings.entries) e.key.name: e.value.encode()};

  /// Reads stored bindings, falling back per action to the default.
  ///
  /// Per action rather than all-or-nothing: one unreadable entry should cost
  /// the writer that one shortcut, not the three he set.
  static ShortcutMap decode(Map<String, dynamic>? stored) {
    if (stored == null) return defaults;
    final out = <ShortcutAction, ShortcutBinding>{};
    for (final action in ShortcutAction.values) {
      final raw = stored[action.name];
      out[action] = ShortcutBinding.decode(raw is String ? raw : null) ??
          defaults[action]!;
    }
    return ShortcutMap(out);
  }
}
