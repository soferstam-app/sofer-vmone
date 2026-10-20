import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/help/help_content.dart';
import 'package:sofer_vmone/help/help_screen.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.demoStore = null;
  });
  tearDown(() => StorageService.demoStore = null);

  test('the bundled help catalog contains every prepared question', () async {
    final catalog = await HelpCatalog.load();

    expect(catalog.sections, hasLength(20));
    expect(catalog.questionCount, 170);
    expect(
      catalog.sections.expand((section) => section.questions).map((q) => q.id),
      containsAll(['start-purpose', 'timer-finish-partial', 'support-report']),
    );
  });

  testWidgets('search finds an answer and clears back to all topics',
      (tester) async {
    const catalog = HelpCatalog([
      HelpSection(
        id: 'backup',
        title: 'גיבוי',
        questions: [
          HelpQuestion(
            id: 'backup-one',
            question: 'איך יוצרים גיבוי?',
            answer: 'שומרים קובץ גיבוי במכשיר.',
            keywords: ['שחזור'],
          ),
        ],
      ),
      HelpSection(
        id: 'timer',
        title: 'טיימר',
        questions: [
          HelpQuestion(
            id: 'timer-one',
            question: 'איך יוצאים להפסקה?',
            answer: 'לוחצים על כפתור ההפסקה.',
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.klaf),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: HelpScreen(catalog: catalog),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2 שאלות ב־2 נושאים'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'שחזור');
    await tester.pump();

    expect(find.text('1 תוצאות'), findsOneWidget);
    expect(find.text('איך יוצרים גיבוי?'), findsOneWidget);
    expect(find.text('איך יוצאים להפסקה?'), findsNothing);

    await tester.tap(find.byTooltip('נקה חיפוש'));
    await tester.pump();
    expect(find.text('2 שאלות ב־2 נושאים'), findsOneWidget);
    expect(find.text('גיבוי'), findsOneWidget);
    expect(find.text('טיימר'), findsOneWidget);
  });

  testWidgets('a question opens as native app content', (tester) async {
    const catalog = HelpCatalog([
      HelpSection(
        id: 'start',
        title: 'צעדים ראשונים',
        questions: [
          HelpQuestion(
            id: 'start-purpose',
            question: 'למה משמשת התוכנה?',
            answer: 'התשובה מוצגת בתוך מסך העזרה.',
          ),
        ],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.modern),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: HelpScreen(catalog: catalog),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('צעדים ראשונים'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('למה משמשת התוכנה?'));
    await tester.pumpAndSettle();

    expect(find.text('התשובה מוצגת בתוך מסך העזרה.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('help remains usable at maximum text size in every theme',
      (tester) async {
    const catalog = HelpCatalog([
      HelpSection(
        id: 'start',
        title: 'צעדים ראשונים',
        questions: [
          HelpQuestion(
            id: 'start-purpose',
            question: 'שאלה ארוכה שבודקת שהכיתוב נשאר קריא גם במסך צר?',
            answer: 'תשובה ארוכה מעט כדי לוודא שהפריסה גוללת ואינה נחתכת.',
          ),
        ],
      ),
    ]);
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final theme in AppTheme.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeBuilder.build(theme),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: HelpScreen(catalog: catalog),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: theme.name);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('the home help button opens the bundled native help screen',
      (tester) async {
    StorageService.demoStore = MemoryStore({});
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeBuilder.build(AppTheme.modern),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: SoferHome(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('עזרה'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(find.text('עזרה'), findsOneWidget);
    expect(find.text('170 שאלות ב־20 נושאים'), findsOneWidget);
    expect(find.text('צעדים ראשונים'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
