import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

/// Copy for dialogs built by Flutter. The base format keeps the established
/// day-month-year order and right-to-left behavior.
class YiddishMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const YiddishMaterialDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'he';

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    await GlobalMaterialLocalizations.delegate.load(locale);
    return _YiddishMaterial();
  }

  @override
  bool shouldReload(YiddishMaterialDelegate old) => false;
}

class _YiddishMaterial extends MaterialLocalizationHe {
  _YiddishMaterial()
      : super(
          fullYearFormat: DateFormat.y('he'),
          compactDateFormat: DateFormat.yMd('he'),
          shortDateFormat: DateFormat.yMMMd('he'),
          mediumDateFormat: DateFormat.MMMEd('he'),
          longDateFormat: DateFormat.yMMMMEEEEd('he'),
          yearMonthFormat: DateFormat.yMMMM('he'),
          shortMonthDayFormat: DateFormat.MMMd('he'),
          decimalFormat: NumberFormat.decimalPattern('he'),
          twoDigitZeroPaddedFormat: NumberFormat('00', 'he'),
        );

  @override
  String get cancelButtonLabel => 'אָפּזאָגן';
  @override
  String get okButtonLabel => 'באַשטעטיקן';
  @override
  String get saveButtonLabel => 'היטן';
  @override
  String get closeButtonLabel => 'צומאַכן';
  @override
  String get closeButtonTooltip => closeButtonLabel;
  @override
  String get modalBarrierDismissLabel => closeButtonLabel;
  @override
  String get backButtonTooltip => 'צוריק';
  @override
  String get copyButtonLabel => 'קאָפּירן';
  @override
  String get cutButtonLabel => 'אויסשנײַדן';
  @override
  String get pasteButtonLabel => 'אַרײַנלייגן';
  @override
  String get selectAllButtonLabel => 'אַלץ אויסקלײַבן';
  @override
  String get datePickerHelpText => 'קלײַבט אַ דאַטע';
  @override
  String get dateInputLabel => 'גיט אַרײַן אַ דאַטע';
  @override
  String get dateOutOfRangeLabel => 'די דאַטע ליגט מחוץ דעם אויסוואַל.';
  @override
  String get dateRangePickerHelpText => 'קלײַבט די אָנהייב־ און סוף־דאַטעס';
  @override
  String get dateRangeStartLabel => 'אָנהייב־דאַטע';
  @override
  String get dateRangeEndLabel => 'סוף־דאַטע';
  @override
  String get inputDateModeButtonLabel => 'אַרײַנטיפּן די דאַטע';
  @override
  String get calendarModeButtonLabel => 'קלײַבן אַ דאַטע אינעם לוח';
  @override
  String get invalidDateFormatLabel =>
      'שרײַבט די דאַטע אינעם געוויזענעם פֿאָרמאַט.';
  @override
  String get invalidDateRangeLabel =>
      'קאָנטראָלירט די אָנהייב־ און סוף־דאַטעס.';
  @override
  String get previousMonthTooltip => 'פֿריִערדיקער חודש';
  @override
  String get nextMonthTooltip => 'קומענדיקער חודש';
  @override
  String get selectYearSemanticsLabel => 'קלײַבט אַ יאָר';
  @override
  String get timePickerDialHelpText => 'קלײַבט אַ צײַט';
  @override
  String get timePickerInputHelpText => 'גיט אַרײַן אַ צײַט';
  @override
  String get timePickerHourLabel => 'שעה';
  @override
  String get timePickerMinuteLabel => 'מינוט';
  @override
  String get dialModeButtonLabel => 'קלײַבן די צײַט אויפֿן זייגער';
  @override
  String get inputTimeModeButtonLabel => 'אַרײַנטיפּן די צײַט';
  @override
  String get invalidTimeLabel => 'גיט אַרײַן אַ גילטיקע צײַט.';
}
