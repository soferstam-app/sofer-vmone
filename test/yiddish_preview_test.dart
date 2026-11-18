import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/l10n/yiddish_preview.dart';
import 'package:sofer_vmone/l10n/yiddish_material.dart';
import 'package:sofer_vmone/l10n/yiddish_workspace_copy.dart';

void main() {
  test('Yiddish is selectable only in the preview build', () {
    expect(
      AppLanguage.fromCode('yi'),
      yiddishPreview ? AppLanguage.yiddish : null,
    );
    expect(AppLanguage.fromCode(null), isNull);
  });

  test('workspace translations keep variable data and the other locales', () {
    const yiddish = AppLocalizations(Locale('yi'));
    const english = AppLocalizations(Locale('en'));
    const hebrew = AppLocalizations(Locale('he'));
    expect(yiddish.pick(he: 'מצב חכם', en: 'Smart Mode'), 'קלוגער מאָדוס');
    for (final (l10n, expected) in [
      (yiddish, 'לעצטער אָרט: מ״ג, שורה 21'),
      (english, 'Last position: מ״ג, line 21'),
      (hebrew, 'מיקום אחרון: מ״ג, שורה 21'),
    ]) {
      expect(
        l10n.pick(
            he: 'מיקום אחרון: מ״ג, שורה 21', en: 'Last position: מ״ג, line 21'),
        expected,
      );
    }
    expect(
        yiddish.pick(he: 'עברית', en: 'Hebrew', yi: 'לשון־קודש'), 'לשון־קודש');
    expect(yiddish.businessMessage('מזוזה 7 כבר נכתבה עד שורה 12'),
        'מזוזה 7 איז שוין געשריבן ביז שורה 12');
  });

  test('each workspace template uses all of its variables exactly once', () {
    final slot = RegExp(r'«(\d+)»');
    for (final (english, _, copy) in yiddishTemplates) {
      final found = slot.allMatches(copy).map((m) => int.parse(m[1]!)).toList()
        ..sort();
      expect(found, List.generate(english.length - 1, (i) => i + 1),
          reason: english.join('…'));
    }
  });

  testWidgets('switching to Yiddish updates app copy and stays right to left',
      (tester) async {
    Widget app(AppLanguage language) => MaterialApp(
          locale: language.frameworkLocale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegateFor(language),
            if (language == AppLanguage.yiddish)
              const YiddishMaterialDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Text(context.l10n.settings),
          ),
        );

    await tester.pumpWidget(app(AppLanguage.hebrew));
    await tester.pumpAndSettle();
    expect(find.text('הגדרות'), findsOneWidget);

    await tester.pumpWidget(app(AppLanguage.yiddish));
    await tester.pumpAndSettle();
    final translated = find.text('אײַנשטעלונגען');
    expect(translated, findsOneWidget);
    expect(Directionality.of(tester.element(translated)), TextDirection.rtl);
    expect(
        MaterialLocalizations.of(tester.element(translated)).datePickerHelpText,
        'קלײַבט אַ דאַטע');

    await tester.pumpWidget(app(AppLanguage.english));
    await tester.pumpAndSettle();
    final english = find.text('Settings');
    expect(english, findsOneWidget);
    expect(Directionality.of(tester.element(english)), TextDirection.ltr);
  });
}
