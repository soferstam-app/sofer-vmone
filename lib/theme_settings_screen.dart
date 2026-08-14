import 'package:flutter/material.dart';

import 'logic/hebrew_clock.dart';
import 'main.dart' show themeController;
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';

/// Picking the app's look, and whether it changes itself after dark.
///
/// The two are separate settings on purpose. Choosing a look is a matter of
/// taste; switching to night dress is a matter of the hour, and one should not
/// silently overwrite the other — the screen says which is in force.
class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final t = SoferTokens.of(context);
        final choice = themeController.choice;

        return Scaffold(
          appBar: AppBar(title: const Text("עיצוב"), centerTitle: true),
          body: SoferPage(
            maxWidth: 720,
            child: ListView(
              children: [
                const SoferSectionTitle("ערכה"),
                for (final option in AppTheme.values)
                  _ThemeOption(
                    theme: option,
                    selected: option == choice,
                    onTap: () => themeController.setChoice(option),
                  ),
                const SizedBox(height: 8),
                const SoferRule(),
                const SoferSectionTitle("אחרי החשכה"),
                SwitchListTile(
                  value: themeController.autoNight,
                  onChanged: themeController.setAutoNight,
                  secondary: Icon(Icons.nightlight_round, color: t.accent),
                  title: const Text("מעבר אוטומטי לערכת לילה"),
                  subtitle: Text(_nightSubtitle()),
                ),
                if (themeController.nightByClock)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text(
                      "כרגע ערכת לילה פעילה בגלל השעה. הבחירה שלך "
                      "(${choice.label}) תחזור עם עלות השחר.",
                      style: TextStyle(fontSize: 12, color: t.accent),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  /// States the actual times rather than the idea of them, so the setting can
  /// be judged before it is switched on.
  String _nightSubtitle() {
    final now = DateTime.now();
    final nightfall = HebrewClock.nightfall(now);
    final dawn = HebrewClock.dawn(now);
    if (nightfall == null || dawn == null) {
      return "מצאת הכוכבים עד עלות השחר";
    }
    String hm(DateTime d) =>
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
    return "היום: מ-${hm(nightfall)} עד ${hm(dawn)} · לפי ממוצע ארץ ישראל";
  }
}

/// One look, shown as itself.
///
/// The swatch is drawn from the theme it represents rather than described in
/// words, because a palette is the one thing that cannot be explained in a
/// subtitle.
class _ThemeOption extends StatelessWidget {
  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final preview =
        AppThemeBuilder.build(theme).extension<SoferTokens>()!;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        child: Row(
          children: [
            _Swatch(preview),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(theme.label,
                      style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 17,
                        color: t.ink,
                      )),
                  const SizedBox(height: 2),
                  Text(theme.description,
                      style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 12,
                        color: t.inkMuted,
                      )),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? t.accent : t.inkFaint,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// A miniature of the look: its paper, its rules, its one accent.
class _Swatch extends StatelessWidget {
  final SoferTokens tokens;

  const _Swatch(this.tokens);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 46,
      decoration: BoxDecoration(
        color: tokens.paper,
        border: Border.all(color: tokens.rule),
        borderRadius: BorderRadius.circular(tokens.panelRadius),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text("42",
              style: TextStyle(
                fontFamily: tokens.numeralFamily,
                fontSize: 17,
                height: 1,
                fontWeight: tokens.isCards ? FontWeight.bold : FontWeight.w400,
                color: tokens.ink,
              )),
          Container(height: 1, color: tokens.rule),
          Row(children: [
            Container(width: 14, height: 3, color: tokens.accent),
            Expanded(child: Container(height: 3, color: tokens.rule)),
          ]),
        ],
      ),
    );
  }
}
