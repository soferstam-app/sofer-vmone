// Opening the monthly summary must not throw.
//
// It froze the app on Windows, and the cause was not the arithmetic — that
// takes eight milliseconds. AlertDialog sizes itself by asking its content how
// wide it wants to be, and the daily chart is built with a LayoutBuilder, which
// cannot answer that question and throws. Every layout pass, on repeat: a
// window that stops responding the moment the summary is opened.
//
// This pumps ninety frames of it, which is the whole bar animation, and
// requires that nothing at all was thrown.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/summary/monthly_summary.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The dialog reads expenses before it opens. Keep that read synchronous
    // with the widget test's fake clock instead of waiting on a platform
    // channel that this test is not intended to exercise.
    StorageService.demoStore = MemoryStore({});
  });
  tearDown(() => StorageService.demoStore = null);

  final project = Project(
    id: 'p1',
    name: 'ספר תורה',
    type: ProjectType.sefer,
    price: 400,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 42,
    totalPages: 245,
  );

  final now = DateTime.now();
  final history = [
    for (var i = 0; i < 6; i++)
      WorkSession(
        id: 's$i',
        projectId: 'p1',
        // Keep every sample in the Hebrew month under test. Using the first
        // Gregorian week of DateTime.now().month becomes the previous Hebrew
        // month whenever Rosh Chodesh falls later in the Gregorian month.
        startTime: DateTime(now.year, now.month, now.day, 7 + i * 2),
        endTime: DateTime(now.year, now.month, now.day, 8 + i * 2),
        amount: 1 + i,
        startLine: 1,
        endLine: 42,
        linesPerPageAtEntry: 42,
        description: '',
        isManual: true,
        workingDateAtEntry: DateTime(now.year, now.month, now.day),
      ),
  ];

  testWidgets('opening it throws nothing, over the whole animation',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.klaf),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showMonthlySummary(
                  context: context,
                  projects: [project],
                  history: history,
                  month: now,
                  dayStart: DayStart.midnight,
                  rules: const WorkCalendarRules(),
                  currency: Currency.ils,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    // Deliberately not pumpAndSettle: a never-ending animation would hang it,
    // and pumping frames by hand shows how far it gets.
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull,
        reason: 'the dialog must survive being laid out and animated');
    expect(find.text('סיכום חודשי'), findsOneWidget);
  });
}
