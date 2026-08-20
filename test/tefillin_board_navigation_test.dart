import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/project_summary_screen.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the separate ruled-theme board really switches by parshiya',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final project = Project(
      id: 't',
      name: 'הזמנת תפילין',
      type: ProjectType.tefillin,
      price: 1200,
      expenses: 0,
      targetDaily: 3,
      targetMonthly: 60,
      targetUnits: 4,
    );
    final history = [
      WorkSession(
        id: 'k',
        projectId: 't',
        startTime: DateTime(2026, 8, 1, 9),
        endTime: DateTime(2026, 8, 1, 10),
        amount: 1,
        startLine: 0,
        endLine: 0,
        tefillinType: 'head',
        parshiya: 1,
        pairIndex: 1,
        description: 'קדש',
        isManual: false,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.klaf),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ProjectSummaryScreen(projects: [project], history: history),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('מפת העבודה'), 500);
    await tester.tap(find.text('מפת העבודה'));
    await tester.pumpAndSettle();

    expect(find.text('לפי פרשייה'), findsOneWidget);
    expect(find.textContaining('מקביל ל־16 שורות'), findsNothing);
    await tester.tap(find.text('לפי פרשייה'));
    await tester.pumpAndSettle();

    expect(find.textContaining('מקביל ל־16 שורות'), findsOneWidget);
  });

  testWidgets('removing a rejected parshiya refreshes the open board',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final project = Project(
      id: 't',
      name: 'הזמנת תפילין',
      type: ProjectType.tefillin,
      price: 1200,
      expenses: 0,
      targetDaily: 3,
      targetMonthly: 60,
      targetUnits: 2,
      tefillinFlags: const {'1:head:2': 'void'},
    );
    final history = [
      for (var parshiya = 1; parshiya <= 3; parshiya++)
        WorkSession(
          id: 'p$parshiya',
          projectId: 't',
          startTime: DateTime(2026, 8, parshiya, 9),
          endTime: DateTime(2026, 8, parshiya, 10),
          amount: 1,
          startLine: 0,
          endLine: 0,
          tefillinType: 'head',
          parshiya: parshiya,
          pairIndex: 1,
          description: 'פרשייה $parshiya',
          isManual: false,
        ),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.klaf),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ProjectSummaryScreen(projects: [project], history: history),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('מפת העבודה'), 500);
    await tester.tap(find.text('מפת העבודה'));
    await tester.pumpAndSettle();

    // One label is the rejected cell and one is the board legend.
    expect(find.text('נפסל'), findsNWidgets(2));
    await tester.tap(find.text('נפסל').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('הסר את הפרשייה והתחל מחדש'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הסר והתחל מחדש'));
    await tester.pumpAndSettle();

    expect(find.text('נפסל'), findsOneWidget);
    expect(history[0].isDeleted, isFalse);
    expect(history[1].isDeleted, isTrue);
    expect(history[2].isDeleted, isTrue);
  });
}
