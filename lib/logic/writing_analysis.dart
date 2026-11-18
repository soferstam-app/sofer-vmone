import 'work_time_breakdown.dart';
import '../models.dart';
import 'date_logic.dart';
import 'hebrew_clock.dart';
import 'production_calculator.dart';
import 'writing_conditions.dart';
import 'writing_timeline.dart';

enum WritingGroup { weekday, hour, type, company, processing, height, climate }

class WritingFilter {
  final DateTime? from;
  final DateTime? to;
  final String? projectId;
  final ProjectType? type;
  final Set<int> weekdays;
  final int hourFrom;
  final int hourTo;
  final String? company;
  final String? processing;
  final double? height;
  final double? minTemperature, maxTemperature, minHumidity, maxHumidity;
  final int? parshiya;
  final String? side;
  const WritingFilter(
      {this.from,
      this.to,
      this.projectId,
      this.type,
      this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
      this.hourFrom = 0,
      this.hourTo = 24,
      this.company,
      this.processing,
      this.height,
      this.minTemperature,
      this.maxTemperature,
      this.minHumidity,
      this.maxHumidity,
      this.parshiya,
      this.side});
  bool get hoursRestricted =>
      hourFrom != hourTo && (hourFrom != 0 || hourTo != 24);
  bool acceptsHour(int hour) => hourFrom < hourTo
      ? hour >= hourFrom && hour < hourTo
      : hour >= hourFrom || hour < hourTo;
}

class WritingBucket {
  final String key;
  double lines = 0;
  double workMs = 0;
  double readingMs = 0;
  final Set<String> visits = {};
  final Set<String> unknownVisits = {};
  WritingBucket(this.key);
  int get sittings => visits.length;
  bool get enoughData => sittings >= 3 && workMs >= 30 * 60000;
  double? get linesPerHour => workMs > 0 ? lines * 3600000 / workMs : null;
  double? get penLinesPerHour =>
      workMs > readingMs ? lines * 3600000 / (workMs - readingMs) : null;
}

class WritingAnalysis {
  final List<WritingBucket> buckets;
  final WritingBucket total;
  final int excludedWithoutTime;
  final int excludedUnknownHour;
  const WritingAnalysis(this.buckets, this.total, this.excludedWithoutTime,
      this.excludedUnknownHour);

  static WritingAnalysis build(
      {required Iterable<Project> projects,
      required Iterable<WorkSession> history,
      required WritingFilter filter,
      required WritingGroup group,
      DayStart dayStart = DayStart.midnight}) {
    final owners = {for (final p in projects) p.id: p};
    final buckets = <String, WritingBucket>{};
    final total = WritingBucket('total');
    var untimed = 0;
    final unknownHour = <String>{};
    bool range(double? value, double? min, double? max) =>
        (min == null && max == null) ||
        (value != null &&
            (min == null || value >= min) &&
            (max == null || value <= max));
    bool acceptsDate(DateTime value) {
      final date = DateTime(value.year, value.month, value.day);
      final from = filter.from == null
          ? null
          : DateTime(filter.from!.year, filter.from!.month, filter.from!.day);
      final to = filter.to == null
          ? null
          : DateTime(filter.to!.year, filter.to!.month, filter.to!.day);
      return filter.weekdays.contains(value.weekday % 7 + 1) &&
          (from == null || !date.isBefore(from)) &&
          (to == null || !date.isAfter(to));
    }

    for (final s in history) {
      final p = owners[s.projectId];
      if (p == null ||
          s.isDeleted ||
          s.backlogOnly ||
          (filter.projectId != null && s.projectId != filter.projectId) ||
          (filter.type != null && p.type != filter.type) ||
          (filter.parshiya != null && s.parshiya != filter.parshiya) ||
          (filter.side != null && s.tefillinType != filter.side)) {
        continue;
      }
      final c = WritingConditions.session(s);
      if ((filter.company != null && c.company != filter.company) ||
          (filter.processing != null && c.processing != filter.processing) ||
          (filter.height != null &&
              (filter.height! < 0
                  ? c.heightMm != null
                  : c.heightMm != filter.height)) ||
          !range(
              c.temperatureC, filter.minTemperature, filter.maxTemperature) ||
          !range(c.humidity, filter.minHumidity, filter.maxHumidity)) {
        continue;
      }
      if (!s.timeRecorded || s.duration <= Duration.zero) {
        if (acceptsDate(DateLogic.workingDateOf(s, dayStart))) untimed++;
        continue;
      }
      final lines = ProductionCalculator.comparableLinesInSession(p, s,
          includeInvalid: true);
      var spans = WritingTimeline.of(s);
      final work = s.duration.inMilliseconds;
      final spanWork = spans.fold<int>(0, (n, span) => n + span.workMs);
      if (spanWork > work) spans = WritingTimeline.slice(spans, 0, work);
      if (spanWork < work) {
        final missing = work - spanWork;
        final existingRead =
            spans.where((s) => s.reading).fold<int>(0, (n, s) => n + s.workMs);
        final read =
            (WorkTimeBreakdown.readingOf(s).inMilliseconds - existingRead)
                .clamp(0, missing);
        spans = [
          ...spans,
          if (missing > read) WritingSpan(null, null, missing - read),
          if (read > 0) WritingSpan(null, null, read, reading: true)
        ];
      }
      final pen = spans
          .where((span) => !span.reading)
          .fold<int>(0, (n, span) => n + span.workMs);
      final visit = s.extraFields['writingSittingId'] ??
          s.extraFields['workTimerId'] ??
          s.entryId;
      void add(
          WritingBucket bucket, double amount, double reading, double output) {
        bucket.workMs += amount;
        bucket.readingMs += reading;
        bucket.lines += output;
        if (visit is String && visit.isNotEmpty) {
          bucket.visits.add('${s.projectId}:$visit');
        } else {
          bucket.unknownVisits.add(s.id);
        }
      }

      for (final span in spans) {
        if (span.workMs <= 0) continue;
        final known = span.start != null &&
            span.end != null &&
            span.end!.isAfter(span.start!) &&
            span.end!.difference(span.start!).inDays <= 31;
        if (!known && !acceptsDate(DateLogic.workingDateOf(s, dayStart))) {
          continue;
        }
        if (!known && (filter.hoursRestricted || group == WritingGroup.hour)) {
          unknownHour.add(s.id);
          continue;
        }
        var cursor = span.start;
        var consumed = 0;
        do {
          DateTime? end;
          var ms = span.workMs - consumed;
          if (known) {
            var next = DateTime(
                cursor!.year, cursor.month, cursor.day, cursor.hour + 1);
            if (!next.isAfter(cursor)) {
              next = cursor.add(const Duration(hours: 1));
            }
            end = next.isBefore(span.end!) ? next : span.end;
            // Sunset/nightfall can change the working day inside an hour.
            final rule = s.dayRule;
            if (rule != null && end!.difference(cursor).inMilliseconds > 1) {
              (int, int, int) dayKey(DateTime at) {
                final d = DateLogic.effectiveDate(at, rule);
                return (d.year, d.month, d.day);
              }

              final first = dayKey(cursor);
              if (dayKey(end.subtract(const Duration(microseconds: 1))) !=
                  first) {
                var low = 1, high = end.difference(cursor).inMilliseconds;
                while (low < high) {
                  final middle = (low + high) ~/ 2;
                  if (dayKey(cursor.add(Duration(milliseconds: middle))) ==
                      first) {
                    low = middle + 1;
                  } else {
                    high = middle;
                  }
                }
                end = cursor.add(Duration(milliseconds: low));
              }
            }
            final cumulative = end == span.end
                ? span.workMs
                : (span.workMs *
                        (end!.difference(span.start!).inMicroseconds /
                            span.end!.difference(span.start!).inMicroseconds))
                    .round();
            ms = cumulative - consumed;
          }
          final day = s.dayRule != null && known
              ? DateLogic.effectiveDate(cursor!, s.dayRule!)
              : DateLogic.workingDateOf(s, dayStart);
          final weekday = day.weekday % 7 + 1;
          if (ms > 0 &&
              acceptsDate(day) &&
              (!known || filter.acceptsHour(cursor!.hour))) {
            final key = switch (group) {
              WritingGroup.weekday => '$weekday',
              WritingGroup.hour => '${cursor!.hour}',
              WritingGroup.type => p.type.name,
              WritingGroup.company => c.company.isEmpty ? '?' : c.company,
              WritingGroup.processing =>
                c.processing.isEmpty ? '?' : c.processing,
              WritingGroup.height => c.heightMm == null ? '?' : '${c.heightMm}',
              WritingGroup.climate => c.temperatureC == null ||
                      c.humidity == null
                  ? '?'
                  : '${(c.temperatureC! / 2).floor() * 2}:${(c.humidity! / 10).floor() * 10}',
            };
            final output = span.reading || pen <= 0 ? 0.0 : lines * ms / pen;
            add(buckets.putIfAbsent(key, () => WritingBucket(key)),
                ms.toDouble(), span.reading ? ms.toDouble() : 0, output);
            add(total, ms.toDouble(), span.reading ? ms.toDouble() : 0, output);
          }
          consumed += ms;
          cursor = end;
        } while (
            known && consumed < span.workMs && cursor!.isBefore(span.end!));
      }
    }
    final rows = buckets.values.toList()
      ..sort((a, b) => group == WritingGroup.hour ||
              group == WritingGroup.weekday ||
              group == WritingGroup.height
          ? (double.tryParse(a.key) ?? double.infinity)
              .compareTo(double.tryParse(b.key) ?? double.infinity)
          : a.key.compareTo(b.key));
    return WritingAnalysis(rows, total, untimed, unknownHour.length);
  }
}
