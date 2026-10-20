import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/entry/tefillin_words_dialog.dart';
import 'package:sofer_vmone/logic/entry_builder.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/tefillin_state.dart';
import 'package:sofer_vmone/logic/tefillin_text.dart';
import 'package:sofer_vmone/logic/tefillin_units.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final p = TefillinPreferences.update(
      Project(
          id: 't',
          name: 'תפילין',
          type: ProjectType.tefillin,
          price: 1200,
          expenses: 0,
          targetDaily: 0,
          targetMonthly: 0,
          targetUnits: 1),
      words: true);
  final start = DateTime(2026, 10, 15, 9);
  WorkSession legacy(int parshiya, String side, {int lines = 0}) => WorkSession(
      id: 'old-$side-$parshiya',
      projectId: p.id,
      startTime: start,
      endTime: start.add(const Duration(minutes: 10)),
      amount: 1,
      startLine: lines > 0 ? 1 : 0,
      endLine: lines,
      pairIndex: 1,
      tefillinType: side,
      parshiya: parshiya,
      description: 'עבר',
      isManual: true);
  EntryOutcome build(
          int parshiya, String side, int until, List<WorkSession> history,
          {StamScript script = StamScript.beitYosef,
          int? base,
          String entryId = 'entry'}) =>
      EntryBuilder.build(
          input: EntryInput(
              project: p,
              start: start,
              end: start.add(const Duration(minutes: 10)),
              isManual: true,
              statedDate: start,
              entryId: entryId,
              tefillinMode: 'parshiya',
              tefillinPart: side,
              tefillinPair: '1',
              tefillinParshiya: parshiya,
              tefillinUntilWord: until,
              tefillinBaselineWord: base,
              tefillinScript: script),
          history: history);

  test('canonical texts keep the reviewed word and letter counts', () {
    expect(TefillinText.all.map((t) => t.words.length), [133, 100, 48, 122]);
    expect(TefillinText.all.map((t) => t.letters), [504, 377, 205, 508]);
    for (final text in TefillinText.all) {
      expect(text.words.every((w) => RegExp(r'^[א-ת]+$').hasMatch(w)), isTrue);
      expect(text.letterBoundaries.first, 0);
      expect(text.letterBoundaries.last, text.letters);
    }
  });

  for (final script in StamScript.values) {
    for (final side in ['head', 'hand']) {
      for (var parshiya = 1; parshiya <= 4; parshiya++) {
        test(
            '$script $side parshiya $parshiya uses new letters and sums to the full weight',
            () {
          final history = [
            for (var previous = 1; previous < parshiya; previous++)
              legacy(previous, side)
          ];
          final text = TefillinText.of(parshiya);
          final first =
              (build(parshiya, side, 3, history, script: script) as EntryBuilt)
                  .sessions
                  .single;
          expect(first.amount, 0);
          expect(first.isTimeOnly, isFalse);
          expect(first.countsAsOutput, isTrue);
          expect(TefillinWordRange.read(first)!.from, 0);
          expect(
              ProductionCalculator.tefillinSeferLines(first),
              closeTo(
                  TefillinUnits.seferLines[parshiya - 1] *
                      text.letterBoundaries[3] /
                      text.letters,
                  1e-9));
          final last = (build(
                  parshiya, side, text.words.length, [...history, first],
                  script: script, entryId: 'last') as EntryBuilt)
              .sessions
              .single;
          expect(TefillinWordRange.read(last)!.from, 3);
          expect(
              ProductionCalculator.tefillinSeferLines(first) +
                  ProductionCalculator.tefillinSeferLines(last),
              closeTo(TefillinUnits.seferLines[parshiya - 1], 1e-9));
          final slot = TefillinState.slots(p, [...history, first, last])
              .singleWhere((s) =>
                  s.pair == 1 &&
                  s.side ==
                      (side == 'head'
                          ? TefillinSide.head
                          : TefillinSide.hand) &&
                  s.parshiya == parshiya);
          expect(slot.wordBoundary, text.words.length);
          expect(slot.state, SlotState.done);
          final restored = WorkSession.fromJson(
              jsonDecode(jsonEncode(last.toJson())) as Map<String, dynamic>);
          expect(TefillinWordRange.read(restored)!.until, text.words.length);
          expect(TefillinWordRange.read(restored)!.script, script.id);
        });
      }
    }
  }

  test('words require a complete predecessor and cannot overlap saved words',
      () {
    expect(build(2, 'head', 2, []), isA<EntryRejected>());
    final first = (build(1, 'head', 3, []) as EntryBuilt).sessions.single;
    expect(
        build(1, 'head', 3, [first], entryId: 'another'), isA<EntryRejected>());
    expect(
        build(1, 'head', 2, [first], entryId: 'another'), isA<EntryRejected>());
  });

  test(
      'legacy partial needs an explicit word baseline and full total remains exact',
      () {
    final previous = legacy(1, 'head', lines: 2);
    final count = TefillinText.of(1).words.length;
    expect(build(1, 'head', count, [previous]), isA<EntryRejected>());
    final completion =
        (build(1, 'head', count, [previous], base: 20) as EntryBuilt)
            .sessions
            .single;
    expect(TefillinWordRange.read(completion)!.baselineWord, 20);
    expect(
        ProductionCalculator.tefillinSeferLines(previous) +
            ProductionCalculator.tefillinSeferLines(completion),
        closeTo(16, 1e-9));
  });

  test(
      'an unsupported canonical version fails closed without changing the source',
      () {
    final first = (build(1, 'head', 3, []) as EntryBuilt).sessions.single;
    final range = {
      ...first.extraFields[TefillinWordRange.key] as Map<String, dynamic>,
      'version': 'future-version'
    };
    final future = first.copyWith(extraFields: {TefillinWordRange.key: range});
    expect(TefillinWordRange.read(future), isNull);
    expect(ProductionCalculator.tefillinSeferLines(future), 0);
    expect(future.extraFields[TefillinWordRange.key], range);
    expect(build(1, 'head', 5, [future], entryId: 'another'),
        isA<EntryRejected>());
  });

  for (final script in StamScript.values) {
    testWidgets(
        '$script saved word is red, selection is green and arrows/Enter confirm',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      int? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (ctx) => TextButton(
                      onPressed: () async {
                        selected = await showTefillinWords(
                            context: ctx,
                            parshiya: 3,
                            script: script,
                            unitLabel: 'ראש זוג 1',
                            fromWord: 1);
                      },
                      child: const Text('פתח'))))));
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
      Finder word(String text) => find.byWidgetPredicate((w) =>
          w is Text && w.data == text && w.style?.fontFamily == script.family);
      expect(tester.widget<Text>(word('שמע')).style!.color,
          const Color(0xFFB71C1C));
      await tester.tap(word('ישראל'));
      await tester.pump();
      expect(tester.widget<Text>(word('ישראל')).style!.color,
          const Color(0xFF1B5E20));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, isNotNull);
      expect(selected, greaterThan(1));
      expect(tester.takeException(), isNull);
    });
  }
}
