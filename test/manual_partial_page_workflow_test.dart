import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/project_summary_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Heebo', 'FrankRuhlLibre']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font-var.ttf')))
          .load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => StorageService.demoStore = null);

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  Future<void> field(WidgetTester tester, String label, String text) async {
    final target = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.decoration?.labelText == label);
    await tester.ensureVisible(target);
    await tester.enterText(target, text);
    await tester.pumpAndSettle();
  }

  for (final theme in AppTheme.values) {
    for (final phone in [true, false]) {
      testWidgets(
          'manual partial pages persist and display correctly: '
          '${theme.name}, phone=$phone', (tester) async {
        tester.view.physicalSize = Size(phone ? 420 : 1200, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final project = Project(
          id: 'p',
          name: 'ספר לבדיקה',
          type: ProjectType.sefer,
          price: 420,
          expenses: 0,
          targetDaily: 0,
          targetMonthly: 0,
          totalPages: 245,
          linesPerPage: 42,
        );
        StorageService.demoStore = MemoryStore({
          'projects': jsonEncode([project.toJson()]),
          'history': '[]',
          'last_project': project.id,
          'smart_workflow_enabled': false,
        });
        await tester.pumpWidget(MaterialApp(
          theme: AppThemeBuilder.build(theme)
              .copyWith(splashFactory: NoSplash.splashFactory),
          locale: const Locale('he', 'IL'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('he', 'IL')],
          home: const Directionality(
              textDirection: TextDirection.rtl, child: SoferHome()),
        ));
        await tester.pumpAndSettle();
        if (find.byIcon(Icons.edit_calendar).evaluate().isEmpty) {
          await tester.scrollUntilVisible(find.byIcon(Icons.edit_calendar), 300,
              scrollable: find.byType(Scrollable).first);
        }
        await tap(tester, find.byIcon(Icons.edit_calendar).first);
        await field(tester, 'מעמוד', '1');
        await field(tester, 'עד עמוד', '2');
        await field(tester, 'משורה', '1');
        await field(tester, 'עד שורה', '10');
        await tap(tester, find.text(phone ? 'שמור' : 'שמור וסגור'));
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        final saved = await StorageService().loadHistory();
        expect(saved, hasLength(2));
        expect(saved.map((s) => (s.amount, s.startLine, s.endLine)),
            [(1, 1, 42), (2, 1, 10)]);
        expect(ProductionCalculator.seferLinesTotal(saved), 52);
        expect(ProductionCalculator.seferPages(saved, project),
            closeTo(1 + 10 / 42, 1e-9));

        await tap(tester, find.text('סיכומים').first);
        expect(find.text('1 עמודים ו-10 שורות'), findsOneWidget);
        expect(find.text('2 עמודים ו-0 שורות'), findsNothing);
        await tap(tester, find.text('יום ▾'));
        expect(find.text('1 עמודים ו-10 שורות'), findsOneWidget);
        await tap(tester, find.byIcon(Icons.calendar_view_month));
        expect(find.textContaining('ספר לבדיקה: 1 עמודים ו-10 שורות'),
            findsOneWidget);
        expect(find.textContaining('2 עמודים ו-0 שורות'), findsNothing);

        // Re-open the project using the records read from storage, so the
        // project total is also checked after JSON serialization.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(MaterialApp(
          theme: AppThemeBuilder.build(theme),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ProjectSummaryScreen(
              projects: [project],
              history: saved,
              initialProjectId: project.id,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('1 עמודים ו-10 שורות'), findsOneWidget);
        expect(find.text('2 עמודים ו-0 שורות'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
