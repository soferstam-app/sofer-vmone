import 'app_localizations.dart';

extension PriorWritingLabels on AppLocalizations {
  String get priorWriting => switch (locale.languageCode) {
        'en' => 'Previously written',
        'yi' => 'פֿריִער אָנגעשריבן',
        _ => 'כתיבה קודמת',
      };

  String get priorWritingHelp => switch (locale.languageCode) {
        'en' =>
          'Adds to project progress without counting toward a day, writing pace or earnings.',
        'yi' =>
          'עס גייט אַרײַן אין דער פֿאָרשריט פֿונעם פּראָיעקט, אָן צו ציילן פֿאַר אַ טאָג, שרײַב־גאַנג אָדער הכנסה.',
        _ =>
          'מוסיף להתקדמות הפרויקט בלי להיספר ביום מסוים, בקצב הכתיבה או ברווח.',
      };

  String get markAsPriorWriting => switch (locale.languageCode) {
        'en' => 'Mark as previously written',
        'yi' => 'באַצייכענען ווי פֿריִער אָנגעשריבן',
        _ => 'סמן ככתיבה קודמת',
      };

  String get writingChangeSaveFailed => switch (locale.languageCode) {
        'en' => 'Could not save the change. Try again.',
        'yi' => 'מען האָט נישט געקענט אָפּהיטן די ענדערונג. פּרוּווט ווידער.',
        _ => 'לא הצלחתי לשמור את השינוי. נסו שוב.',
      };
}
