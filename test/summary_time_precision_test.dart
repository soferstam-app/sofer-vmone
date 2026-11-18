import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/l10n/yiddish_material.dart';
import 'package:sofer_vmone/logic/calendar_days.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/writing_journal.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/summary_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => StorageService.demoStore = null);

  for (final (language, day, week, previous, next) in [
    (AppLanguage.hebrew, 'יום', 'שבוע', 'השבוע הקודם', 'השבוע הבא'),
    (AppLanguage.english, 'Day', 'Week', 'Previous week', 'Next week'),
    (
      AppLanguage.yiddish,
      'טאָג',
      'וואָך',
      'פֿריִערדיקע וואָך',
      'קומענדיקע וואָך'
    ),
  ]) {
    testWidgets('weekly summary follows working dates in ${language.name}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final project = Project(
        id: 'p',
        name: 'Sample project',
        type: ProjectType.sefer,
        price: 4200,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 0,
        totalPages: 10,
        linesPerPage: 42,
      );
      final sunday = WritingJournalLogic.weekStart(DateTime.now());
      final followingSunday = CalendarDays.addDays(sunday, 7);
      WorkSession session(String id, DateTime start, int lines,
              {DayStart? rule, bool backlog = false}) =>
          WorkSession(
            id: id,
            projectId: project.id,
            startTime: start,
            endTime: start.add(const Duration(minutes: 2)),
            amount: 1,
            startLine: 1,
            endLine: lines,
            description: '',
            isManual: true,
            linesPerPageAtEntry: 42,
            dayRule: rule,
            backlogOnly: backlog,
          );
      StorageService.demoStore = MemoryStore({});
      await tester.pumpWidget(MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        locale: language.frameworkLocale,
        localizationsDelegates: [
          AppLocalizations.delegateFor(language),
          if (language == AppLanguage.yiddish) const YiddishMaterialDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: SummaryScreen(
          projects: [project],
          history: [
            session('first', sunday, 3),
            session(
                'saturday', followingSunday.add(const Duration(minutes: 30)), 4,
                rule: const DayStart(boundary: DayBoundary.fixedHour, hour: 2)),
            session('next', followingSunday, 11),
            session('backlog', sunday, 30, backlog: true),
          ],
          onHistoryUpdated: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('$day ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(week));
      await tester.pumpAndSettle();
      final period = find.text('$week ▾');
      final projectCard = find.ancestor(
          of: find.text(project.name), matching: find.byType(Card));
      Finder output(int lines) => find.descendant(
          of: projectCard,
          matching: find.textContaining(RegExp('^0\\D+$lines\\D+')));
      expect(
          Directionality.of(tester.element(period)),
          language == AppLanguage.english
              ? TextDirection.ltr
              : TextDirection.rtl);
      expect(find.text('Sample project'), findsOneWidget);
      expect(output(7), findsOneWidget);
      expect(find.text('00:04'), findsOneWidget);
      expect(find.textContaining('1050'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.byTooltip(next));
      await tester.pumpAndSettle();
      expect(output(11), findsOneWidget);
      await tester.tap(find.byTooltip(previous));
      await tester.pumpAndSettle();
      expect(output(7), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('daily summary calculates line average with seconds',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final project = Project(
      id: 'p',
      name: 'ספר',
      type: ProjectType.sefer,
      price: 420,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0,
      totalPages: 10,
      linesPerPage: 42,
    );
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 10);
    final session = WorkSession(
      id: 'line',
      projectId: project.id,
      startTime: start,
      endTime: start.add(const Duration(minutes: 1, seconds: 30)),
      amount: 1,
      startLine: 1,
      endLine: 1,
      description: '',
      isManual: true,
      linesPerPageAtEntry: 42,
    );
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([project.toJson()]),
      'history': jsonEncode([session.toJson()]),
    });

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: SummaryScreen(
          projects: [project],
          history: [session],
          onHistoryUpdated: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1.50 דקות לשורה'), findsOneWidget);
  });
}
