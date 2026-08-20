import '../models.dart';
import 'date_logic.dart';
import 'production_calculator.dart';

/// Folds smart-mode checkpoints into the records of the sitting under way.
///
/// A checkpoint is written whenever the sofer presses "סיימתי שורה". Keeping
/// every checkpoint as a separate [WorkSession] would make a page of writing
/// look like forty-two sittings and would grow the history by thousands of
/// records. This keeps the durability of a save after every line while the
/// stored shape remains one record per physical page, mezuza or parshiya.
class SmartLiveRecording {
  const SmartLiveRecording._();

  static List<WorkSession> merge(
    Iterable<WorkSession> history,
    Iterable<WorkSession> checkpoints,
  ) {
    final merged = history.toList();
    for (final checkpoint in checkpoints) {
      final index = merged.indexWhere(
        (existing) =>
            !existing.isDeleted &&
            existing.entryId != null &&
            existing.entryId == checkpoint.entryId &&
            _canExtend(existing, checkpoint),
      );
      if (index < 0) {
        merged.add(checkpoint);
      } else {
        merged[index] = _extend(merged[index], checkpoint);
      }
    }
    return merged;
  }

  static bool _canExtend(WorkSession existing, WorkSession next) {
    if (existing.projectId != next.projectId) return false;
    if (!_sameWorkingDay(existing, next)) return false;

    if (existing.mezuzaIndex != null || next.mezuzaIndex != null) {
      return existing.mezuzaIndex != null &&
          existing.mezuzaIndex == next.mezuzaIndex;
    }

    if (existing.tefillinType != null || next.tefillinType != null) {
      return existing.tefillinType == next.tefillinType &&
          existing.parshiya == next.parshiya &&
          existing.pairIndex == next.pairIndex &&
          existing.endLine + 1 == next.startLine;
    }

    return existing.amount == next.amount &&
        existing.endLine + 1 == next.startLine;
  }

  static bool _sameWorkingDay(WorkSession a, WorkSession b) {
    DateTime filedDate(WorkSession session) {
      final rule = session.dayRule;
      final date = rule == null
          ? session.workingDateAtEntry ?? session.startTime
          : DateLogic.effectiveDate(session.startTime, rule);
      return DateTime(date.year, date.month, date.day);
    }

    final first = filedDate(a);
    final second = filedDate(b);
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  static WorkSession _extend(WorkSession existing, WorkSession next) {
    final combinedDuration =
        (existing.timeRecorded ? existing.duration : Duration.zero) +
            (next.timeRecorded ? next.duration : Duration.zero);
    final end = next.endTime.isAfter(existing.endTime)
        ? next.endTime
        : existing.endTime;
    final start = end.subtract(combinedDuration);

    if (existing.mezuzaIndex != null) {
      final oldLines = existing.endLine > 0
          ? existing.endLine
          : ProductionCalculator.linesPerMezuza;
      final newLines =
          next.endLine > 0 ? next.endLine : ProductionCalculator.linesPerMezuza;
      final lines =
          (oldLines + newLines).clamp(0, ProductionCalculator.linesPerMezuza);
      final complete = lines >= ProductionCalculator.linesPerMezuza;
      return existing.copyWith(
        startTime: start,
        endTime: end,
        endLine: complete ? 0 : lines,
        description: complete
            ? 'מזוזה ${existing.mezuzaIndex}'
            : 'מזוזה ${existing.mezuzaIndex} ($lines שורות)',
        timeRecorded: existing.timeRecorded || next.timeRecorded,
      );
    }

    return existing.copyWith(
      startTime: start,
      endTime: end,
      amount: existing.amount > next.amount ? existing.amount : next.amount,
      startLine: existing.startLine,
      endLine: next.endLine,
      // The latest description knows when a parshiya has just become whole;
      // for a sefer both descriptions name the same page.
      description: next.description,
      timeRecorded: existing.timeRecorded || next.timeRecorded,
    );
  }
}
