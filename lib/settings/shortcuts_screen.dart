import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/keyboard_shortcuts.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/sofer_widgets.dart';

/// Choosing which key does what.
///
/// The three actions a sofer performs while writing, and nothing else. A
/// shortcut is worth learning only for something done often enough to resent
/// reaching for, and a screen offering thirty of them is a screen nobody
/// finishes reading.
class ShortcutsScreen extends StatefulWidget {
  const ShortcutsScreen({super.key});

  @override
  State<ShortcutsScreen> createState() => _ShortcutsScreenState();
}

class _ShortcutsScreenState extends State<ShortcutsScreen> {
  final StorageService _storage = StorageService();
  ShortcutMap _map = ShortcutMap.defaults;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _storage.getShortcuts().then((m) {
      if (!mounted) return;
      setState(() {
        _map = m;
        _loaded = true;
      });
    });
  }

  Future<void> _rebind(ShortcutAction action) async {
    final picked = await _captureKey(action);
    if (picked == null || !mounted) return;

    if (!picked.isUsable) {
      showAppError(
        context,
        "אות או ספרה בודדת נבלעת ברשימות נפתחות. יש להוסיף Ctrl, Alt או "
        "Shift — או לבחור מקש פונקציה, רווח או Enter.",
      );
      return;
    }

    final clash = _map.conflictWith(picked, except: action);
    if (clash != null) {
      // Naming the action it already means beats refusing without saying why.
      showAppError(context, "${picked.label} כבר משמש ל\"${clash.label}\"");
      return;
    }

    final next = _map.withBinding(action, picked);
    await _storage.setShortcuts(next);
    if (!mounted) return;
    setState(() => _map = next);
    showAppSuccess(context, "${action.label}: ${picked.label}");
  }

  /// Waits for the writer to press the combination he wants.
  ///
  /// Asking him to press it is the only way that does not require him to know
  /// what the app calls a key.
  Future<ShortcutBinding?> _captureKey(ShortcutAction action) {
    final node = FocusNode();
    return showDialog<ShortcutBinding>(
      context: context,
      builder: (ctx) {
        final t = SoferTokens.of(ctx);
        return AlertDialog(
          title: Text(action.label),
          content: KeyboardListener(
            focusNode: node,
            autofocus: true,
            onKeyEvent: (event) {
              if (event is! KeyDownEvent) return;
              // A modifier on its own is half a combination — he is still
              // choosing.
              if (ShortcutBinding.isModifierKey(event.logicalKey)) return;
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(
                ctx,
                ShortcutBinding.fromEvent(event,
                    pressed: HardwareKeyboard.instance.logicalKeysPressed),
              );
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard, size: 40, color: t.inkMuted),
                const SizedBox(height: 14),
                const Text("הקש את הצירוף הרצוי",
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  "Esc לביטול",
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(node.dispose);
  }

  Future<void> _restoreDefaults() async {
    await _storage.setShortcuts(ShortcutMap.defaults);
    if (!mounted) return;
    setState(() => _map = ShortcutMap.defaults);
    showAppSuccess(context, "הוחזרו ברירות המחדל");
  }

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("קיצורי מקלדת")),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SoferPage(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  SoferPanel(
                    child: Text(
                      "הקיצורים פועלים כשחלון התוכנה בחזית — גם בחלון הצף. "
                      "בזמן הקלדה בשדה טקסט הם אינם מופעלים.\n"
                      "רווח ו-Enter פועלים כשאין כפתור שנבחר, כדי שלא יפעילו "
                      "אותו וגם את הקיצור.",
                      style: TextStyle(
                          fontSize: 14, height: 1.6, color: t.inkMuted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final action in ShortcutAction.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SoferPanel(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(action.label,
                                      style: TextStyle(
                                          fontFamily: t.numeralFamily,
                                          fontSize: 17,
                                          color: t.ink)),
                                  const SizedBox(height: 3),
                                  Text(action.describe,
                                      style: TextStyle(
                                          fontSize: 13, color: t.inkMuted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: () => _rebind(action),
                              child: Text(_map[action]?.label ?? '—'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  SoferSecondaryButton(
                    "החזרת ברירות המחדל",
                    icon: Icons.settings_backup_restore,
                    expand: true,
                    onPressed: _restoreDefaults,
                  ),
                ],
              ),
            ),
    );
  }
}
