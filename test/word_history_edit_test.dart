import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/logic/writing_analysis.dart';
import 'package:sofer_vmone/logic/writing_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/tefillin_text.dart';
import 'package:sofer_vmone/summary/history_editor.dart';

void main() {
  for (final mode in ['manual', 'timer', 'unchanged']) {
    testWidgets('editing word-record hours in $mode mode', (tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = Project(
          id: 'p',
          name: 'Tefillin',
          type: ProjectType.tefillin,
          price: 0,
          expenses: 0,
          targetDaily: 0,
          targetMonthly: 0);
      final start = DateTime(2026, 11, 1, 9, 0, 20);
      final end = start.add(const Duration(minutes: 10));
      final s = WorkSession(
          id: 's',
          projectId: 'p',
          startTime: start,
          endTime: end,
          amount: 0,
          startLine: 0,
          endLine: 0,
          parshiya: 1,
          pairIndex: 1,
          tefillinType: 'head',
          description: 'Word record',
          isManual: mode != 'timer',
          dayRule: DayStart.midnight,
          extraFields: {
            TefillinWordRange.key: const TefillinWordRange(
                    parshiya: 1, from: 0, until: 3, script: 'beitYosef')
                .toJson(),
            WritingTimeline.key: [WritingSpan(start, end, 600000).toJson()]
          });
      List<WorkSession>? saved;
      await tester.pumpWidget(MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showHistoryEditor(
                          context: context,
                          projects: [p],
                          history: [s],
                          day: start,
                          dayLabel: 'today',
                          dayStart: DayStart.midnight,
                          useGregorianDates: true,
                          startWithAllDays: true,
                          onHistoryUpdated: (v) {
                            saved = v;
                          }),
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      if (mode != 'unchanged') {
        await tester.enterText(
            find.widgetWithText(TextField, 'Start time HH:MM'), '20:00');
        await tester.enterText(
            find.widgetWithText(TextField, 'End time HH:MM'), '20:10');
      }
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isNotNull);
      final a = WritingAnalysis.build(
          projects: [p],
          history: saved!,
          filter: const WritingFilter(),
          group: WritingGroup.hour);
      expect(tester.takeException(), isNull);
      expect(saved!.single.startTime,
          mode == 'unchanged' ? start : DateTime(2026, 11, 1, 20));
      expect(
          a.buckets.map((b) => b.key),
          switch (mode) {
            'timer' => <String>[],
            'unchanged' => ['9'],
            _ => ['20'],
          });
    });
  }
}
