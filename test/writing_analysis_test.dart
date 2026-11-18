import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/entry/entry_draft.dart';
import 'package:sofer_vmone/logic/entry_builder.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/smart_live_recording.dart';
import 'package:sofer_vmone/logic/timer_controller.dart';
import 'package:sofer_vmone/logic/writing_analysis.dart';
import 'package:sofer_vmone/logic/writing_conditions.dart';
import 'package:sofer_vmone/logic/writing_timeline.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final project = Project(
      id: 'p',
      name: 'ספר',
      type: ProjectType.sefer,
      price: 100,
      expenses: 0,
      targetDaily: 1,
      targetMonthly: 20,
      linesPerPage: 42);
  WorkSession record(
      {String id = 's',
      String? visit = 'visit',
      int lines = 20,
      bool manual = false,
      bool known = true,
      DateTime? start,
      DateTime? end,
      List<WritingSpan>? spans,
      WritingConditions? conditions}) {
    final from = start ?? DateTime(2026, 11, 1, 9);
    return WorkSession(
        id: id,
        projectId: 'p',
        startTime: from,
        endTime: end ?? from.add(const Duration(minutes: 20)),
        amount: 1,
        startLine: 1,
        endLine: lines,
        description: '',
        isManual: manual,
        timeOfDayKnown: known,
        entryId: visit,
        extraFields: {
          if (visit != null) 'writingSittingId': visit,
          if (spans != null)
            WritingTimeline.key: [for (final span in spans) span.toJson()],
          if (conditions != null) WritingConditions.key: conditions.toJson(),
        });
  }

  WritingAnalysis analyze(List<WorkSession> history,
          {WritingFilter filter = const WritingFilter(),
          WritingGroup group = WritingGroup.weekday,
          Project? owner}) =>
      WritingAnalysis.build(
          projects: [owner ?? project],
          history: history,
          filter: filter,
          group: group);

  test(
      'hour bins divide a manual range, instead of assigning all work to its start',
      () {
    final s = record(
        manual: true,
        lines: 40,
        start: DateTime(2026, 11, 1, 8, 30),
        end: DateTime(2026, 11, 1, 10, 30));
    final result = analyze([s], group: WritingGroup.hour);
    expect(result.buckets.map((b) => b.key), ['8', '9', '10']);
    expect(result.buckets.map((b) => b.lines), [10, 20, 10]);
    expect(result.buckets.map((b) => b.linesPerHour), [20, 20, 20]);
    expect(result.total.sittings, 1);
    final filtered = analyze([s],
        group: WritingGroup.hour,
        filter: const WritingFilter(hourFrom: 9, hourTo: 10));
    expect(filtered.total.lines, 20);
    expect(filtered.total.workMs, 3600000);
  });
  test('real intervals keep a break out of the hourly analysis', () {
    final s = record(
        start: DateTime(2026, 11, 1, 9, 50),
        end: DateTime(2026, 11, 1, 10, 10),
        spans: [
          WritingSpan(
              DateTime(2026, 11, 1, 9), DateTime(2026, 11, 1, 9, 10), 600000),
          WritingSpan(
              DateTime(2026, 11, 1, 10), DateTime(2026, 11, 1, 10, 10), 600000),
        ]);
    final result = analyze([s], group: WritingGroup.hour);
    expect(result.buckets.map((b) => b.key), ['9', '10']);
    expect(result.buckets.map((b) => b.lines), [10, 10]);
    expect(result.total.workMs, 1200000);
  });
  test('reading remains work but receives no output or pen time', () {
    final s = record(
        lines: 10,
        start: DateTime(2026, 11, 1, 9, 55),
        end: DateTime(2026, 11, 1, 10, 5),
        spans: [
          WritingSpan(
              DateTime(2026, 11, 1, 9, 55), DateTime(2026, 11, 1, 10), 300000),
          WritingSpan(
              DateTime(2026, 11, 1, 10), DateTime(2026, 11, 1, 10, 5), 300000,
              reading: true),
        ]);
    final result = analyze([s], group: WritingGroup.hour);
    expect(result.buckets.first.lines, 10);
    expect(result.buckets.last.lines, 0);
    expect(result.total.readingMs, 300000);
    expect(result.total.linesPerHour, 60);
    expect(result.total.penLinesPerHour, 120);
    expect(result.buckets.last.penLinesPerHour, isNull);
  });
  test('many records from one sitting are counted once', () {
    final result = analyze([for (var i = 0; i < 10; i++) record(id: 's$i')]);
    expect(result.total.sittings, 1);
    expect(result.total.enoughData, isFalse);
    final visits =
        analyze([for (var i = 0; i < 3; i++) record(id: 's$i', visit: 'v$i')]);
    expect(visits.total.sittings, 3);
    expect(visits.total.enoughData, isTrue);
  });
  test('unknown session identities do not create confident results', () {
    final result =
        analyze([for (var i = 0; i < 10; i++) record(id: 's$i', visit: null)]);
    expect(result.total.sittings, 0);
    expect(result.total.unknownVisits.length, 10);
    expect(result.total.enoughData, isFalse);
  });
  test('legacy compressed times do not silently become measured hours', () {
    expect(analyze([record()], group: WritingGroup.hour).buckets, isEmpty);
    expect(
        analyze([record()], group: WritingGroup.hour).excludedUnknownHour, 1);
    expect(analyze([record()]).total.lines, 20);
    expect(
        analyze([record(manual: true, known: false)], group: WritingGroup.hour)
            .buckets,
        isEmpty);
  });
  test('zero humidity is measured, missing humidity is unknown', () {
    final history = [
      record(
          id: 'known',
          conditions: const WritingConditions(humidity: 0, temperatureC: 22)),
      record(id: 'unknown')
    ];
    final result = analyze(history,
        filter: const WritingFilter(minHumidity: 0, maxHumidity: 0));
    expect(result.total.lines, 20);
    expect(
        analyze(history, group: WritingGroup.climate).buckets.map((b) => b.key),
        containsAll(['22:0', '?']));
  });
  test('conditions and size filters use historical snapshots', () {
    final old = record(
        conditions: const WritingConditions(
            company: 'A', processing: 'hand', heightMm: 3));
    final current = const WritingConditions(company: 'B', heightMm: 4)
        .applyToProject(project);
    expect(
        analyze([old],
                owner: current,
                filter: const WritingFilter(company: 'A', height: 3))
            .total
            .lines,
        20);
    expect(
        analyze([old],
                owner: current, filter: const WritingFilter(company: 'B'))
            .buckets,
        isEmpty);
    expect(
        analyze([record()], owner: current, group: WritingGroup.company)
            .buckets
            .single
            .key,
        '?');
    expect(
        analyze([record()],
                owner: current, filter: const WritingFilter(height: -1))
            .total
            .lines,
        20);
  });
  test('weekday and period filters combine with overnight hour ranges', () {
    final late = record(
        manual: true,
        start: DateTime(2026, 11, 1, 23, 30),
        end: DateTime(2026, 11, 2, 0, 30));
    final result = analyze([late],
        filter: WritingFilter(
            from: DateTime(2026, 11, 1),
            to: DateTime(2026, 11, 1),
            weekdays: const {1},
            hourFrom: 22,
            hourTo: 6));
    // Manual entry dates are asserted by the writer; its midnight range stays
    // in that working day. Timed records use their captured day-boundary rule.
    expect(result.total.lines, 20);
    final timed = WorkSession.fromJson({...late.toJson(), 'isManual': false})
        .copyWith(dayRule: DayStart.midnight, extraFields: {
      WritingTimeline.key: [
        WritingSpan(late.startTime, late.endTime, 3600000).toJson()
      ]
    });
    expect(
        analyze([timed],
                filter: WritingFilter(
                    from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 1)))
            .total
            .lines,
        10);
    expect(analyze([late], filter: const WritingFilter(weekdays: {})).buckets,
        isEmpty);
  });
  test(
      'invalid work retains measured physical effort and deleted work is excluded',
      () {
    final s = record();
    expect(analyze([s.copyWith(isInvalid: true)]).total.lines, 20);
    expect(analyze([s.copyWith(isDeleted: true)]).buckets, isEmpty);
    expect(analyze([s.copyWith(backlogOnly: true)]).buckets, isEmpty);
    expect(analyze([s.copyWith(timeRecorded: false)]).excludedWithoutTime, 1);
  });
  test(
      'entry builder captures project conditions and does not replace them on edit',
      () {
    final p = const WritingConditions(company: 'original', heightMm: 3)
        .applyToProject(project);
    final result = EntryBuilder.build(
        input: EntryInput(
            project: p,
            start: DateTime(2026, 11, 1, 9),
            end: DateTime(2026, 11, 1, 10),
            isManual: true,
            pageFrom: '1',
            lineFrom: '1',
            lineTo: '20'),
        history: []);
    final saved = (result as EntryBuilt).sessions.single;
    expect(WritingConditions.session(saved).company, 'original');
    expect(WritingTimeline.of(saved).single.start, DateTime(2026, 11, 1, 9));
    expect(
        WritingConditions.session(WorkSession.fromJson(saved.toJson()))
            .heightMm,
        3);
  });
  test(
      'smart merging concatenates disjoint spans and keeps condition changes separate',
      () {
    final first = record(
        lines: 10,
        spans: [
          WritingSpan(
              DateTime(2026, 11, 1, 9), DateTime(2026, 11, 1, 9, 20), 1200000)
        ],
        conditions: const WritingConditions(company: 'A'));
    final next = record(
            id: 'next',
            spans: [
              WritingSpan(DateTime(2026, 11, 1, 10),
                  DateTime(2026, 11, 1, 10, 20), 1200000)
            ],
            conditions: const WritingConditions(company: 'A'))
        .copyWith(startLine: 11, endLine: 20);
    final merged = SmartLiveRecording.merge([first], [next]);
    expect(merged, hasLength(1));
    expect(WritingTimeline.of(merged.single), hasLength(2));
    expect(
        SmartLiveRecording.merge(
            [first], [const WritingConditions(company: 'B').stamp(next)]),
        hasLength(2));
  });
  test('slicing metadata keeps its real wall-clock location', () {
    final spans = [
      WritingSpan(
          DateTime(2026, 11, 1, 9), DateTime(2026, 11, 1, 9, 10), 600000),
      WritingSpan(
          DateTime(2026, 11, 1, 10), DateTime(2026, 11, 1, 10, 10), 600000)
    ];
    final slice = WritingTimeline.slice(spans, 900000, 300000).single;
    expect(slice.start, DateTime(2026, 11, 1, 10, 5));
    expect(slice.end, DateTime(2026, 11, 1, 10, 10));
  });
  test('malformed and nonfinite values are ignored instead of fabricated', () {
    final c = WritingConditions.fromJson({
      'humidity': double.nan,
      'heightMm': -1,
      'temperatureC': double.infinity,
      'processing': 'invalid'
    });
    expect(c.humidity, isNull);
    expect(c.heightMm, isNull);
    expect(c.temperatureC, isNull);
    expect(c.processing, '');
    expect(
        WritingSpan.decode([
          {'workMs': double.infinity},
          42,
          {}
        ]),
        isEmpty);
  });
  test('unknown-hour and untimed counts respect the chosen dates', () {
    final filter = WritingFilter(
        from: DateTime(2026, 11, 2, 9), to: DateTime(2026, 11, 2, 18));
    expect(
        analyze([record()], filter: filter, group: WritingGroup.hour)
            .excludedUnknownHour,
        0);
    expect(
        analyze([record().copyWith(timeRecorded: false)], filter: filter)
            .excludedWithoutTime,
        0);
    expect(
        analyze([record()],
                filter: WritingFilter(
                    from: DateTime(2026, 11, 1, 9),
                    to: DateTime(2026, 11, 1, 18)))
            .total
            .lines,
        20);
  });
  test('equal hour endpoints include the whole day, even with unknown hours',
      () {
    final s = record();
    const allDay = WritingFilter(hourFrom: 7, hourTo: 7);
    expect(analyze([s], filter: allDay).total.lines, 20);
    expect(
        analyze([s], filter: allDay, group: WritingGroup.hour)
            .excludedUnknownHour,
        1);
  });
  test('sunset divides the working weekday inside a clock hour', () {
    final sunset = HebrewClock.sunset(DateTime(2026, 11, 1))!.toLocal();
    final from = sunset.subtract(const Duration(minutes: 30));
    final to = sunset.add(const Duration(minutes: 30));
    final s =
        record(start: from, end: to, spans: [WritingSpan(from, to, 3600000)])
            .copyWith(dayRule: const DayStart(boundary: DayBoundary.sunset));
    final result = analyze([s]);
    expect(result.buckets.length, 2);
    expect(result.buckets.first.lines, closeTo(10, 0.001));
    expect(result.buckets.last.lines, closeTo(10, 0.001));
    expect(result.total.workMs, 3600000);
  });
  test(
      'restating a timer preserves reading totals but invalidates its old hours',
      () {
    final s = record(spans: [
      WritingSpan(
          DateTime(2026, 11, 1, 9), DateTime(2026, 11, 1, 9, 20), 1200000)
    ]).copyWith(
        extraFields: {'readingCorrectionMs': 300000, WritingTimeline.key: []});
    expect(analyze([s]).total.readingMs, 300000);
    expect(analyze([s], group: WritingGroup.hour).buckets, isEmpty);
  });
  group('timer wall-clock timeline', () {
    late DateTime now;
    late Duration mono;
    late TimerController clock;
    void pass(int minutes) {
      now = now.add(Duration(minutes: minutes));
      mono += Duration(minutes: minutes);
    }

    setUp(() {
      now = DateTime(2026, 11, 1, 9);
      mono = Duration.zero;
      clock =
          TimerController(onTick: () {}, now: () => now, monotonic: () => mono);
    });
    tearDown(() => clock.dispose());
    test('pause, resume, reading and a restart retain the actual intervals',
        () {
      clock.start();
      pass(10);
      clock.pause();
      pass(20);
      clock.start();
      pass(10);
      clock.beginReadingCorrection();
      pass(5);
      final saved = clock.checkpoint();
      clock.dispose();
      pass(5);
      clock =
          TimerController(onTick: () {}, now: () => now, monotonic: () => mono);
      expect(clock.restoreFrom(saved), isTrue);
      clock.endReadingCorrection();
      pass(5);
      final spans = clock.workIntervals;
      expect(spans.fold<int>(0, (n, s) => n + s.workMs),
          clock.elapsed.inMilliseconds);
      expect(spans.where((s) => s.reading).fold<int>(0, (n, s) => n + s.workMs),
          600000);
      expect(spans.first.start, DateTime(2026, 11, 1, 9));
      expect(spans[1].start, DateTime(2026, 11, 1, 9, 30));
      expect(
          spans.any((s) => s.start == DateTime(2026, 11, 1, 9, 10)), isFalse);
    });
    test(
        'restoring an old timer keeps its unknown bank, not invented clock hours',
        () {
      clock.restoreFrom({'isPaused': true, 'accumulatedElapsedSeconds': 600});
      clock.start();
      pass(5);
      expect(clock.workIntervals.first.start, isNull);
      expect(clock.workIntervals.last.start, DateTime(2026, 11, 1, 9));
    });
  });
  test('backup includes immutable conditions and pending real intervals',
      () async {
    StorageService.demoStore = MemoryStore({});
    addTearDown(() => StorageService.demoStore = null);
    final s = record(
        conditions: const WritingConditions(company: 'A', humidity: 45),
        spans: [
          WritingSpan(
              DateTime(2026, 11, 1, 9), DateTime(2026, 11, 1, 9, 20), 1200000)
        ]);
    await StorageService().saveHistory([s]);
    final draft = EntryDraft.timed(
        projectId: 'p',
        entryId: 'draft',
        measuredTime: s.duration,
        measuredEnd: s.endTime,
        writingConditions: WritingConditions.session(s).toJson(),
        writingSittingId: 'visit',
        workIntervals: s.extraFields[WritingTimeline.key] as List<dynamic>);
    await StorageService().savePendingEntry(draft);
    final snapshot = await StorageService().exportAllAfterPendingWrites();
    final restored = WorkSession.fromJson(
        Map<String, dynamic>.from((snapshot['history'] as List).single));
    expect(WritingConditions.session(restored).humidity, 45);
    final pending = EntryDraft.fromJson(
        jsonDecode((snapshot['migrationRecovery'] as Map)['pendingEntryRaw']));
    expect(pending.writingSittingId, 'visit');
    expect(WritingSpan.decode(pending.workIntervals).single.start,
        DateTime(2026, 11, 1, 9));
  });
}
