import '../hebrew_utils.dart';
import '../models.dart';
import 'id_generator.dart';
import 'production_calculator.dart';
import 'session_logic.dart';
import 'tefillin_state.dart';
import 'tefillin_units.dart';

/// A correction together with enough information to undo it safely.
class WorkCorrectionResult {
  final List<WorkSession> history;
  final Map<String, WorkSession> originals;
  final Set<String> createdIds;

  const WorkCorrectionResult({
    required this.history,
    this.originals = const {},
    this.createdIds = const {},
  });

  Set<String> get changedIds => originals.keys.toSet();
  bool get changed => changedIds.isNotEmpty || createdIds.isNotEmpty;

  /// Restores changed originals and removes fragments created by the edit.
  List<WorkSession> undo() => [
        for (final session in history)
          if (createdIds.contains(session.id))
            session.copyWith(isDeleted: true)
          else if (originals[session.id] case final original?)
            // Undo is a new edit. An old timestamp would lose against the
            // correction at the next backup merge; undoing deletion also
            // needs an explicit restore register to beat its tombstone.
            original.copyWith(
                isDeleted:
                    session.isDeleted && !original.isDeleted ? false : null)
          else
            session,
      ];
}

/// Unit-aware corrections made from a project rather than from a raw record.
class WorkCorrection {
  const WorkCorrection._();

  static WorkCorrectionResult markInvalid(
    Iterable<WorkSession> history,
    Set<String> ids, {
    bool invalid = true,
  }) {
    final originals = <String, WorkSession>{};
    final next = <WorkSession>[];
    for (final session in history) {
      if (ids.contains(session.id) &&
          !session.isDeleted &&
          session.isInvalid != invalid) {
        originals[session.id] = session;
        next.add(session.copyWith(isInvalid: invalid));
      } else {
        next.add(session);
      }
    }
    return WorkCorrectionResult(history: next, originals: originals);
  }

  static WorkCorrectionResult delete(
      Iterable<WorkSession> history, Set<String> ids) {
    final originals = <String, WorkSession>{};
    final next = <WorkSession>[];
    for (final session in history) {
      if (ids.contains(session.id) && !session.isDeleted) {
        originals[session.id] = session;
        next.add(session.copyWith(isDeleted: true));
      } else {
        next.add(session);
      }
    }
    return WorkCorrectionResult(history: next, originals: originals);
  }

  /// Marks one physical Mezuzah invalid, even when an older record bundled
  /// several Mezuzot together without identifiers.
  static WorkCorrectionResult markMezuzaInvalid({
    required Iterable<WorkSession> history,
    required String projectId,
    required int index,
  }) =>
      _correctMezuza(
        history: history,
        projectId: projectId,
        index: index,
        delete: false,
      );

  /// Deletes one physical Mezuzah while retaining the other Mezuzot that may
  /// share its legacy counted record.
  static WorkCorrectionResult deleteMezuza({
    required Iterable<WorkSession> history,
    required String projectId,
    required int index,
  }) =>
      _correctMezuza(
        history: history,
        projectId: projectId,
        index: index,
        delete: true,
      );

  /// Marks one physical Tefillin Parashah invalid. Legacy records that bundle
  /// a whole head, hand or pair are first divided into named physical records.
  static WorkCorrectionResult markTefillinInvalid({
    required Iterable<WorkSession> history,
    required Project project,
    required int pair,
    required TefillinSide side,
    required int parshiya,
  }) =>
      _correctTefillin(
        history: history,
        project: project,
        pair: pair,
        side: side,
        parshiya: parshiya,
        deleteFrom: false,
      );

  /// Deletes one physical Parashah and all later Parashiyot in the same set.
  /// Records outside that one head or hand remain live, even when all of them
  /// originally shared one legacy record.
  static WorkCorrectionResult deleteTefillinFrom({
    required Iterable<WorkSession> history,
    required Project project,
    required int pair,
    required TefillinSide side,
    required int parshiya,
  }) =>
      _correctTefillin(
        history: history,
        project: project,
        pair: pair,
        side: side,
        parshiya: parshiya,
        deleteFrom: true,
      );

  static WorkCorrectionResult _correctTefillin({
    required Iterable<WorkSession> history,
    required Project project,
    required int pair,
    required TefillinSide side,
    required int parshiya,
    required bool deleteFrom,
  }) {
    final source = history.toList();
    final placements = TefillinState.placements(project, source);
    final sideName = side == TefillinSide.head ? 'head' : 'hand';
    final originals = <String, WorkSession>{};
    final created = <String>{};
    final next = <WorkSession>[];

    bool isSelected(TefillinPlacement piece) =>
        piece.pair == pair &&
        piece.side == side &&
        (deleteFrom ? piece.parshiya >= parshiya : piece.parshiya == parshiya);

    bool isDirectlySelected(WorkSession session) =>
        session.pairIndex == pair &&
        session.tefillinType == sideName &&
        session.parshiya != null &&
        (deleteFrom
            ? session.parshiya! >= parshiya
            : session.parshiya == parshiya);

    for (final session in source) {
      // Split corrections produce fully identified records. This direct path
      // also sees invalid records, which are deliberately absent from the
      // production layout but still have to be removable afterwards.
      if (!session.isDeleted && isDirectlySelected(session)) {
        originals[session.id] = session;
        next.add(session.copyWith(
          isDeleted: deleteFrom ? true : null,
          isInvalid: deleteFrom ? null : true,
        ));
        continue;
      }

      final pieces = placements[session.id];
      if (session.isDeleted || pieces == null || !pieces.any(isSelected)) {
        next.add(session);
        continue;
      }

      // A legacy session does not carry enough identity to be edited again.
      // Normalize all of its pieces now, even if this particular session only
      // happened to land in one slot.
      originals[session.id] = session;
      final slices = SessionLogic.splitByWeight(
        start: session.startTime,
        end: session.endTime,
        weights: [for (final piece in pieces) _tefillinWeight(piece)],
      );
      final fragments = <WorkSession>[];
      final sourceCreated = <String>[];
      for (var i = 0; i < pieces.length; i++) {
        final piece = pieces[i];
        final selected = isSelected(piece);
        final fragmentSide = piece.side == TefillinSide.head ? 'head' : 'hand';
        final fullLines = TefillinUnits.linesIn(piece.side);
        final id = IdGenerator.generate(
            suffix: 'tefillin-${piece.pair}-$fragmentSide-${piece.parshiya}');
        created.add(id);
        sourceCreated.add(id);
        fragments.add(WorkSession(
          id: id,
          projectId: session.projectId,
          startTime: slices[i].start,
          endTime: slices[i].end,
          amount: 1,
          startLine: 0,
          endLine: piece.lines >= fullLines ? 0 : piece.lines,
          tefillinType: fragmentSide,
          parshiya: piece.parshiya,
          pairIndex: piece.pair,
          description: TefillinUnits.names[piece.parshiya - 1],
          isManual: session.isManual,
          backlogOnly: session.backlogOnly,
          isInvalid: !deleteFrom && selected,
          timeRecorded: session.timeRecorded,
          timeOfDayKnown: session.timeOfDayKnown,
          entryId: session.entryId,
          dayRule: session.dayRule,
          workingDateAtEntry: session.workingDateAtEntry,
          deletedAt: deleteFrom && selected ? DateTime.now() : null,
          extraFields: {
            ...session.extraFields,
            'appCorrectionSourceId': session.id,
          },
        ));
      }
      next.add(session.copyWith(
        isDeleted: true,
        extraFields: {
          ...session.extraFields,
          'appCorrectionKind': 'tefillinParashah',
          'appCorrectionCreatedIds': sourceCreated,
        },
      ));
      next.addAll(fragments);
    }

    return WorkCorrectionResult(
      history: next,
      originals: originals,
      createdIds: created,
    );
  }

  /// An integer equivalent of the fraction of Sefer-Torah text represented
  /// by a partly written Parashah. The factors 7 and 4 give head and hand a
  /// common denominator, so unequal parts receive honest shares of the time.
  static int _tefillinWeight(TefillinPlacement piece) =>
      TefillinUnits.seferLines[piece.parshiya - 1] *
      piece.lines *
      (piece.side == TefillinSide.head ? 7 : 4);

  static WorkCorrectionResult _correctMezuza({
    required Iterable<WorkSession> history,
    required String projectId,
    required int index,
    required bool delete,
  }) {
    final source = history.toList();
    final ordered = source
        .where((session) =>
            session.projectId == projectId &&
            !session.isDeleted &&
            !session.isInvalid)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final placements = <String, List<(int, int)>>{};
    final written = <int, int>{};
    var nextLegacy = 1;

    int takeNextLegacy() {
      while ((written[nextLegacy] ?? 0) > 0) {
        nextLegacy++;
      }
      return nextLegacy++;
    }

    void place(WorkSession session, int slot, int lines) {
      if (slot < 1 || lines <= 0) return;
      placements.putIfAbsent(session.id, () => []).add((slot, lines));
      written[slot] = ((written[slot] ?? 0) + lines)
          .clamp(0, ProductionCalculator.linesPerMezuza);
    }

    for (final session in ordered) {
      final count = session.amount < 1 ? 1 : session.amount;
      final identified = session.mezuzaIndex;
      if (identified != null && identified >= 1) {
        for (var i = 0; i < count; i++) {
          final lines = i == count - 1 && session.endLine > 0
              ? session.endLine
              : ProductionCalculator.linesPerMezuza;
          place(session, identified + i, lines);
        }
        continue;
      }

      final whole = session.endLine > 0 ? count - 1 : count;
      for (var i = 0; i < whole; i++) {
        place(session, takeNextLegacy(), ProductionCalculator.linesPerMezuza);
      }
      if (session.endLine > 0) {
        place(session, takeNextLegacy(), session.endLine);
      }
    }

    final next = <WorkSession>[];
    final originals = <String, WorkSession>{};
    final created = <String>{};
    for (final session in source) {
      final pieces = placements[session.id];
      if (pieces == null || !pieces.any((piece) => piece.$1 == index)) {
        next.add(session);
        continue;
      }

      originals[session.id] = session;
      if (pieces.length == 1) {
        next.add(session.copyWith(
          isDeleted: delete ? true : null,
          isInvalid: delete ? null : true,
        ));
        continue;
      }

      final slices = SessionLogic.splitByWeight(
        start: session.startTime,
        end: session.endTime,
        weights: [for (final piece in pieces) piece.$2],
      );
      final fragments = <WorkSession>[];
      final sourceCreated = <String>[];
      for (var i = 0; i < pieces.length; i++) {
        final piece = pieces[i];
        final id = IdGenerator.generate(suffix: 'mezuza-${piece.$1}');
        created.add(id);
        sourceCreated.add(id);
        fragments.add(WorkSession(
          id: id,
          projectId: session.projectId,
          startTime: slices[i].start,
          endTime: slices[i].end,
          amount: 1,
          startLine: 0,
          endLine: piece.$2,
          mezuzaIndex: piece.$1,
          description: piece.$2 >= ProductionCalculator.linesPerMezuza
              ? 'מזוזה ${piece.$1}'
              : 'מזוזה ${piece.$1} (${piece.$2} שורות)',
          isManual: session.isManual,
          backlogOnly: session.backlogOnly,
          isInvalid: !delete && piece.$1 == index,
          timeRecorded: session.timeRecorded,
          timeOfDayKnown: session.timeOfDayKnown,
          entryId: session.entryId,
          dayRule: session.dayRule,
          workingDateAtEntry: session.workingDateAtEntry,
          deletedAt: delete && piece.$1 == index ? DateTime.now() : null,
          extraFields: {
            ...session.extraFields,
            'appCorrectionSourceId': session.id,
          },
        ));
      }
      next.add(session.copyWith(
        isDeleted: true,
        extraFields: {
          ...session.extraFields,
          'appCorrectionKind': 'mezuzaUnit',
          'appCorrectionCreatedIds': sourceCreated,
        },
      ));
      next.addAll(fragments);
    }
    return WorkCorrectionResult(
      history: next,
      originals: originals,
      createdIds: created,
    );
  }

  /// Removes selected lines from a Sefer page.
  ///
  /// A record may cover a range, so removing a middle line creates two live
  /// fragments and tombstones the original. The measured duration is divided
  /// between the remaining fragments and still sums to the original duration.
  static WorkCorrectionResult removeSeferLines({
    required Iterable<WorkSession> history,
    required String projectId,
    required int page,
    required Set<int> lines,
  }) {
    if (lines.isEmpty) {
      return WorkCorrectionResult(history: history.toList());
    }

    final next = <WorkSession>[];
    final originals = <String, WorkSession>{};
    final created = <String>{};

    for (final session in history) {
      if (session.isDeleted ||
          session.isInvalid ||
          session.projectId != projectId ||
          session.amount != page ||
          session.startLine <= 0 ||
          session.endLine < session.startLine) {
        next.add(session);
        continue;
      }

      final covered = {
        for (var line = session.startLine; line <= session.endLine; line++)
          line,
      };
      if (covered.intersection(lines).isEmpty) {
        next.add(session);
        continue;
      }

      final remaining = covered.difference(lines).toList()..sort();
      final ranges = _ranges(remaining);
      originals[session.id] = session;
      if (ranges.isEmpty) {
        next.add(session.copyWith(isDeleted: true));
        continue;
      }

      final slices = SessionLogic.splitByWeight(
        start: session.startTime,
        end: session.endTime,
        weights: [for (final range in ranges) range.$2 - range.$1 + 1],
      );
      final fragments = <WorkSession>[];
      final sourceCreated = <String>[];
      for (var i = 0; i < ranges.length; i++) {
        final range = ranges[i];
        final id = IdGenerator.generate(suffix: 'corrected-${i + 1}');
        created.add(id);
        sourceCreated.add(id);
        fragments.add(WorkSession(
          id: id,
          projectId: session.projectId,
          startTime: slices[i].start,
          endTime: slices[i].end,
          amount: session.amount,
          startLine: range.$1,
          endLine: range.$2,
          description: 'עמוד ${formatHebrewNumber(page)} '
              '(${range.$1}-${range.$2})',
          isManual: session.isManual,
          backlogOnly: session.backlogOnly,
          isInvalid: session.isInvalid,
          timeRecorded: session.timeRecorded,
          timeOfDayKnown: session.timeOfDayKnown,
          linesPerPageAtEntry: session.linesPerPageAtEntry,
          entryId: session.entryId,
          dayRule: session.dayRule,
          workingDateAtEntry: session.workingDateAtEntry,
          extraFields: {
            ...session.extraFields,
            'appCorrectionSourceId': session.id,
          },
        ));
      }
      next.add(session.copyWith(
        isDeleted: true,
        extraFields: {
          ...session.extraFields,
          'appCorrectionKind': 'seferLines',
          'appCorrectionCreatedIds': sourceCreated,
        },
      ));
      next.addAll(fragments);
    }

    return WorkCorrectionResult(
      history: next,
      originals: originals,
      createdIds: created,
    );
  }

  static List<(int, int)> _ranges(List<int> sorted) {
    if (sorted.isEmpty) return const [];
    final out = <(int, int)>[];
    var from = sorted.first;
    var to = from;
    for (final line in sorted.skip(1)) {
      if (line == to + 1) {
        to = line;
      } else {
        out.add((from, to));
        from = to = line;
      }
    }
    out.add((from, to));
    return out;
  }
}
