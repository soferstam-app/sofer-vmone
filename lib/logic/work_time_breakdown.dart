import 'writing_timeline.dart';
import '../format.dart';
import '../models.dart';
import 'json_compat.dart';

/// Optional metadata; duration remains total professional work for all readers.
class WorkTimeBreakdown {
  static const readingKey = 'readingCorrectionMs';
  static const breakKey = 'sittingBreakMs';
  final Duration work;
  final Duration reading;
  final Duration breaks;
  const WorkTimeBreakdown(this.work, this.reading, this.breaks);

  static int _ms(WorkSession s, String key) =>
      (JsonCompat.intOrNull(s.extraFields[key]) ?? 0).clamp(0, 1 << 53);

  static Duration readingOf(WorkSession s) => Duration(
      milliseconds: _ms(s, readingKey)
          .clamp(0, s.duration.inMilliseconds.clamp(0, 1 << 53)));

  static WorkTimeBreakdown of(Iterable<WorkSession> sessions) {
    var work = Duration.zero;
    var reading = Duration.zero;
    var breaks = Duration.zero;
    for (final s in sessions.where((s) => !s.isDeleted && s.timeRecorded)) {
      if (s.duration > Duration.zero) work += s.duration;
      reading += readingOf(s);
      breaks += Duration(milliseconds: _ms(s, breakKey));
    }
    return WorkTimeBreakdown(work, reading, breaks);
  }

  bool get hasDetails => reading > Duration.zero || breaks > Duration.zero;
  String label({bool english = false}) => english
      ? 'Writing: ${formatClock(work - reading)} · Reading / correction: ${formatClock(reading)} · Breaks: ${formatClock(breaks)}'
      : 'כתיבה: ${formatClock(work - reading)} · קריאה / תיקון: ${formatClock(reading)} · הפסקות: ${formatClock(breaks)}';

  /// Splits metadata in proportion to the existing work slices, preserving
  /// the exact remainder. Does not change dates, production or total work.
  static List<WorkSession> allocate(List<WorkSession> sessions,
      {required Duration reading,
      Duration breaks = Duration.zero,
      String? timerId,
      List<WritingSpan>? intervals}) {
    if (sessions.isEmpty) return sessions;
    final total = sessions.fold<int>(
        0, (n, s) => n + s.duration.inMilliseconds.clamp(0, 1 << 53));
    final readingMs = reading.inMilliseconds.clamp(0, total);
    final breakMs = breaks.inMilliseconds.clamp(0, 1 << 53);
    var usedReading = 0;
    var usedBreak = 0;
    var cumulative = 0;
    final result = <WorkSession>[];
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      cumulative += s.duration.inMilliseconds.clamp(0, 1 << 53);
      final last = i == sessions.length - 1;
      final nextReading =
          last ? readingMs : (total == 0 ? 0 : readingMs * cumulative ~/ total);
      final nextBreak =
          last ? breakMs : (total == 0 ? 0 : breakMs * cumulative ~/ total);
      result.add(s.copyWith(extraFields: {
        ...s.extraFields,
        if (timerId != null) 'workTimerId': timerId,
        readingKey: nextReading - usedReading,
        breakKey: nextBreak - usedBreak,
      }));
      usedReading = nextReading;
      usedBreak = nextBreak;
    }
    return intervals == null
        ? result
        : WritingTimeline.allocate(result, intervals);
  }

  static Map<String, dynamic> mergedFields(WorkSession a, WorkSession b) => {
        ...a.extraFields,
        ...b.extraFields,
        if (a.extraFields.containsKey(WritingTimeline.key) ||
            b.extraFields.containsKey(WritingTimeline.key))
          WritingTimeline.key: [
            for (final span in [
              ...WritingTimeline.of(a),
              ...WritingTimeline.of(b)
            ])
              span.toJson()
          ],
        readingKey: readingOf(a).inMilliseconds + readingOf(b).inMilliseconds,
        breakKey: _ms(a, breakKey) + _ms(b, breakKey),
      };
}
