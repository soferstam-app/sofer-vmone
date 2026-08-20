import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/entry/entry_sheet.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save and continue preserves an overnight range length', () {
    final next = continuationEndTime(
      const TimeOfDay(hour: 23, minute: 0),
      const TimeOfDay(hour: 1, minute: 0),
    );
    expect(next, const TimeOfDay(hour: 3, minute: 0));
  });

  testWidgets('clock entry distinguishes start from end and uses 24-hour time',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final project = Project(
      id: 'sefer',
      name: 'ספר תורה',
      type: ProjectType.sefer,
      price: 100,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      linesPerPage: 42,
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.klaf),
      locale: const Locale('he', 'IL'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('he', 'IL')],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () => showEntrySheet(
              context: context,
              isManual: true,
              projects: [project],
              history: const [],
              useGregorianDates: true,
              dayStart: DayStart.midnight,
              onProjectCreated: (_) {},
              onSave: (_) async {},
              initialProject: project,
            ),
            child: const Text('פתיחה'),
          );
        }),
      ),
    ));

    await tester.tap(find.text('פתיחה'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('משעה עד שעה'));
    await tester.pumpAndSettle();

    expect(find.text('שעת התחלה'), findsOneWidget);
    expect(find.text('שעת סיום'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);

    await tester.tap(find.text('שעת התחלה'));
    await tester.pumpAndSettle();

    final picker = find.byType(TimePickerDialog);
    expect(picker, findsOneWidget);
    expect(MediaQuery.of(tester.element(picker)).alwaysUse24HourFormat, isTrue);
    expect(find.text('שעת התחלה'), findsWidgets);

    await tester.tap(find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.text('ביטול'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('שעת סיום'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('שעת סיום'), findsWidgets);
  });
}
