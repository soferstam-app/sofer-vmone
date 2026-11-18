import '../theme/app_theme.dart';
import 'app_localizations.dart';

extension ThemeLabels on AppLocalizations {
  String themeLabel(AppTheme theme) => switch (theme) {
        AppTheme.modern => pick(he: theme.label, en: 'Modern', yi: 'מאָדערן'),
        AppTheme.klaf => pick(he: theme.label, en: 'Parchment', yi: 'קלף'),
        AppTheme.layla => pick(he: theme.label, en: 'Night', yi: 'נאַכט'),
      };

  String themeDescription(AppTheme theme) => switch (theme) {
        AppTheme.modern => pick(
            he: theme.description,
            en: 'Cards, color, and system dark mode',
            yi: 'קאַרטלען, פֿאַרבן און דער פֿינצטערער אויסזען פֿונעם מיטל'),
        AppTheme.klaf => pick(
            he: theme.description,
            en: 'Warm paper, ruling lines, and no cards',
            yi: 'אַ וואַרעמער פּאַפּיר־קאָליר מיט שורות, אָן קאַרטלען'),
        AppTheme.layla => pick(
            he: theme.description,
            en: 'Charcoal and brass for writing at night',
            yi: 'טונקל־גרוי מיט מעש־קאָליר פֿאַרן שרײַבן בײַ נאַכט'),
      };
}
