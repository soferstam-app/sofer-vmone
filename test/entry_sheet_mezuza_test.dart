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

  testWidgets('manual entry offers the unfinished mezuza for its second half',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final project = Project(
      id: 'mezuza',
      name: 'מזוזות',
      type: ProjectType.mezuza,
      price: 100,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
    );
    final firstHalf = WorkSession(
      id: 'first-half',
      projectId: project.id,
      startTime: DateTime(2026, 8, 20, 9),
      endTime: DateTime(2026, 8, 20, 10),
      amount: 1,
      startLine: 0,
      endLine: 11,
      description: 'מזוזה 1 עד שורה 11',
      isManual: true,
      mezuzaIndex: 1,
    );
    EntrySave? saved;

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
        child: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => showEntrySheet(
                context: context,
                isManual: true,
                projects: [project],
                history: [firstHalf],
                useGregorianDates: true,
                dayStart: DayStart.midnight,
                onProjectCreated: (_) {},
                onSave: (value) async => saved = value,
                initialProject: project,
              ),
              child: const Text('פתיחה'),
            );
          }),
        ),
      ),
    ));

    await tester.tap(find.text('פתיחה'));
    await tester.pumpAndSettle();

    expect(find.text('המשך מזוזה 1 — משורה 12'), findsOneWidget);

    expect(find.text('כמות מזוזות'), findsNothing);
    expect(
      find.text('במזוזה 1 נכתבו 11 מתוך 22 שורות. ממשיכים משורה 12.'),
      findsOneWidget,
    );
    expect(find.text('עד איזו שורה הגעת עכשיו'), findsOneWidget);

    await tester.tap(find.text('שמור וסגור'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.sessions.single.mezuzaIndex, 1);
    expect(saved!.sessions.single.endLine, 11);
    expect(saved!.reachedLine, 22);
  });

  testWidgets('manual entry defaults to the one unfinished tefillin parashah',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final project = Project(
      id: 'tefillin',
      name: 'תפילין',
      type: ProjectType.tefillin,
      price: 1000,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      targetUnits: 1,
    );
    final history = <WorkSession>[
      for (var parshiya = 1; parshiya <= 3; parshiya++)
        WorkSession(
          id: 'done-$parshiya',
          projectId: project.id,
          startTime: DateTime(2026, 8, 19, 9),
          endTime: DateTime(2026, 8, 19, 10),
          amount: 1,
          startLine: 0,
          endLine: 0,
          description: 'שלמה',
          isManual: true,
          tefillinType: 'hand',
          parshiya: parshiya,
          pairIndex: 1,
        ),
      WorkSession(
        id: 'partial-fourth',
        projectId: project.id,
        startTime: DateTime(2026, 8, 20, 9),
        endTime: DateTime(2026, 8, 20, 10),
        amount: 1,
        startLine: 0,
        endLine: 3,
        description: 'והיה אם שמע עד שורה 3',
        isManual: true,
        tefillinType: 'hand',
        parshiya: 4,
        pairIndex: 1,
      ),
    ];
    EntrySave? saved;

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.modern),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      locale: const Locale('he', 'IL'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('he', 'IL')],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Builder(builder: (context) {
            return ElevatedButton(
              onPressed: () => showEntrySheet(
                context: context,
                isManual: true,
                projects: [project],
                history: history,
                useGregorianDates: true,
                dayStart: DayStart.midnight,
                onProjectCreated: (_) {},
                onSave: (value) async => saved = value,
                initialProject: project,
              ),
              child: const Text('פתיחה'),
            );
          }),
        ),
      ),
    ));

    await tester.tap(find.text('פתיחה'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('המשך והיה אם שמע של יד, זוג 1 — משורה 4'),
      findsOneWidget,
    );
    expect(
      find.textContaining('נכתבו 3 מתוך 7 שורות'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('שמור וסגור'));
    await tester.tap(find.text('שמור וסגור'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.sessions.single.amount, 0);
    expect(saved!.sessions.single.startLine, 4);
    expect(saved!.sessions.single.endLine, 7);
    expect(saved!.sessions.single.pairIndex, 1);
    expect(saved!.sessions.single.parshiya, 4);
  });
}
