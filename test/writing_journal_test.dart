import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/writing_journal.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => StorageService.demoStore = null);

  group('WritingJournalSettings', () {
    test('round-trips every portable table choice', () {
      const settings = WritingJournalSettings(
        useAsHome: true,
        dateDisplay: JournalDateDisplay.gregorian,
        inIsrael: false,
        showProject: false,
        showTime: false,
        showNotes: false,
        showParsha: false,
        blankRowsPerDay: 5,
      );

      final restored = WritingJournalSettings.fromJson(settings.toJson());

      expect(restored.useAsHome, isTrue);
      expect(restored.dateDisplay, JournalDateDisplay.gregorian);
      expect(restored.inIsrael, isFalse);
      expect(restored.showProject, isFalse);
      expect(restored.showTime, isFalse);
      expect(restored.showNotes, isFalse);
      expect(restored.showParsha, isFalse);
      expect(restored.blankRowsPerDay, 5);
    });

    test('damaged values fall back and row count is bounded', () {
      final restored = WritingJournalSettings.fromJson({
        'dateDisplay': 'future-calendar',
        'blankRowsPerDay': 200,
      });

      expect(restored.dateDisplay, JournalDateDisplay.both);
      expect(restored.blankRowsPerDay, 6);
    });

    test('survives storage and travels in the portable backup settings',
        () async {
      StorageService.demoStore = MemoryStore({});
      final storage = StorageService();
      const chosen = WritingJournalSettings(
        useAsHome: true,
        dateDisplay: JournalDateDisplay.both,
        inIsrael: false,
        blankRowsPerDay: 4,
      );

      await storage.setWritingJournalSettings(chosen);
      final restored = await storage.getWritingJournalSettings();
      final backup = await storage.exportAll();

      expect(restored.toJson(), chosen.toJson());
      expect((backup['settings'] as Map)['writing_journal'], isA<String>());
    });

    test('malformed stored journal settings fail closed', () async {
      StorageService.demoStore = MemoryStore({'writing_journal': '{broken'});

      final restored = await StorageService().getWritingJournalSettings();

      expect(restored.toJson(), WritingJournalSettings.defaults.toJson());
    });
  });

  group('WritingJournalLogic', () {
    test('weeks always run from Sunday through Shabbat', () {
      final days = WritingJournalLogic.weekDays(DateTime(2026, 8, 27));

      expect(days.first, DateTime(2026, 8, 23));
      expect(days.last, DateTime(2026, 8, 29));
      expect(days.length, 7);
    });

    test('Israel and diaspora can produce different weekly portions', () {
      var foundDifference = false;
      for (var day = DateTime(2026, 4, 1);
          day.isBefore(DateTime(2026, 9, 1));
          day = day.add(const Duration(days: 7))) {
        final israel = WritingJournalLogic.weeklyParsha(day,
            inIsrael: true, english: false);
        final diaspora = WritingJournalLogic.weeklyParsha(day,
            inIsrael: false, english: false);
        if (israel != diaspora) {
          foundDifference = true;
          break;
        }
      }

      expect(foundDifference, isTrue);
    });

    test('blank export preserves two fillable rows for every day', () {
      final table = WritingJournalLogic.exportWeek(
        anyDayInWeek: DateTime(2026, 8, 27),
        projects: const [],
        history: const [],
        dayStart: DayStart.midnight,
        settings: WritingJournalSettings.defaults,
        english: false,
        blank: true,
      );

      expect(table.rows.length, 14);
      expect(table.headings,
          containsAll(['יום', 'תאריך', 'פרויקט', 'מה נכתב', 'זמן כתיבה']));
      expect(table.summary, contains('פרשת'));
    });

    test('filled export uses normal sessions and their project', () {
      final project = Project(
        id: 'sefer',
        name: 'ספר הבדיקה',
        type: ProjectType.sefer,
        price: 420,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 1,
        totalPages: 245,
        linesPerPage: 42,
      );
      final session = WorkSession(
        id: 'session',
        projectId: project.id,
        startTime: DateTime(2026, 8, 25, 9),
        endTime: DateTime(2026, 8, 25, 10, 30),
        amount: 7,
        startLine: 1,
        endLine: 21,
        description: 'עמוד ז (1–21)',
        isManual: true,
      );

      final table = WritingJournalLogic.exportWeek(
        anyDayInWeek: DateTime(2026, 8, 25),
        projects: [project],
        history: [session],
        dayStart: DayStart.midnight,
        settings: WritingJournalSettings.defaults,
        english: false,
        blank: false,
      );

      final written =
          table.rows.singleWhere((row) => row.cells.contains('עמוד ז (1–21)'));
      expect(written.cells, contains('ספר הבדיקה'));
      expect(written.cells, contains('01:30'));
    });
  });

  testWidgets('the optional journal home keeps the timer one tap away',
      (tester) async {
    final project = Project(
      id: 'home-project',
      name: 'ספר למסך הבית',
      type: ProjectType.sefer,
      price: 420,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      totalPages: 245,
      linesPerPage: 42,
    );
    const settings = WritingJournalSettings(useAsHome: true);
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([project.toJson()]),
      'history': '[]',
      'last_project': project.id,
      'writing_journal': jsonEncode(settings.toJson()),
    });

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.modern),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: SoferHome(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('מסך הטיימר'), findsOneWidget);
    expect(find.textContaining('הוסף רשומה'), findsWidgets);

    await tester.tap(find.text('מסך הטיימר'));
    await tester.pump();

    expect(find.text('הוספת כתיבה ידנית (ללא טיימר)'), findsOneWidget);
  });
}
