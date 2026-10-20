import 'package:flutter/material.dart';

import '../accessibility/accessibility_controller.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show accessibilityController;
import '../theme/app_theme.dart';
import '../widgets/sofer_widgets.dart';

class AccessibilityScreen extends StatelessWidget {
  const AccessibilityScreen({super.key});

  String _name(BuildContext context, AppTextSize size) => switch (size) {
        AppTextSize.regular => context.l10n.pick(he: 'רגיל', en: 'Regular'),
        AppTextSize.large => context.l10n.pick(he: 'גדול', en: 'Large'),
        AppTextSize.extraLarge =>
          context.l10n.pick(he: 'גדול מאוד', en: 'Extra large'),
        AppTextSize.maximum => context.l10n.pick(he: 'מרבי', en: 'Maximum'),
      };

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.pick(he: 'נגישות', en: 'Accessibility')),
      ),
      body: SoferPage(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
          children: [
            Text(
              context.l10n.pick(
                he: 'גודל הכיתוב חל על כל מסכי התוכנה. כאשר הכיתוב גדל, שורות צפופות עוברות לגובה והמסך נגלל במקום לחתוך מידע.',
                en: 'Text size applies throughout the app. At larger sizes, dense rows grow vertically and screens scroll rather than clipping information.',
              ),
              style: TextStyle(height: 1.55, color: t.inkMuted),
            ),
            const SizedBox(height: 18),
            SoferPanel(
              child: ListenableBuilder(
                listenable: accessibilityController,
                builder: (context, _) => RadioGroup<AppTextSize>(
                  groupValue: accessibilityController.textSize,
                  onChanged: (value) {
                    if (value != null) {
                      accessibilityController.setTextSize(value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final size in AppTextSize.values) ...[
                        RadioListTile<AppTextSize>(
                          value: size,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          title: Text(_name(context, size)),
                          subtitle: Text('${size.percent}%'),
                        ),
                        if (size != AppTextSize.values.last) const SoferRule(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SoferSectionTitle(
              context.l10n.pick(he: 'תצוגה מקדימה', en: 'Preview'),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 10),
            SoferPanel(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.pick(
                          he: 'עמוד מ״ג · שורה כ״א', en: 'Page מ״ג · line 21'),
                      style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 22,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.pick(
                        he: 'הטיימר, המיקום וכפתורי הפעולה נשארים ברורים ונעימים גם בכתב מוגדל.',
                        en: 'The timer, position, and action buttons remain clear and balanced at larger text sizes.',
                      ),
                      style: TextStyle(height: 1.5, color: t.inkMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
