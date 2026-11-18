import 'package:sofer_vmone/entry/entry_draft.dart';
import 'package:sofer_vmone/widgets/writing_conditions_fields.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/entry/entry_sheet.dart';
import 'package:sofer_vmone/features_screen.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/home_additions.dart';
import 'package:sofer_vmone/logic/writing_conditions.dart';
import 'package:sofer_vmone/logic/writing_timeline.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/projects_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';
import 'package:sofer_vmone/writing_analysis_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in ['Heebo', 'FrankRuhlLibre']) {
      await (FontLoader(font)
            ..addFont(rootBundle.load('assets/fonts/$font-var.ttf')))
          .load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StorageService.demoStore = MemoryStore({});
  });
  tearDown(() {
    StorageService.demoStore = null;
    StorageService.onChanged = null;
  });
  final project = const WritingConditions(
          company: 'חברה א', processing: 'hand', heightMm: 3)
      .applyToProject(Project(
          id: 'p',
          name: 'מזוזות לבדיקה',
          type: ProjectType.mezuza,
          price: 100,
          expenses: 0,
          targetDaily: 0,
          targetMonthly: 0,
          targetUnits: 10));
  WorkSession session(String id, int hour, String company) {
    final start = DateTime(2026, 11, 1, hour);
    return WorkSession(
        id: id,
        projectId: 'p',
        startTime: start,
        endTime: start.add(const Duration(minutes: 30)),
        amount: 1,
        startLine: 0,
        endLine: 0,
        description: '',
        isManual: false,
        entryId: id,
        extraFields: {
          WritingConditions.key: WritingConditions(
                  company: company,
                  processing: 'hand',
                  heightMm: 3,
                  temperatureC: 22,
                  humidity: 45)
              .toJson(),
          WritingTimeline.key: [
            WritingSpan(start, start.add(const Duration(minutes: 30)), 1800000)
                .toJson()
          ]
        });
  }

  final history = [session('a', 9, 'חברה א'), session('b', 15, 'חברה ב')];
  Future<void> host(WidgetTester tester, Widget home,
      {AppTheme theme = AppTheme.modern,
      double width = 1100,
      double scale = 1,
      bool english = false,
      bool settle = true}) async {
    tester.view.physicalSize = Size(width, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(theme),
        locale: english ? const Locale('en', 'US') : const Locale('he', 'IL'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(
                textDirection: english ? TextDirection.ltr : TextDirection.rtl,
                child: child!)),
        home: home));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();
  }

  Future<void> field(WidgetTester tester, String label, String value) async {
    final f = find.widgetWithText(TextField, label);
    await tester.ensureVisible(f);
    await tester.enterText(f, value);
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  test('nonfinite input remains recoverable as text without invalid JSON', () {
    final c = WritingConditionsController(const WritingConditions());
    addTearDown(c.dispose);
    c.height.text = 'NaN';
    c.temperature.text = 'Infinity';
    final draft = EntryDraft(
        projectId: 'p',
        entryId: 'e',
        isManual: true,
        writingConditions: c.draftJson);
    final restored =
        EntryDraft.fromJson(jsonDecode(jsonEncode(draft.toJson())));
    final next = WritingConditionsController.draft(
        restored.writingConditions, const WritingConditions());
    addTearDown(next.dispose);
    expect(next.height.text, 'NaN');
    expect(next.error(), isNotNull);
    expect(next.value.heightMm, isNull);
  });
  for (final theme in AppTheme.values) {
    testWidgets('analysis filters and chart in $theme at large phone text',
        (tester) async {
      await host(
          tester, WritingAnalysisScreen(projects: [project], history: history),
          theme: theme, width: 360, scale: 2);
      final company = tester
          .widgetList<DropdownButton<String>>(
              find.byType(DropdownButton<String>))
          .firstWhere((w) => w.items!.any((i) => i.value == 'חברה א'));
      company.onChanged!('חברה א');
      await tester.pumpAndSettle();
      final compare = find.text('השוואה לפי');
      await tester.scrollUntilVisible(compare, 350,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('1 ישיבות מזוהות'), findsWidgets);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final group = tester
          .widgetList<DropdownButton<String>>(
              find.byType(DropdownButton<String>))
          .firstWhere((w) => w.items!.any((i) => i.value == 'climate'));
      group.onChanged!('climate');
      await tester.pumpAndSettle();
      expect(find.text('22–24°C · 40–50%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets('English filters, missing hours and validation are visible',
      (tester) async {
    await host(
        tester,
        WritingAnalysisScreen(projects: [
          project
        ], history: [
          history.first.copyWith(extraFields: {
            WritingConditions.key:
                const WritingConditions(company: 'A').toJson()
          })
        ]),
        english: true,
        width: 420,
        scale: 1.4);
    final group = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .firstWhere((w) => w.items!.any((i) => i.value == 'climate'));
    group.onChanged!('hour');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.textContaining('actual intervals are unknown'), 350,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('actual intervals are unknown'), findsOneWidget);
    final humidity = find.widgetWithText(TextField, 'Humidity from %');
    await tester.ensureVisible(humidity);
    await tester.enterText(humidity, '101');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.textContaining('Enter temperature from'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Enter temperature from'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('tools opens the analysis screen', (tester) async {
    await host(tester, FeaturesScreen(projects: [project], history: history));
    await tap(tester, find.text('תנאי כתיבה וקצב'));
    expect(find.byType(WritingAnalysisScreen), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
      'project editor persists optional conditions and validates height',
      (tester) async {
    Project? saved;
    await host(
        tester,
        Scaffold(
            body: ProjectDialog(
                existingProject: project, onSave: (p) => saved = p)));
    await tap(tester, find.text('תנאי כתיבה לסטטיסטיקה (רשות)'));
    await field(tester, 'חברת הקלף (רשות)', 'חברה חדשה');
    await field(tester, 'גובה הכתב במ״מ (רשות)', '-1');
    await tap(tester, find.text('שמור'));
    expect(saved, isNull);
    await field(tester, 'גובה הכתב במ״מ (רשות)', '3,5');
    await tap(tester, find.text('שמור'));
    expect(WritingConditions.project(saved!).company, 'חברה חדשה');
    expect(WritingConditions.project(saved!).heightMm, 3.5);
    await finish(tester);
  });
  testWidgets(
      'manual entry saves session conditions and keeps project defaults',
      (tester) async {
    EntrySave? saved;
    await host(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showEntrySheet(
                        context: context,
                        isManual: true,
                        projects: [project],
                        history: const [],
                        useGregorianDates: false,
                        dayStart: DayStart.midnight,
                        initialProject: project,
                        onProjectCreated: (_) {},
                        onSave: (s) async => saved = s),
                    child: const Text('open')))));
    await tap(tester, find.text('open'));
    await field(tester, 'כמות מזוזות', '1');
    await tap(tester, find.text('תנאי הישיבה (רשות)'));
    await field(tester, 'חברת הקלף (רשות)', 'קלף אחר');
    await field(tester, 'טמפרטורה בחדר °C (רשות)', '23');
    await field(tester, 'לחות בחדר % (רשות)', '50');
    await tap(tester, find.text('שמור וסגור'));
    expect(
        WritingConditions.session(saved!.sessions.single).company, 'קלף אחר');
    expect(WritingConditions.session(saved!.sessions.single).humidity, 50);
    expect(WritingConditions.project(project).company, 'חברה א');
    await finish(tester);
  });
  testWidgets('invalid environment remains in the recovery draft',
      (tester) async {
    await host(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showEntrySheet(
                        context: context,
                        isManual: true,
                        projects: [project],
                        history: const [],
                        useGregorianDates: false,
                        dayStart: DayStart.midnight,
                        initialProject: project,
                        onProjectCreated: (_) {},
                        onSave: (_) async {}),
                    child: const Text('open')))));
    await tap(tester, find.text('open'));
    await field(tester, 'כמות מזוזות', '1');
    await tap(tester, find.text('תנאי הישיבה (רשות)'));
    await field(tester, 'לחות בחדר % (רשות)', '101');
    await tap(tester, find.text('שמור וסגור'));
    final pending = await StorageService().getPendingEntry();
    expect((pending!.writingConditions!['_text'] as Map)['humidity'], '101');
    expect(find.textContaining('יש לבדוק'), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
      'smart session snapshots pending conditions and measured intervals',
      (tester) async {
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([project.toJson()]),
      'history': '[]',
      'last_project': 'p',
      'smart_workflow_enabled': true,
      'home_additions': jsonEncode(
          const HomeAdditionsSettings(writingConditionsEnabled: true).toJson())
    });
    await host(tester, const SoferHome());
    await tap(tester, find.text('תנאי הישיבה הבאה'));
    await field(tester, 'טמפרטורה בחדר °C (רשות)', '24');
    await field(tester, 'לחות בחדר % (רשות)', '40');
    await tap(tester, find.text('שמור לישיבה הבאה'));
    expect(
        WritingConditions.fromJson(
                await StorageService().getNextWritingConditions('p'))
            .humidity,
        40);
    await finish(tester);
    await host(tester, const SoferHome());
    final start = find.text('כניסה');
    await tester.ensureVisible(start);
    await tester.runAsync(() async {
      await tester.tap(start);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump(const Duration(milliseconds: 300));
    final state = await StorageService().getTimerState();
    expect(WritingConditions.fromJson(state['writingConditions']).humidity, 40);
    expect(state['writingSittingId'], isNotNull);
    expect(await StorageService().getNextWritingConditions('p'), isNull);
    expect(state['workIntervals'], isA<List>());
    // Restore the captured checkpoint to verify the original defaults are not
    // substituted after a project edit or application restart.
    final changed =
        const WritingConditions(company: 'changed').applyToProject(project);
    await finish(tester);
    final data = StorageService.demoStore!;
    await data.setString('projects', jsonEncode([changed.toJson()]));
    await host(tester, const SoferHome(), settle: false);
    await tester.ensureVisible(find.text('תנאי הישיבה'));
    await tester.tap(find.text('תנאי הישיבה'));
    await tester.pump(const Duration(milliseconds: 400));
    final company = tester
        .widget<TextField>(find.widgetWithText(TextField, 'חברת הקלף (רשות)'));
    expect(company.controller!.text, 'חברה א');
    final restored = await StorageService().getTimerState();
    expect(WritingConditions.fromJson(restored['writingConditions']).company,
        'חברה א');
    await finish(tester);
  });
}
