import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/settings/work_day_exception_dialog.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';
import 'package:sofer_vmone/work_calendar_settings_screen.dart';

class _FailingStore extends MemoryStore {
  _FailingStore(super.initial);
  bool fail = false;
  @override
  Future<void> setString(String key, String value) async {
    if (fail && key == 'work_calendar_rules') throw StateError('Disk full');
    await super.setString(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    StorageService.demoStore = null;
    StorageService.onChanged = null;
  });

  Future<void> host(WidgetTester tester,
      {AppTheme theme = AppTheme.modern,
      double width = 1100,
      double scale = 1,
      bool english = false}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(theme)
          .copyWith(splashFactory: NoSplash.splashFactory),
      locale: english ? const Locale('en', 'US') : const Locale('he', 'IL'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(
              textDirection: english ? TextDirection.ltr : TextDirection.rtl,
              child: child!)),
      home: const WorkCalendarSettingsScreen(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  Future<void> hebrewValue(WidgetTester tester, String label, int value) async {
    final field = find.byWidgetPredicate((widget) =>
        widget is DropdownButtonFormField<int> &&
        widget.decoration.labelText == label);
    tester.widget<DropdownButtonFormField<int>>(field).onChanged!(value);
    await tester.pumpAndSettle();
  }

  Future<void> note(WidgetTester tester, String value) async {
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  Map<String, Object> initial() => {
        'work_calendar_rules':
            jsonEncode(WorkCalendarRules.standard.copyWith(exceptions: {
          '2026-02-02':
              const WorkDayException(weight: DayWeight.none, note: 'חתונה'),
        }).toJson()),
      };

  for (final theme in AppTheme.values) {
    testWidgets('add Hebrew date, edit and remove in ${theme.name}',
        (tester) async {
      StorageService.demoStore = MemoryStore({});
      await host(tester, theme: theme);
      await tap(tester, find.text('הוסף תאריך חריג'));
      await hebrewValue(tester, 'שנה', 5786);
      await hebrewValue(tester, 'חודש', 11);
      await hebrewValue(tester, 'יום', 15);
      await note(tester, 'חתונה');
      await tap(tester, find.text('שמור'));
      final stored = await StorageService().getWorkCalendarRules();
      expect(stored.exceptions.keys, ['2026-02-02']);
      expect(stored.exceptions.values.single.note, 'חתונה');
      await tap(
          tester, find.byKey(const ValueKey('personal-exception-2026-02-02')));
      tester
          .widget<DropdownButtonFormField<DayWeight>>(
              find.byType(DropdownButtonFormField<DayWeight>))
          .onChanged!(DayWeight.half);
      await tester.pumpAndSettle();
      await note(tester, 'שבע ברכות');
      await tap(tester, find.text('שמור'));
      final updated = await StorageService().getWorkCalendarRules();
      expect(updated.exceptions.values.single.weight, DayWeight.half);
      expect(find.text('חצי יום · שבע ברכות'), findsOneWidget);
      await tap(tester, find.byTooltip('מחק חריגה'));
      expect(
          (await StorageService().getWorkCalendarRules()).exceptions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('Gregorian date selection moves an existing exception',
      (tester) async {
    StorageService.demoStore = MemoryStore(initial());
    await host(tester);
    await tap(
        tester, find.byKey(const ValueKey('personal-exception-2026-02-02')));
    await tap(tester, find.text('לועזי'));
    await tap(tester, find.byType(OutlinedButton).last);
    final picker =
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    picker.onDateChanged(DateTime(2026, 2, 3));
    await tester.pumpAndSettle();
    final ok =
        MaterialLocalizations.of(tester.element(find.byType(DatePickerDialog)))
            .okButtonLabel;
    await tap(tester, find.text(ok));
    await tap(tester, find.text('שמור'));
    final saved = await StorageService().getWorkCalendarRules();
    expect(saved.exceptions.keys, ['2026-02-03']);
    expect(saved.exceptions.values.single.note, 'חתונה');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a duplicate date is rejected without overwriting its note',
      (tester) async {
    StorageService.demoStore = MemoryStore(initial());
    await host(tester);
    await tap(tester, find.text('הוסף תאריך חריג'));
    await hebrewValue(tester, 'שנה', 5786);
    await hebrewValue(tester, 'חודש', 11);
    await hebrewValue(tester, 'יום', 15);
    await note(tester, 'אירוע אחר');
    await tap(tester, find.text('שמור'));
    expect(find.text('התאריך כבר מופיע ברשימה. יש לערוך את החריגה הקיימת.'),
        findsOneWidget);
    expect(
        (await StorageService().getWorkCalendarRules())
            .exceptions
            .values
            .single
            .note,
        'חתונה');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Hebrew date changes clamp short months and non-leap Adar',
      (tester) async {
    StorageService.demoStore = MemoryStore({});
    await host(tester);
    await tap(tester, find.text('הוסף תאריך חריג'));
    await hebrewValue(tester, 'שנה', 5784);
    await hebrewValue(tester, 'חודש', 12);
    await hebrewValue(tester, 'יום', 30);
    await hebrewValue(tester, 'חודש', 13);
    await hebrewValue(tester, 'שנה', 5785);
    await tap(tester, find.text('שמור'));
    final date = JewishDate.initDate(
        jewishYear: 5785, jewishMonth: 12, jewishDayOfMonth: 29);
    expect((await StorageService().getWorkCalendarRules()).exceptions.keys,
        [WorkCalendarRules.dateKey(date.getGregorianCalendar())]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'failed saving leaves the persisted exception and displayed list unchanged',
      (tester) async {
    final store = _FailingStore(initial());
    StorageService.demoStore = store;
    await host(tester);
    await tap(
        tester, find.byKey(const ValueKey('personal-exception-2026-02-02')));
    await note(tester, 'שבע ברכות');
    store.fail = true;
    await tap(tester, find.text('שמור'));
    expect(find.text('יום חופש · חתונה'), findsOneWidget);
    expect(find.textContaining('השינוי לא נשמר'), findsOneWidget);
    expect(
        (await StorageService().getWorkCalendarRules())
            .exceptions
            .values
            .single
            .note,
        'חתונה');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('date editor fits a narrow phone with large text',
      (tester) async {
    StorageService.demoStore = MemoryStore(initial());
    await host(tester, width: 360, scale: 2);
    await tester.scrollUntilVisible(find.text('הוסף תאריך חריג'), 200,
        scrollable: find.byType(Scrollable).first);
    await tap(tester, find.text('הוסף תאריך חריג'));
    expect(find.byType(WorkDayExceptionDialog), findsOneWidget);
    await note(tester, 'חתונה');
    await tap(tester, find.text('שמור'));
    expect(
        (await StorageService().getWorkCalendarRules()).exceptions.length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('English uses translated controls and preserves personal note',
      (tester) async {
    StorageService.demoStore = MemoryStore(initial());
    await host(tester, english: true);
    expect(find.text('Personal date exceptions'), findsOneWidget);
    await tap(
        tester, find.byKey(const ValueKey('personal-exception-2026-02-02')));
    expect(find.text('Edit personal exception'), findsOneWidget);
    expect(find.text('Writing availability'), findsOneWidget);
    await tap(tester, find.text('Save'));
    expect(
        (await StorageService().getWorkCalendarRules())
            .exceptions
            .values
            .single
            .note,
        'חתונה');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
