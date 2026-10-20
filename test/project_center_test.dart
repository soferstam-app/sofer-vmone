import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/projects_screen.dart';
import 'package:sofer_vmone/project_summary_screen.dart';
import 'package:sofer_vmone/recycle_bin_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Project project() => Project(
        id: 'sefer',
        name: 'ספר לבדיקה',
        type: ProjectType.sefer,
        price: 40000,
        expenses: 0,
        targetDaily: 21,
        targetMonthly: 420,
        totalPages: 245,
        linesPerPage: 42,
      );

  WorkSession work({bool deleted = false}) {
    final session = WorkSession(
      id: 'work',
      projectId: 'sefer',
      startTime: DateTime(2026, 8, 23, 9),
      endTime: DateTime(2026, 8, 23, 10),
      amount: 1,
      startLine: 1,
      endLine: 21,
      description: 'עמוד א שורות 1–21',
      isManual: true,
    );
    return deleted ? session.copyWith(isDeleted: true) : session;
  }

  Widget host(Widget child, {AppTheme theme = AppTheme.modern}) => MaterialApp(
        theme: AppThemeBuilder.build(theme),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      );

  tearDown(() => StorageService.demoStore = null);

  testWidgets('project tap opens the unified center and writing map',
      (tester) async {
    final p = project();
    final session = work();
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([p.toJson()]),
      'history': jsonEncode([session.toJson()]),
    });
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(ProjectsScreen(
      projects: [p],
      onProjectAdded: (_) {},
      onProjectUpdated: (_) {},
      onProjectDeleted: (_) {},
      onResetAllData: () {},
    )));
    await tester.pumpAndSettle();

    // Reset is no longer a large list item; it lives in the top overflow.
    expect(find.textContaining('איפוס כל הנתונים'), findsNothing);
    await tester.tap(find.text('ספר לבדיקה'));
    await tester.pumpAndSettle();
    expect(find.text('סקירה'), findsOneWidget);
    expect(find.text('הכתיבה'), findsOneWidget);
    expect(find.text('פרטים'), findsOneWidget);

    await tester.tap(find.text('הכתיבה'));
    await tester.pumpAndSettle();
    expect(find.text('מפת העמודים'), findsOneWidget);
    expect(find.byKey(const ValueKey('sefer-page-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sefer-page-1')));
    await tester.pumpAndSettle();
    expect(find.text('בחר שורות שנרשמו בטעות, או טפל בעמוד כולו.'),
        findsOneWidget);
  });

  testWidgets('klaf map keeps every page individually accessible',
      (tester) async {
    final p = project();
    final session = work();
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([p.toJson()]),
      'history': jsonEncode([session.toJson()]),
    });
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      ProjectsScreen(
        projects: [p],
        onProjectAdded: (_) {},
        onProjectUpdated: (_) {},
        onProjectDeleted: (_) {},
        onResetAllData: () {},
      ),
      theme: AppTheme.klaf,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ספר לבדיקה'));
    await tester.pumpAndSettle();
    // Exercise the parchment overview entry point that users actually tap. It
    // must open the same editable page map as the writing tab.
    await tester.scrollUntilVisible(find.text('מפת העבודה'), 300);
    await tester.tap(find.text('מפת העבודה'));
    await tester.pumpAndSettle();

    final firstPage = find.byKey(const ValueKey('sefer-page-1'));
    final secondPage = find.byKey(const ValueKey('sefer-page-2'));
    expect(firstPage, findsOneWidget);
    expect(secondPage, findsOneWidget);
    expect(tester.widget<Material>(firstPage).elevation, 0);

    await tester.tap(secondPage);
    await tester.pumpAndSettle();
    expect(find.text('העמוד טרם נכתב.'), findsOneWidget);
  });

  testWidgets('deleted writing record appears in the bin and restores',
      (tester) async {
    final p = project();
    final deleted = work(deleted: true);
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([p.toJson()]),
      'history': jsonEncode([deleted.toJson()]),
    });

    await tester.pumpWidget(host(const RecycleBinScreen()));
    await tester.pumpAndSettle();
    expect(find.text('עמוד א שורות 1–21'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.restore_from_trash));
    await tester.pumpAndSettle();
    final restored = await StorageService().loadHistory();
    expect(restored.single.isDeleted, isFalse);
    expect(find.text('סל המחזור ריק'), findsOneWidget);
  });

  testWidgets('editing a deadline refreshes the required daily line pace',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final today = DateTime.now();
    final firstDeadline = today.add(const Duration(days: 21));
    final laterDeadline = today.add(const Duration(days: 70));
    final original = project().copyWith(
      totalPages: 10,
      targetCompletionDate: firstDeadline,
    );
    final other = Project.fromJson({
      ...project().toJson(),
      'id': 'other',
      'name': 'ספר נוסף',
    });
    final projects = [original, other];
    StorageService.demoStore = MemoryStore({});

    await tester.pumpWidget(host(ProjectSummaryScreen(
      projects: projects,
      history: const [],
      initialProjectId: original.id,
      onEditProject: (current) async {
        final updated = current.copyWith(targetCompletionDate: laterDeadline);
        projects[0] = updated;
        return updated;
      },
    )));
    await tester.pumpAndSettle();

    final before = find.textContaining('שורות ליום עבודה');
    expect(before, findsWidgets);
    final beforeLabels =
        tester.widgetList<Text>(before).map((w) => w.data).toList();

    await tester.tap(find.text('פרטים'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('עריכה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('סקירה'));
    await tester.pumpAndSettle();

    final afterLabels = tester
        .widgetList<Text>(find.textContaining('שורות ליום עבודה'))
        .map((w) => w.data)
        .toList();
    expect(afterLabels, isNot(beforeLabels));
  });
}
