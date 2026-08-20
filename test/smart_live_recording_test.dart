import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/production_calculator.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/smart_live_recording.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  WorkSession checkpoint({
    required String id,
    required String entry,
    required DateTime start,
    required DateTime end,
    int page = 5,
    int from = 1,
    int to = 1,
    int amount = 5,
    int? mezuza,
    String? tefillinType,
    int? parshiya,
    int? pair,
    String description = 'כתיבה רציפה',
    DayStart? dayRule,
  }) =>
      WorkSession(
        id: id,
        projectId: 'p',
        startTime: start,
        endTime: end,
        amount: amount,
        startLine: from,
        endLine: to,
        mezuzaIndex: mezuza,
        tefillinType: tefillinType,
        parshiya: parshiya,
        pairIndex: pair,
        description: description,
        isManual: false,
        entryId: entry,
        dayRule: dayRule,
      );

  final nine = DateTime(2026, 8, 19, 9);

  test('line checkpoints become one growing page record', () {
    var history = <WorkSession>[];
    for (var line = 1; line <= 3; line++) {
      final start = nine.add(Duration(minutes: (line - 1) * 5));
      history = SmartLiveRecording.merge(history, [
        checkpoint(
          id: 'line-$line',
          entry: 'sitting',
          start: start,
          end: start.add(const Duration(minutes: 5)),
          from: line,
          to: line,
        ),
      ]);
    }

    expect(history, hasLength(1));
    expect(history.single.id, 'line-1', reason: 'the stored id stays stable');
    expect(history.single.startLine, 1);
    expect(history.single.endLine, 3);
    expect(history.single.duration, const Duration(minutes: 15));
    expect(ProductionCalculator.seferLinesTotal(history), 3);
  });

  test('a break between lines is not folded into writing time', () {
    final first = checkpoint(
      id: 'first',
      entry: 'sitting',
      start: nine,
      end: nine.add(const Duration(minutes: 5)),
    );
    final afterBreak = checkpoint(
      id: 'second',
      entry: 'sitting',
      start: nine.add(const Duration(minutes: 20)),
      end: nine.add(const Duration(minutes: 27)),
      from: 2,
      to: 2,
    );

    final merged = SmartLiveRecording.merge([first], [afterBreak]).single;
    expect(merged.duration, const Duration(minutes: 12));
    expect(merged.endTime, afterBreak.endTime);
  });

  test('a full mezuza remains one record while all 22 lines are durable', () {
    var history = <WorkSession>[];
    for (var line = 1; line <= ProductionCalculator.linesPerMezuza; line++) {
      final start = nine.add(Duration(minutes: line));
      history = SmartLiveRecording.merge(history, [
        checkpoint(
          id: 'm$line',
          entry: 'sitting',
          start: start,
          end: start.add(const Duration(minutes: 1)),
          amount: 1,
          from: 0,
          to: 1,
          mezuza: 7,
        ),
      ]);
    }

    expect(history, hasLength(1));
    expect(history.single.mezuzaIndex, 7);
    expect(history.single.endLine, 0, reason: 'zero is the complete shape');
    expect(ProductionCalculator.mezuzaLinesTotal(history), 22);
  });

  test('a tefillin parshiya grows without being counted four times', () {
    var history = <WorkSession>[];
    for (var line = 1; line <= 4; line++) {
      final start = nine.add(Duration(minutes: line));
      history = SmartLiveRecording.merge(history, [
        checkpoint(
          id: 't$line',
          entry: 'sitting',
          start: start,
          end: start.add(const Duration(minutes: 1)),
          amount: line == 1 ? 1 : 0,
          from: line,
          to: line,
          tefillinType: 'head',
          parshiya: 1,
          pair: 3,
          description: line == 4 ? 'פרשייה שלמה' : 'עד שורה $line',
        ),
      ]);
    }

    expect(history, hasLength(1));
    expect(history.single.amount, 1);
    expect(history.single.startLine, 1);
    expect(history.single.endLine, 4);
    expect(ProductionCalculator.parshiyotTotal(history), 1);
  });

  test('different sittings never merge', () {
    final first = checkpoint(
      id: 'a',
      entry: 'one',
      start: nine,
      end: nine.add(const Duration(minutes: 2)),
    );
    final second = checkpoint(
      id: 'b',
      entry: 'two',
      start: nine.add(const Duration(minutes: 2)),
      end: nine.add(const Duration(minutes: 4)),
      from: 2,
      to: 2,
    );
    expect(SmartLiveRecording.merge([first], [second]), hasLength(2));
  });

  test('one sitting is split when it crosses the working-day boundary', () {
    final first = checkpoint(
      id: 'before-midnight',
      entry: 'overnight',
      start: DateTime(2026, 8, 19, 23, 50),
      end: DateTime(2026, 8, 19, 23, 55),
      dayRule: DayStart.midnight,
    );
    final second = checkpoint(
      id: 'after-midnight',
      entry: 'overnight',
      start: DateTime(2026, 8, 20, 0, 5),
      end: DateTime(2026, 8, 20, 0, 10),
      from: 2,
      to: 2,
      dayRule: DayStart.midnight,
    );

    expect(SmartLiveRecording.merge([first], [second]), hasLength(2));
  });

  test('clock midnight may still merge inside a later working-day boundary',
      () {
    const boundary = DayStart(boundary: DayBoundary.fixedHour, hour: 2);
    final first = checkpoint(
      id: 'before-midnight',
      entry: 'overnight',
      start: DateTime(2026, 8, 19, 23, 50),
      end: DateTime(2026, 8, 19, 23, 55),
      dayRule: boundary,
    );
    final second = checkpoint(
      id: 'after-midnight',
      entry: 'overnight',
      start: DateTime(2026, 8, 20, 0, 5),
      end: DateTime(2026, 8, 20, 0, 10),
      from: 2,
      to: 2,
      dayRule: boundary,
    );

    expect(SmartLiveRecording.merge([first], [second]), hasLength(1));
  });
}
