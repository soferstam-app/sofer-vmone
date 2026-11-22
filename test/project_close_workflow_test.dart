import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/entry/entry_draft.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/l10n/yiddish_material.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/project_summary_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/summary_screen.dart';
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

  WorkSession work() {
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
    return session;
  }

  Widget host(Widget child, {AppTheme theme = AppTheme.modern}) => MaterialApp(
        theme: AppThemeBuilder.build(theme),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      );

  tearDown(() => StorageService.demoStore = null);

  for (final (language, close, reopen, direction) in [
    (
      AppLanguage.english,
      'Close project',
      'Reopen for writing',
      TextDirection.ltr
    ),
    (
      AppLanguage.yiddish,
      'שליסן דעם פּראָיעקט',
      'עפֿן ווידער צום שרײַבן',
      TextDirection.rtl
    ),
  ]) {
    testWidgets('project status controls fit a phone in ${language.name}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      StorageService.demoStore = MemoryStore({});
      await tester.pumpWidget(MaterialApp(
        locale: language.frameworkLocale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegateFor(language),
          if (language == AppLanguage.yiddish) const YiddishMaterialDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: ProjectSummaryScreen(
          projects: [project()],
          history: const [],
          onSetProjectClosed: (current, closed) async =>
              current.copyWith(isClosed: closed),
        ),
      ));
      await tester.pumpAndSettle();
      final control = find.text(close);
      expect(Directionality.of(tester.element(control)), direction);
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect(find.text(reopen), findsOneWidget);
    });
  }

  testWidgets('closing a project hides it from writing and keeps its records',
      (tester) async {
    final p = project();
    final session = work();
    final legacy = p.toJson()..remove('isClosed');
    expect(Project.fromJson(legacy).isClosed, isFalse);
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([legacy]),
      'history': jsonEncode([session.toJson()]),
      'last_project': p.id,
    });
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> tapText(String label) async {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    Future<void> goBack() async {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(host(const SoferHome()));
    await tester.pumpAndSettle();
    expect(find.text(p.name), findsOneWidget);
    await tapText('פרויקטים');
    await tapText(p.name);
    await StorageService().savePendingEntry(EntryDraft(
      entryId: 'unsaved',
      projectId: p.id,
      isManual: false,
    ));
    await tapText('סגור פרויקט');
    expect((await StorageService().loadProjects()).single.isClosed, isFalse);
    expect(
      find.text('יש לסיים ולשמור את ישיבת הכתיבה לפני סגירת הפרויקט.'),
      findsOneWidget,
    );
    await StorageService().clearPendingEntry();
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    await tapText('סגור פרויקט');
    expect(find.text('פתח מחדש לכתיבה'), findsOneWidget);
    expect((await StorageService().loadProjects()).single.isClosed, isTrue);
    await goBack();
    expect(find.textContaining('פרויקט סגור'), findsOneWidget);
    await goBack();
    expect(find.text(p.name), findsNothing);
    expect(find.text('אין פרויקטים פתוחים לכתיבה'), findsOneWidget);

    await tapText('סיכומים');
    final summary = tester.widget<SummaryScreen>(find.byType(SummaryScreen));
    expect(summary.projects.single.name, p.name);
    expect(summary.history.single.id, session.id);
    await tester.tap(find.byIcon(Icons.folder_special));
    await tester.pumpAndSettle();
    await tapText('פתח מחדש לכתיבה');
    expect((await StorageService().loadProjects()).single.isClosed, isFalse);
    expect((await StorageService().loadHistory()).single.id, session.id);
    await goBack();
    await goBack();
    expect(find.text('אין פרויקטים פתוחים לכתיבה'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
