import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/entry/entry_sheet.dart';
import 'package:sofer_vmone/entry/journal_inline_editor.dart';
import 'package:sofer_vmone/hebrew_utils.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/writing_journal.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/plan/plan_export.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';
import 'package:sofer_vmone/writing_journal_screen.dart';

import 'support/fault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final day = DateTime(2026, 10, 15);
  final project = Project(
      id: 'p',
      name: 'ספר בדיקה',
      type: ProjectType.sefer,
      price: 420,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0,
      totalPages: 245,
      linesPerPage: 42);
  WorkSession slice(String id, int page, int from, int through, int hour,
          {String? entry = 'entry', DateTime? date}) =>
      WorkSession(
          id: id,
          entryId: entry,
          projectId: project.id,
          startTime: (date ?? day).add(Duration(hours: hour)),
          endTime: (date ?? day).add(Duration(hours: hour, minutes: 30)),
          workingDateAtEntry: date ?? day,
          amount: page,
          startLine: from,
          endLine: through,
          linesPerPageAtEntry: 42,
          description: 'עמוד $page ($from–$through)',
          isManual: true,
          extraFields: {
            'entryNotes': 'הערת בדיקה',
            'futureData': {'v': 7}
          });
  Widget host(Widget child, {AppTheme theme = AppTheme.modern}) => MaterialApp(
      theme: AppThemeBuilder.build(theme),
      home: Scaffold(
          body:
              Directionality(textDirection: TextDirection.rtl, child: child)));
  Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label);
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  setUp(() {
    StorageService.demoStore = MemoryStore({});
    StorageService.onChanged = null;
  });
  tearDown(() {
    StorageService.demoStore = null;
    StorageService.onChanged = null;
  });

  test('C1 groups by day/project/entry and sums measured time, without breaks',
      () {
    final first = slice('a', 43, 1, 42, 9);
    final second = slice('b', 44, 1, 21, 12);
    final legacy = slice('old', 5, 1, 1, 13, entry: null);
    final tomorrow =
        slice('next-day', 45, 1, 42, 9, date: day.add(const Duration(days: 1)));
    final otherProject =
        WorkSession.fromJson({...second.toJson(), 'projectId': 'other'});
    final entries = WritingJournalLogic.entriesOnDay(
        [first, second, legacy, tomorrow, otherProject],
        day,
        DayStart.midnight);
    expect(entries, hasLength(3));
    final combined = entries.singleWhere((e) => e.sessions.length == 2);
    expect(combined.duration, const Duration(hours: 1));
    expect(
        combined.descriptionFor(project, english: false), contains('שורה 21'));
    expect(combined.notes, 'הערת בדיקה');
    expect(
        WritingJournalLogic.entriesOnDay(
            [tomorrow], tomorrow.workingDateAtEntry!, DayStart.midnight),
        hasLength(1));
  });

  test(
      'C1-C3 grouped export carries notes into actual PDF and Excel generation',
      () async {
    final table = WritingJournalLogic.exportWeek(
        anyDayInWeek: day,
        projects: [project],
        history: [slice('a', 43, 1, 42, 9), slice('b', 44, 1, 21, 12)],
        dayStart: DayStart.midnight,
        settings: WritingJournalSettings.defaults,
        english: false,
        blank: false);
    final written =
        table.rows.where((r) => r.cells.contains('הערת בדיקה')).toList();
    expect(written, hasLength(1));
    expect(written.single.cells, contains('01:00'));
    final pdf = await PlanExport.toPdf(table);
    final xlsx = await PlanExport.toXlsx(table);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(xlsx.take(2), [0x50, 0x4b]);
  });

  testWidgets('C2 chosen day survives creating the first project',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    EntrySave? saved;
    final projects = <Project>[];
    await tester.pumpWidget(host(Builder(
        builder: (ctx) => TextButton(
            onPressed: () => showEntrySheet(
                context: ctx,
                isManual: true,
                projects: projects,
                history: [],
                useGregorianDates: true,
                dayStart: DayStart.midnight,
                initialDate: day,
                onProjectCreated: (p) async {
                  projects.add(p);
                },
                onSave: (entry) async {
                  saved = entry;
                }),
            child: const Text('פתח')))));
    await tap(tester, find.text('פתח'));
    await tap(tester, find.byTooltip('פרויקט חדש'));
    final name = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'שם הפרויקט');
    await tester.enterText(name, 'פרויקט ראשון');
    await tester.ensureVisible(field('מחיר'));
    await tester.enterText(field('מחיר'), '420');
    await tap(tester, find.text('שמור'));
    expect(find.textContaining(formatDisplayDate(day, true)), findsWidgets);
    await tester.enterText(field('מעמוד'), '1');
    await tester.enterText(field('משורה'), '1');
    await tester.enterText(field('עד שורה'), '2');
    await tap(tester, find.text('שמור וסגור'));
    expect(saved, isNotNull);
    expect(saved!.sessions.every((s) => s.workingDateAtEntry == day), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'C3 editing notes preserves exact timestamps, identities and extensions',
      (tester) async {
    final original = [slice('a', 43, 1, 42, 9), slice('b', 44, 1, 21, 12)];
    List<WorkSession>? edited;
    await tester.pumpWidget(host(SingleChildScrollView(
        child: JournalInlineEditor(
            day: day,
            entry: JournalEntry(original),
            projects: [project],
            history: original,
            onClose: () {},
            onFullForm: (draft, notes) async {},
            onAdd: (_) async {},
            onEdit: (next) async {
              edited = next;
            }))));
    await tester.enterText(field('הערות'), 'הערה חדשה');
    await tap(tester, find.text('שמור שורה'));
    expect(edited!.map((s) => s.id), ['a', 'b']);
    for (var i = 0; i < 2; i++) {
      expect(edited![i].startTime, original[i].startTime);
      expect(edited![i].endTime, original[i].endTime);
      expect(edited![i].extraFields['futureData'], {'v': 7});
      expect(edited![i].extraFields['entryNotes'], 'הערה חדשה');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'C3 shorter range keeps existing identities and tombstones removed pages',
      (tester) async {
    final original = [slice('a', 43, 1, 42, 9), slice('b', 44, 1, 21, 12)];
    List<WorkSession>? edited;
    await tester.pumpWidget(host(SingleChildScrollView(
        child: JournalInlineEditor(
            day: day,
            entry: JournalEntry(original),
            projects: [project],
            history: original,
            onClose: () {},
            onFullForm: (draft, notes) async {},
            onAdd: (_) async {},
            onEdit: (next) async {
              edited = next;
            }))));
    await tester.enterText(field('עד עמוד'), '43');
    await tap(tester, find.text('שמור שורה'));
    expect(edited!.singleWhere((s) => s.id == 'b').isDeleted, isTrue);
    final kept = edited!.singleWhere((s) => !s.isDeleted);
    expect(kept.id, 'a');
    expect(kept.startLine, 1);
    expect(kept.endLine, 21);
    expect(kept.duration, const Duration(hours: 1));
    expect(kept.extraFields['futureData'], {'v': 7});
  });

  testWidgets('C3 save failure retains all input and allows retry in the row',
      (tester) async {
    var fail = true;
    var closed = false;
    EntrySave? saved;
    await tester.pumpWidget(host(SingleChildScrollView(
        child: JournalInlineEditor(
            day: day,
            projects: [project],
            history: [],
            onClose: () {
              closed = true;
            },
            onFullForm: (draft, notes) async {},
            onEdit: (_) async {},
            onAdd: (next) async {
              if (fail) throw StateError('disk full');
              saved = next;
            }))));
    await tester.enterText(field('מעמוד'), '1');
    await tester.enterText(field('משורה'), '1');
    await tester.enterText(field('עד שורה'), '3');
    await tester.enterText(field('הערות'), 'שמור את ההערה');
    await tap(tester, find.text('שמור שורה'));
    expect(closed, isFalse);
    expect(saved, isNull);
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(tester.widget<TextField>(field('הערות')).controller!.text,
        'שמור את ההערה');
    fail = false;
    await tap(tester, find.text('שמור שורה'));
    expect(closed, isTrue);
    expect(saved!.sessions.single.extraFields['entryNotes'], 'שמור את ההערה');
  });

  for (final width in [430.0, 1000.0]) {
    for (final theme in AppTheme.values) {
      testWidgets('C3 journal row edits and reloads at width $width in $theme',
          (tester) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final current = DateUtils.dateOnly(DateTime.now());
        final original = slice('row', 43, 1, 42, 9, date: current);
        final store = FaultStore({
          'projects': jsonEncode([project.toJson()]),
          'history': jsonEncode([original.toJson()])
        });
        StorageService.demoStore = store;
        await tester.pumpWidget(host(
            WritingJournalScreen(
                projects: [project],
                history: [original],
                onProjectCreated: (_) async {},
                onSave: (_) async {}),
            theme: theme));
        await tester.pumpAndSettle();
        await tap(tester, find.text(original.description));
        await tester.enterText(field('הערות'), 'הערה נשמרה');
        await tap(tester, find.text('שמור שורה'));
        expect(find.byType(JournalInlineEditor), findsNothing);
        expect(
            (await StorageService().loadHistory())
                .single
                .extraFields['entryNotes'],
            'הערה נשמרה');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
