import '../models.dart';
import 'production_calculator.dart';

enum MezuzaSlotState { empty, partial, done }

/// One identifiable mezuza in a commission.
class MezuzaSlot {
  final int index;
  final MezuzaSlotState state;
  final int linesWritten;
  final DateTime? startedOn;

  const MezuzaSlot({
    required this.index,
    required this.state,
    required this.linesWritten,
    this.startedOn,
  });

  int get resumeLine => state == MezuzaSlotState.partial
      ? (linesWritten + 1).clamp(1, ProductionCalculator.linesPerMezuza)
      : 1;
}

/// Reconstructs individual mezuzot from counted and indexed records.
///
/// Old records carry only a quantity and are laid down in writing order. New
/// smart-mode records also carry [WorkSession.mezuzaIndex], which is what lets
/// a writer leave mezuza 8 part-written, move to 9, and later return to 8.
class MezuzaState {
  const MezuzaState._();

  static List<MezuzaSlot> slots(
    Project project,
    Iterable<WorkSession> history,
  ) {
    final sessions = history
        .where((s) => s.projectId == project.id && !s.isDeleted)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final written = <int, int>{};
    final began = <int, DateTime>{};
    var highest = 0;
    var nextLegacy = 1;

    void put(int index, int lines, DateTime when) {
      if (index < 1 || lines <= 0) return;
      final sum = (written[index] ?? 0) + lines;
      written[index] = sum.clamp(0, ProductionCalculator.linesPerMezuza);
      began.putIfAbsent(index, () => when);
      if (index > highest) highest = index;
    }

    int takeNextLegacy() {
      // A counted record has no identity of its own. Place it in the first
      // untouched slot, including when an indexed smart-mode record was saved
      // before it. Simply incrementing a second counter laid both records on
      // mezuza 1 and made one of them disappear from the board.
      while ((written[nextLegacy] ?? 0) > 0) {
        nextLegacy++;
      }
      return nextLegacy++;
    }

    for (final s in sessions) {
      final count = s.amount < 1 ? 1 : s.amount;
      final day = s.workingDateAtEntry ?? s.startTime;
      final indexed = s.mezuzaIndex;

      if (indexed != null && indexed >= 1) {
        for (var i = 0; i < count; i++) {
          final isLast = i == count - 1;
          final lines = isLast && s.endLine > 0
              ? s.endLine
              : ProductionCalculator.linesPerMezuza;
          put(indexed + i, lines, day);
        }
        continue;
      }

      // Legacy counted shape: `amount: 3, endLine: 10` means two whole
      // mezuzot and ten lines of the third.
      final whole = s.endLine > 0 ? count - 1 : count;
      for (var i = 0; i < whole; i++) {
        put(takeNextLegacy(), ProductionCalculator.linesPerMezuza, day);
      }
      if (s.endLine > 0) {
        put(takeNextLegacy(), s.endLine, day);
      }
    }

    final ordered = project.targetUnits ?? 0;
    final count = ordered > highest ? ordered : highest + 1;
    return [
      for (var index = 1; index <= count; index++)
        MezuzaSlot(
          index: index,
          linesWritten: written[index] ?? 0,
          state: switch (written[index] ?? 0) {
            >= ProductionCalculator.linesPerMezuza => MezuzaSlotState.done,
            > 0 => MezuzaSlotState.partial,
            _ => MezuzaSlotState.empty,
          },
          startedOn: began[index],
        ),
    ];
  }

  /// The place to offer after rebuilding the commission from its records.
  ///
  /// The highest mezuza that was actually touched determines the forward
  /// workflow. Earlier partial ones remain available through the "stopped"
  /// picker and must not pull the main position backwards.
  static ({int page, int line}) nextWritingPosition(
    Project project,
    Iterable<WorkSession> history,
  ) {
    final written = slots(project, history)
        .where((slot) => slot.state != MezuzaSlotState.empty)
        .toList();
    if (written.isEmpty) return (page: 1, line: 1);

    final last = written.reduce((a, b) => a.index > b.index ? a : b);
    return last.state == MezuzaSlotState.done
        ? (page: last.index + 1, line: 1)
        : (page: last.index, line: last.resumeLine);
  }
}

/// The short position list shown while the clock is running.
class MezuzaPicks {
  final List<MezuzaSlot> stopped;
  final List<MezuzaSlot> nextUp;

  const MezuzaPicks({required this.stopped, required this.nextUp});

  static MezuzaPicks from(
    Iterable<MezuzaSlot> slots, {
    required int current,
    int nextCount = 3,
  }) {
    final ordered = slots.where((s) => s.index != current).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return MezuzaPicks(
      stopped: [
        for (final s in ordered)
          if (s.state == MezuzaSlotState.partial) s,
      ],
      nextUp: [
        for (final s in ordered)
          if (s.state == MezuzaSlotState.empty) s,
      ].take(nextCount).toList(),
    );
  }
}
