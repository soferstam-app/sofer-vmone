import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The two languages the application ships with.
///
/// Hebrew remains the safe fallback for data written before language choice
/// existed. English is deliberately a real locale, not a second hard-coded
/// layout: Flutter supplies LTR/RTL, date-picker labels and accessibility
/// conventions from the selected locale.
enum AppLanguage {
  hebrew(Locale('he', 'IL')),
  english(Locale('en', 'US'));

  final Locale locale;
  const AppLanguage(this.locale);

  String get code => locale.languageCode;

  static AppLanguage? fromCode(String? code) => switch (code) {
        'he' => AppLanguage.hebrew,
        'en' => AppLanguage.english,
        _ => null,
      };
}

/// Small hand-owned localization surface.
///
/// The application predates localization and has user-facing strings in pure
/// business logic as well as widgets. Keeping the source phrase beside the
/// approved English phrase makes that migration reviewable: no machine
/// translation runs at runtime, and a missing phrase remains Hebrew rather
/// than guessing at professional STaM terminology.
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  static const supportedLocales = [
    Locale('he', 'IL'),
    Locale('en', 'US'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('he', 'IL'));

  bool get isEnglish => locale.languageCode == 'en';
  TextDirection get textDirection =>
      isEnglish ? TextDirection.ltr : TextDirection.rtl;

  String pick({required String he, required String en}) => isEnglish ? en : he;

  String get appName => pick(he: 'סופר ומונה', en: 'Sofer v’Mone');
  String get language => pick(he: 'שפה', en: 'Language');
  String get hebrew => 'עברית';
  String get english => 'English';
  String get cancel => pick(he: 'ביטול', en: 'Cancel');
  String get confirm => pick(he: 'אישור', en: 'Confirm');
  String get settings => pick(he: 'הגדרות', en: 'Settings');
  String get interfaceLanguage =>
      pick(he: 'שפת הממשק', en: 'Interface language');
  String get languageCanChange => pick(
        he: 'אפשר לשנות בכל עת בהגדרות',
        en: 'You can change this at any time in Settings',
      );

  /// Expense names are persisted as their original Hebrew identifiers.  Only
  /// their presentation is localized, so switching language never rewrites a
  /// quote, backup, or historical expense.
  String expenseCategory(String storedName) {
    if (!isEnglish) return storedName;
    return switch (storedName) {
      'קלף מזוזות' => 'Mezuzah Parchment',
      'קלף תפילין' => 'Tefillin Parchment',
      'קלף והגהות מגילות' => 'Megillah Parchment and Proofreading',
      'הגהות מזוזות' => 'Mezuzah Proofreading',
      'הגהות תפילין' => 'Tefillin Proofreading',
      'מחיקות מזוזות' => 'Mezuzah Erasures',
      'תיקון סופרים' => 'Tikkun Sofrim',
      'משלוחים ונסיעות' => 'Shipping and Travel',
      'דיו, מי קלף, ציוד' => 'Ink, Mei Klaf, and Equipment',
      'קולמוס מגילות' => 'Quills for Megillot',
      'קולמוס מזוזות' => 'Quills for Mezuzot',
      'קולמוס תש"י' => 'Quills for Tefillin Shel Yad',
      'קולמוס תש"ר' => 'Quills for Tefillin Shel Rosh',
      'משקפיים' => 'Glasses',
      'שולחן, כסא, פנס, מכשיר אדים' => 'Desk, Chair, Lamp, and Humidifier',
      'חדר סופרים' => 'Sofrim Workspace',
      'שונות' => 'Other',
      'קורס סת"ם' => 'STaM Course',
      'תעודה' => 'Certificate',
      _ => storedName,
    };
  }

  String proofreadingStage(String hebrewLabel) {
    if (!isEnglish) return hebrewLabel;
    return switch (hebrewLabel) {
      'ממתין להגהה' => 'Awaiting Proofreading',
      'אצל המגיה' => 'With the Proofreader',
      'חזר לתיקון' => 'Awaiting Correction',
      'הושלם' => 'Completed',
      _ => hebrewLabel,
    };
  }

  String nonWorkReason(String hebrewLabel) {
    if (!isEnglish) return hebrewLabel;
    return switch (hebrewLabel) {
      'שבת' => 'Shabbat',
      'יום טוב' => 'Yom Tov',
      'חול המועד' => 'Chol HaMoed',
      'ערב חג' => 'Erev Yom Tov',
      'פורים' => 'Purim',
      'תשעה באב' => 'Tisha B’Av',
      'ערב תשעה באב' => 'Erev Tisha B’Av',
      'ערב שבת' => 'Erev Shabbat',
      'מוצאי שבת' => 'Motzaei Shabbat',
      'חנוכה' => 'Chanukah',
      'י״ז בתמוז' => '17 Tammuz',
      'צום גדליה' => 'Tzom Gedaliah',
      'י׳ בטבת' => '10 Tevet',
      'תענית אסתר' => 'Ta’anit Esther',
      'ל״ג בעומר' => 'Lag BaOmer',
      'איסרו חג' => 'Isru Chag',
      'לפני פסח' => 'Before Pesach',
      'בין כיפור לסוכות' => 'Between Yom Kippur and Sukkot',
      'יום חופש אישי' => 'Personal time off',
      _ => hebrewLabel,
    };
  }

  /// Translates validation text emitted by the legacy pure business layer.
  /// The source remains Hebrew for backward-compatible tests and stored
  /// descriptions; presentation converts only known messages.
  String businessMessage(String message) {
    if (!isEnglish) return message;
    const exact = {
      'יש להזין לפחות עמוד התחלה תקין': 'Enter a valid starting page',
      'יש להזין עמוד סיום תקין או להשאיר אותו ריק':
          'Enter a valid ending page or leave it blank',
      'עמוד הסיום לא יכול להיות לפני עמוד ההתחלה':
          'The ending page cannot be before the starting page',
      'יש להזין שורות תקינות (משורה, עד שורה)':
          'Enter a valid line range (from line, to line)',
      'שורה התחלה חייבת להיות קטנה משורה סיום':
          'The starting line must be before the ending line',
      'מספר שורה אינו יכול להיות שלילי': 'The line number cannot be negative',
      'יש להזין מספר זוג כדי לשמור על סדר הפרשיות בתוך הסט':
          'Enter a set number to preserve the order of Parashiyot in the set',
      'המזוזה שנבחרה כבר אינה חלקית. יש לרענן ולבחור שוב':
          'The selected Mezuzah is no longer partial. Refresh and select again',
      'יש להזין עד איזו שורה הגעת': 'Enter the line you reached',
      'יש להזין כמות': 'Enter a quantity',
    };
    final known = exact[message];
    if (known != null) return known;

    Match? m;
    if ((m = RegExp(r'^מספר העמוד חורג מהגדרת הספר \((\d+)\)$')
            .firstMatch(message)) !=
        null) {
      return 'The page number exceeds the Sefer limit (${m![1]})';
    }
    if ((m = RegExp(r'^עמוד הסיום חורג מהגדרת הספר \((\d+)\)$')
            .firstMatch(message)) !=
        null) {
      return 'The ending page exceeds the Sefer limit (${m![1]})';
    }
    if ((m = RegExp(r'^טווח של יותר מ־(\d+) עמודים בהזנה אחת — יש לפצל אותו$')
            .firstMatch(message)) !=
        null) {
      return 'A range of more than ${m![1]} pages must be split into separate entries';
    }
    if ((m = RegExp(r'^שורת ההתחלה חייבת להיות בין 1 ל־(\d+)$')
            .firstMatch(message)) !=
        null) {
      return 'The starting line must be between 1 and ${m![1]}';
    }
    if ((m = RegExp(r'^שורת הסיום חייבת להיות בין 1 ל־(\d+)$')
            .firstMatch(message)) !=
        null) {
      return 'The ending line must be between 1 and ${m![1]}';
    }
    if ((m = RegExp(r'^מספר השורות חורג מהגדרת העמוד \((\d+)\)$')
            .firstMatch(message)) !=
        null) {
      return 'The line number exceeds the page limit (${m![1]})';
    }
    if ((m = RegExp(r'^במזוזה יש רק (\d+) שורות$').firstMatch(message)) !=
        null) {
      return 'A Mezuzah has only ${m![1]} lines';
    }
    if ((m = RegExp(r'^בתפילין (.+) יש עד (\d+) שורות$').firstMatch(message)) !=
        null) {
      final side = m![1] == 'ראש' ? 'Shel Rosh' : 'Shel Yad';
      return 'Tefillin $side has up to ${m[2]} lines';
    }
    if ((m = RegExp(r'^פרשיית (.+) בזוג (\d+) כבר התחילה$')
            .firstMatch(message)) !=
        null) {
      return 'Parashah ${m![1]} in set ${m[2]} has already started';
    }
    if ((m = RegExp(
                r'^אי אפשר להתחיל את (.+) לפני שהפרשייה (.+) הסתיימה באותו סט$')
            .firstMatch(message)) !=
        null) {
      return 'Cannot start ${m![1]} before Parashah ${m[2]} is complete in the same set';
    }
    if ((m = RegExp(r'^מזוזה (\d+) כבר נכתבה עד שורה (\d+)$')
            .firstMatch(message)) !=
        null) {
      return 'Mezuzah ${m![1]} has already been written through line ${m[2]}';
    }
    if ((m = RegExp(r'^פרשיית (.+) כבר הסתיימה$').firstMatch(message)) !=
        null) {
      return 'Parashah ${m![1]} is already complete';
    }
    if ((m = RegExp(r'^פרשיית (.+) נפסלה; יש להסיר אותה לפני שמתחילים מחדש$')
            .firstMatch(message)) !=
        null) {
      return 'Parashah ${m![1]} is invalid; remove it before starting again';
    }
    if ((m = RegExp(
                r'^אי אפשר לכתוב את (.+) לפני שהפרשייה הקודמת הסתיימה באותו סט$')
            .firstMatch(message)) !=
        null) {
      return 'Cannot write ${m![1]} before the previous Parashah is complete in the same set';
    }
    return message;
  }
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
        (supported) => supported.languageCode == locale.languageCode,
      );

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
