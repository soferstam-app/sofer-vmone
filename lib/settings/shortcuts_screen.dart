import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/keyboard_shortcuts.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/sofer_widgets.dart';
import '../l10n/app_localizations.dart';

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
        context.l10n.pick(
          he: "אות או ספרה בודדת נבלעת ברשימות נפתחות. יש להוסיף Ctrl, Alt או Shift — או לבחור מקש פונקציה, רווח או Enter.",
          en: "A bare letter or digit is consumed by dropdown lists. Add Ctrl, Alt, or Shift, or choose a function key, Space, or Enter.",
        ),
      );
      return;
    }

    final clash = _map.conflictWith(picked, except: action);
    if (clash != null) {
      // Naming the action it already means beats refusing without saying why.
      showAppError(
        context,
        context.l10n.pick(
          he: "${picked.label} כבר משמש ל\"${clash.label}\"",
          en: "${_bindingLabel(picked)} is already assigned to “${_actionLabel(clash)}”",
        ),
      );
      return;
    }

    final next = _map.withBinding(action, picked);
    await _storage.setShortcuts(next);
    if (!mounted) return;
    setState(() => _map = next);
    showAppSuccess(
        context, "${_actionLabel(action)}: ${_bindingLabel(picked)}");
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
          title: Text(_actionLabel(action)),
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
                Text(
                    context.l10n.pick(
                        he: "הקש את הצירוף הרצוי",
                        en: "Press the desired key combination"),
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  context.l10n.pick(he: "Esc לביטול", en: "Esc to cancel"),
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
    showAppSuccess(context,
        context.l10n.pick(he: "הוחזרו ברירות המחדל", en: "Defaults restored"));
  }

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    return Scaffold(
      appBar: AppBar(
          title: Text(
              context.l10n.pick(he: "קיצורי מקלדת", en: "Keyboard shortcuts"))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SoferPage(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  SoferPanel(
                    child: Text(
                      context.l10n.pick(
                        he: "הקיצורים פועלים כשחלון התוכנה בחזית — גם בחלון הצף. בזמן הקלדה בשדה טקסט הם אינם מופעלים.\nרווח ו-Enter פועלים כשאין כפתור שנבחר, כדי שלא יפעילו אותו וגם את הקיצור.",
                        en: "Shortcuts work while the app is in the foreground, including the floating window. They are disabled while typing in a text field.\nSpace and Enter work only when no button is focused, so they do not activate both the button and the shortcut.",
                      ),
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
                                  Text(_actionLabel(action),
                                      style: TextStyle(
                                          fontFamily: t.numeralFamily,
                                          fontSize: 17,
                                          color: t.ink)),
                                  const SizedBox(height: 3),
                                  Text(_actionDescription(action),
                                      style: TextStyle(
                                          fontSize: 13, color: t.inkMuted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: () => _rebind(action),
                              child: Text(_map[action] == null
                                  ? '—'
                                  : _bindingLabel(_map[action]!)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  SoferSecondaryButton(
                    context.l10n
                        .pick(he: "החזרת ברירות המחדל", en: "Restore defaults"),
                    icon: Icons.settings_backup_restore,
                    expand: true,
                    onPressed: _restoreDefaults,
                  ),
                ],
              ),
            ),
    );
  }

  String _actionLabel(ShortcutAction action) => context.l10n.isEnglish
      ? switch (action) {
          ShortcutAction.startStop => 'Start and stop',
          ShortcutAction.takeBreak => 'Break and resume',
          ShortcutAction.markLine => 'Finished a line',
        }
      : action.label;

  String _actionDescription(ShortcutAction action) => context.l10n.isEnglish
      ? switch (action) {
          ShortcutAction.startStop =>
            'Starts a session; during a session, finishes and saves it',
          ShortcutAction.takeBreak =>
            'Starts a break; during a break, resumes writing',
          ShortcutAction.markLine =>
            'Marks a completed line and measures its time',
        }
      : action.describe;

  String _bindingLabel(ShortcutBinding binding) =>
      context.l10n.isEnglish && binding.key == LogicalKeyboardKey.space
          ? binding.label.replaceAll('רווח', 'Space')
          : binding.label;
}
