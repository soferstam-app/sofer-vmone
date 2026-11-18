import '../models.dart';

/// Real wall-clock intervals paired with measured working milliseconds.
/// Null timestamps retain work whose hour is unknown without inventing one.
class WritingSpan {
  final DateTime? start;
  final DateTime? end;
  final int workMs;
  final bool reading;
  const WritingSpan(this.start, this.end, this.workMs, {this.reading = false});
  Map<String, dynamic> toJson() => {
        if (start != null) 'start': start!.toIso8601String(),
        if (end != null) 'end': end!.toIso8601String(),
        'workMs': workMs,
        'reading': reading,
      };
  static List<WritingSpan> decode(Object? raw) {
    if (raw is! List) return [];
    return [
      for (final value in raw.take(10000))
        if (value is Map &&
            value['workMs'] is num &&
            (value['workMs'] as num).isFinite &&
            (value['workMs'] as num) > 0)
          WritingSpan(
              DateTime.tryParse('${value['start']}')?.toLocal(),
              DateTime.tryParse('${value['end']}')?.toLocal(),
              (value['workMs'] as num).toInt().clamp(0, 1 << 53),
              reading: value['reading'] == true)
    ];
  }

  WritingSpan portion(int from, int to) {
    DateTime? at(
            int amount) =>
        start != null && end != null && end!.isAfter(start!)
            ? start!.add(Duration(
                microseconds:
                    (end!.difference(start!).inMicroseconds * (amount / workMs))
                        .round()))
            : null;
    return WritingSpan(at(from), at(to), to - from, reading: reading);
  }
}

class WritingTimeline {
  static const key = 'workIntervals';
  static List<WritingSpan> slice(
      List<WritingSpan> spans, int from, int length) {
    final result = <WritingSpan>[];
    var cursor = 0;
    final until = from + length;
    for (final span in spans) {
      final left = from > cursor ? from - cursor : 0;
      final right = until < cursor + span.workMs ? until - cursor : span.workMs;
      if (right > left && right > 0 && left < span.workMs) {
        result.add(span.portion(left, right));
      }
      cursor += span.workMs;
      if (cursor >= until) break;
    }
    return result;
  }

  static List<WorkSession> allocate(
      List<WorkSession> records, List<WritingSpan> spans) {
    var cursor = 0;
    final result = <WorkSession>[];
    for (final s in records) {
      final length = s.duration.inMilliseconds.clamp(0, 1 << 53);
      final part = slice(spans, cursor, length);
      final measured = part.fold<int>(0, (n, span) => n + span.workMs);
      if (measured < length) {
        final missing = length - measured;
        final assignedReading = s.extraFields['readingCorrectionMs'];
        final oldReading = assignedReading is num && assignedReading.isFinite
            ? assignedReading.toInt().clamp(0, length)
            : 0;
        final read = (oldReading -
                part
                    .where((span) => span.reading)
                    .fold<int>(0, (n, span) => n + span.workMs))
            .clamp(0, missing);
        if (missing > read) part.add(WritingSpan(null, null, missing - read));
        if (read > 0) part.add(WritingSpan(null, null, read, reading: true));
      }
      cursor += length;
      result.add(s.copyWith(extraFields: {
        ...s.extraFields,
        key: [for (final span in part) span.toJson()],
        'readingCorrectionMs': part
            .where((span) => span.reading)
            .fold<int>(0, (n, span) => n + span.workMs),
      }));
    }
    return result;
  }

  static List<WritingSpan> of(WorkSession s) {
    final work = s.duration.inMilliseconds.clamp(0, 1 << 53);
    final raw = s.extraFields['readingCorrectionMs'];
    final reading = raw is num && raw.isFinite ? raw.toInt().clamp(0, work) : 0;
    final unknown = [
      if (work > reading) WritingSpan(null, null, work - reading),
      if (reading > 0) WritingSpan(null, null, reading, reading: true)
    ];
    if (!s.timeOfDayKnown) return unknown;
    if (s.extraFields.containsKey(key)) {
      final decoded = WritingSpan.decode(s.extraFields[key]);
      return decoded.isEmpty ? unknown : decoded;
    }
    if (s.isManual && reading == 0 && work > 0) {
      return [WritingSpan(s.startTime.toLocal(), s.endTime.toLocal(), work)];
    }
    return unknown;
  }

  /// Changing compressed clock timestamps cannot relocate previously measured
  /// pauses or reading intervals. A manual clock declaration can be restated.
  static Map<String, dynamic> restated(
      WorkSession s, DateTime start, DateTime end) {
    if (start == s.startTime && end == s.endTime) return s.extraFields;
    return {
      ...s.extraFields,
      key: s.isManual && (s.extraFields['readingCorrectionMs'] ?? 0) == 0
          ? [
              WritingSpan(start, end, end.difference(start).inMilliseconds)
                  .toJson()
            ]
          : <dynamic>[]
    };
  }
}
