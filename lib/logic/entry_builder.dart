import '../hebrew_utils.dart';
import '../models.dart';
import 'id_generator.dart';
import 'production_calculator.dart';
import 'session_logic.dart';
import 'tefillin_state.dart';
import 'tefillin_units.dart';

/// What the entry form was told, in the shape the builder needs it.
///
/// The text arrives exactly as it was typed. Parsing belongs here and not in
/// the form: a page reads as "יא" or as "11" depending on the writer, and which
/// of the two arrived is not something a screen should have an opinion about.
class EntryInput {
  final Project project;

  /// The stretch of time the entry covers. Equal start and end mean no working
  /// time was given, which [timeRecorded] states outright.
  final DateTime start;
  final DateTime end;

  /// The day the writer said this work was done on, when he said it.
  ///
  /// Null for anything the app timed itself. The difference decides which day
  /// the record is filed under, and it is a real one: the day-boundary rule
  /// exists to interpret a *measurement* — a moment the app captured and has to
  /// decide the meaning of. A date a person typed is not a measurement, it is
  /// an assertion, and re-deriving it from the hour beside it told writers who
  /// entered Tuesday 00:30 that they had worked on Monday.
  final DateTime? statedDate;

  final bool isManual;
  final bool backlogOnly;
  final bool timeRecorded;

  /// Whether the hour on [start] is a fact about when the writing happened, or
  /// only where a length had to be anchored. See [WorkSession.timeOfDayKnown].
  final bool timeOfDayKnown;

  final String pageFrom;
  final String pageTo;
  final String lineFrom;
  final String lineTo;
  final String amount;

  /// "Up to line", for a mezuza or a tefillin parshiya left part-written.
  final String partialLine;

  /// Tefillin only: `set`, `head`, `hand` or `parshiya`.
  final String tefillinMode;

  /// Tefillin parshiya mode only: `head` or `hand`.
  final String tefillinPart;

  /// Tefillin parshiya mode only, 1–4.
  final int tefillinParshiya;

  /// Which pair the parshiya belongs to, as typed. Blank means the writer did
  /// not say, and the work falls into the first free slot in writing order.
  final String tefillinPair;

  const EntryInput({
    required this.project,
    required this.start,
    required this.end,
    this.statedDate,
    required this.isManual,
    this.backlogOnly = false,
    this.timeRecorded = true,
    this.timeOfDayKnown = true,
    this.pageFrom = '',
    this.pageTo = '',
    this.lineFrom = '',
    this.lineTo = '',
    this.amount = '',
    this.partialLine = '',
    this.tefillinMode = 'set',
    this.tefillinPart = 'head',
    this.tefillinParshiya = 1,
    this.tefillinPair = '',
  });
}

/// The result of trying to turn an entry into records.
sealed class EntryOutcome {
  const EntryOutcome();
}

/// The entry cannot be recorded, with the reason written out ready to show.
final class EntryRejected extends EntryOutcome {
  final String message;
  const EntryRejected(this.message);
}

/// The records the entry produces.
///
/// Nothing has been saved: the caller decides that, because only it can ask the
/// writer about [overlapsRecordedWork] first.
final class EntryBuilt extends EntryOutcome {
  final List<WorkSession> sessions;

  /// Some of this work is already recorded against the same pages. Not an
  /// error — a sofer correcting a page writes over lines he has written before
  /// — so it is a question for the writer rather than a refusal.
  final bool overlapsRecordedWork;

  /// Where the writer has reached, for the stored position.
  final int reachedPage;
  final int reachedLine;

  const EntryBuilt({
    required this.sessions,
    required this.overlapsRecordedWork,
    required this.reachedPage,
    required this.reachedLine,
  });
}

/// Turns what was typed into the records it means.
///
/// This used to be three hundred lines inside the home screen, holding the
/// parsing, the validation, the overlap check, the record building and the
/// saving all at once — which is to say that the part of the app most worth
/// being sure about was the part that could not be tested at all. It is pure
/// now: text and a project in, records or a reason out, and not a single
/// widget or stored file in between.
class EntryBuilder {
  const EntryBuilder._();

  /// Most pages one entry may cover. A sefer is 245; nothing real reaches this.
  static const int _maxPagesPerEntry = 500;

  /// Reads a page written either as a Hebrew numeral or as digits.
  ///
  /// Returns 0 for anything unreadable, which every caller treats as "not
  /// given" — the same meaning the form has always given an empty field.
  static int _page(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    return int.tryParse(trimmed) ?? parseHebrewPageToNumber(trimmed);
  }

  static EntryOutcome build({
    required EntryInput input,
    required Iterable<WorkSession> history,
  }) {
    // One mark for the whole entry, settled before anything is built, so that
    // every record it produces carries the same one — including an entry that
    // turns out to produce a single record.
    final entryId = IdGenerator.generate();
    return switch (input.project.type) {
      ProjectType.sefer => _sefer(input, history, entryId),
      ProjectType.mezuza => _counted(input, entryId),
      ProjectType.tefillin => input.tefillinMode == 'parshiya'
          ? _parshiya(input, history, entryId)
          : _counted(input, entryId),
    };
  }

  static EntryOutcome _sefer(
      EntryInput input, Iterable<WorkSession> history, String entryId) {
    final project = input.project;
    final totalPages = project.totalPages;
    final linesPerPage = ProductionCalculator.linesPerPageOf(project);

    // A negative page number passed this check, and `formatHebrewNumber` has no
    // numeral for it — so the record was filed with a blank where its page
    // should be: "עמוד  (1-10)", which the writer cannot identify afterwards.
    final pageFrom = _page(input.pageFrom);
    if (pageFrom <= 0) {
      return const EntryRejected("יש להזין לפחות עמוד התחלה תקין");
    }
    if (totalPages != null && pageFrom > totalPages) {
      return EntryRejected("מספר העמוד חורג מהגדרת הספר ($totalPages)");
    }

    final pageToText = input.pageTo.trim();
    final pageToParsed = _page(pageToText);
    if (pageToText.isNotEmpty && pageToParsed <= 0) {
      return const EntryRejected("יש להזין עמוד סיום תקין או להשאיר אותו ריק");
    }
    if (pageToParsed > 0 && pageToParsed < pageFrom) {
      return const EntryRejected("עמוד הסיום לא יכול להיות לפני עמוד ההתחלה");
    }
    final pageTo = pageToParsed <= 0 ? null : pageToParsed;
    final isRange = pageTo != null && pageTo != pageFrom;

    if (isRange) {
      if (totalPages != null && pageTo > totalPages) {
        return EntryRejected("עמוד הסיום חורג מהגדרת הספר ($totalPages)");
      }
      // A commission with no stated page count had no upper bound at all, so a
      // slip in "up to page" built one record per page of a range that was
      // never meant: history is saved as a single JSON string, and a few
      // hundred thousand records of it is a file the app can no longer write.
      // Far beyond any real entry, and still a number rather than a hang.
      if (pageTo - pageFrom + 1 > _maxPagesPerEntry) {
        return EntryRejected(
            "טווח של יותר מ־$_maxPagesPerEntry עמודים בהזנה אחת — יש לפצל אותו");
      }

      // In a multi-page entry the two line fields describe the two ends of
      // one continuous stretch: the first page starts at `lineFrom`, every
      // page in the middle is full, and the last page stops at `lineTo`.
      // Previously both fields were silently discarded as soon as `pageTo`
      // was present, so page מג line 1 through page מד line 21 became two full
      // pages. Blank endpoints keep the convenient "whole pages" behaviour.
      final firstLine = input.lineFrom.trim().isEmpty
          ? 1
          : int.tryParse(input.lineFrom.trim()) ?? 0;
      final lastLine = input.lineTo.trim().isEmpty
          ? linesPerPage
          : int.tryParse(input.lineTo.trim()) ?? 0;
      if (firstLine < 1 || firstLine > linesPerPage) {
        return EntryRejected("שורת ההתחלה חייבת להיות בין 1 ל־$linesPerPage");
      }
      if (lastLine < 1 || lastLine > linesPerPage) {
        return EntryRejected("שורת הסיום חייבת להיות בין 1 ל־$linesPerPage");
      }

      final ranges = <({int page, int startLine, int endLine})>[
        for (var page = pageFrom; page <= pageTo; page++)
          (
            page: page,
            startLine: page == pageFrom ? firstLine : 1,
            endLine: page == pageTo ? lastLine : linesPerPage,
          ),
      ];

      var overlaps = false;
      for (final range in ranges) {
        if (_overlaps(
            history, project, range.page, range.startLine, range.endLine)) {
          overlaps = true;
          break;
        }
      }

      // One stretch of time was entered for the whole range, so it is divided
      // in proportion to the lines on each page. For a page and a half this
      // means the full page receives twice the time of the half page.
      final slices = SessionLogic.splitByWeight(
        start: input.start,
        end: input.end,
        weights: [for (final r in ranges) r.endLine - r.startLine + 1],
      );

      return EntryBuilt(
        sessions: [
          for (var i = 0; i < ranges.length; i++)
            _session(
              input,
              id: IdGenerator.generate(suffix: '${ranges[i].page}'),
              entryId: entryId,
              start: slices[i].start,
              end: slices[i].end,
              amount: ranges[i].page,
              startLine: ranges[i].startLine,
              endLine: ranges[i].endLine,
              description: "עמוד ${formatHebrewNumber(ranges[i].page)} "
                  "(${ranges[i].startLine}-${ranges[i].endLine})",
              linesPerPageAtEntry: linesPerPage,
            ),
        ],
        overlapsRecordedWork: overlaps,
        reachedPage: pageTo,
        reachedLine: lastLine,
      );
    }

    final startLine = int.tryParse(input.lineFrom.trim()) ?? 0;
    final endLine = int.tryParse(input.lineTo.trim()) ?? 0;
    final lineError = SessionLogic.validateSeferLines(
      startLine: startLine,
      endLine: endLine,
      linesPerPage: linesPerPage,
    );
    if (lineError != null) return EntryRejected(lineError);

    return EntryBuilt(
      sessions: [
        _session(
          input,
          id: IdGenerator.generate(),
          entryId: entryId,
          start: input.start,
          end: input.end,
          amount: pageFrom,
          startLine: startLine,
          endLine: endLine,
          description:
              "עמוד ${formatHebrewNumber(pageFrom)} ($startLine-$endLine)",
          linesPerPageAtEntry: linesPerPage,
        ),
      ],
      overlapsRecordedWork:
          _overlaps(history, project, pageFrom, startLine, endLine),
      reachedPage: pageFrom,
      reachedLine: endLine,
    );
  }

  /// A single tefillin parshiya, whole or part-written.
  static EntryOutcome _parshiya(
      EntryInput input, Iterable<WorkSession> history, String entryId) {
    final endLine = int.tryParse(input.partialLine.trim()) ?? 0;
    final lineError = SessionLogic.validateTefillinLine(
      tefillinType: input.tefillinPart,
      line: endLine,
    );
    if (lineError != null) return EntryRejected(lineError);

    final name = input.tefillinParshiya >= 1 && input.tefillinParshiya <= 4
        ? TefillinUnits.names[input.tefillinParshiya - 1]
        : "";
    final part = input.tefillinPart == 'head' ? "ראש" : "יד";
    // A pair of zero or less is no pair at all, and storing it would send the
    // parshiya to a slot that cannot exist.
    final pair = int.tryParse(input.tefillinPair.trim());
    final pairIndex = pair != null && pair >= 1 ? pair : null;
    if (pairIndex == null) {
      return const EntryRejected(
          "יש להזין מספר זוג כדי לשמור על סדר הפרשיות בתוך הסט");
    }

    final side =
        input.tefillinPart == 'head' ? TefillinSide.head : TefillinSide.hand;
    final slots = TefillinState.slots(input.project, history);
    final target = slots.firstWhere(
      (s) =>
          s.pair == pairIndex &&
          s.side == side &&
          s.parshiya == input.tefillinParshiya,
      orElse: () => TefillinSlot(
        pair: pairIndex,
        side: side,
        parshiya: input.tefillinParshiya,
      ),
    );
    if (target.state != SlotState.empty) {
      return EntryRejected("פרשיית $name בזוג $pairIndex כבר התחילה");
    }
    if (!TefillinState.canStart(target, slots)) {
      final previous = TefillinUnits.names[input.tefillinParshiya - 2];
      return EntryRejected(
          "אי אפשר להתחיל את $name לפני שהפרשייה $previous הסתיימה באותו סט");
    }

    var description = "פרשיית $name של $part";
    description += " (זוג $pairIndex)";
    if (endLine > 0) description += " (עד שורה $endLine)";

    return EntryBuilt(
      sessions: [
        _session(
          input,
          id: IdGenerator.generate(),
          entryId: entryId,
          start: input.start,
          end: input.end,
          amount: 1,
          startLine: 0,
          endLine: endLine,
          description: description,
          tefillinType: input.tefillinPart,
          parshiya: input.tefillinParshiya,
          pairIndex: pairIndex,
        ),
      ],
      overlapsRecordedWork: false,
      reachedPage: 1,
      reachedLine: endLine,
    );
  }

  /// Mezuzot, and tefillin counted as sets or as head/hand units.
  static EntryOutcome _counted(EntryInput input, String entryId) {
    // Negative as well as absent. A minus typed in front of a quantity used to
    // be accepted whole: five mezuzot entered as "-5" subtracted five from the
    // commission and five hundred shekels from its income, and nothing on any
    // screen said so — the totals simply went down.
    final amount = int.tryParse(input.amount.trim()) ?? 0;
    if (amount <= 0) return const EntryRejected("יש להזין כמות");

    var endLine = 0;
    String description;
    String? tefillinType;

    if (input.project.type == ProjectType.mezuza) {
      endLine = int.tryParse(input.partialLine.trim()) ?? 0;
      final lineError = SessionLogic.validateMezuzaLine(endLine);
      if (lineError != null) return EntryRejected(lineError);
      description =
          endLine > 0 ? "$amount מזוזות (עד שורה $endLine)" : "$amount מזוזות";
    } else {
      switch (input.tefillinMode) {
        case 'set':
          description = "$amount זוגות תפילין";
        case 'head':
          description = "$amount תפילין של ראש";
          tefillinType = 'head';
        case 'hand':
          description = "$amount תפילין של יד";
          tefillinType = 'hand';
        default:
          description = "$amount יחידות";
      }
    }

    return EntryBuilt(
      sessions: [
        _session(
          input,
          id: IdGenerator.generate(),
          entryId: entryId,
          start: input.start,
          end: input.end,
          amount: amount,
          startLine: 0,
          endLine: endLine,
          description: description,
          tefillinType: tefillinType,
        ),
      ],
      overlapsRecordedWork: false,
      reachedPage: amount,
      reachedLine: endLine,
    );
  }

  static bool _overlaps(Iterable<WorkSession> history, Project project,
          int page, int startLine, int endLine) =>
      SessionLogic.hasSeferOverlap(
        history: history,
        projectId: project.id,
        page: page,
        startLine: startLine,
        endLine: endLine,
        projectType: project.type,
      );

  /// The fields every record of an entry shares.
  ///
  /// `workingDateAtEntry` is set only when the writer stated a date. Where he
  /// did not, it is deliberately left unset: which day a timed session belongs
  /// to depends on his day-boundary setting, which is not this file's business,
  /// and the caller stamps every such record through one place so the two paths
  /// cannot answer it differently.
  static WorkSession _session(
    EntryInput input, {
    required String id,
    required String entryId,
    required DateTime start,
    required DateTime end,
    required int amount,
    required int startLine,
    required int endLine,
    required String description,
    String? tefillinType,
    int? parshiya,
    int? pairIndex,
    int? linesPerPageAtEntry,
  }) =>
      WorkSession(
        id: id,
        projectId: input.project.id,
        startTime: start,
        endTime: end,
        amount: amount,
        startLine: startLine,
        endLine: endLine,
        tefillinType: tefillinType,
        parshiya: parshiya,
        pairIndex: pairIndex,
        description: description,
        isManual: input.isManual,
        backlogOnly: input.backlogOnly,
        timeRecorded: input.timeRecorded,
        timeOfDayKnown: input.timeOfDayKnown,
        linesPerPageAtEntry: linesPerPageAtEntry,
        entryId: entryId,
        workingDateAtEntry: input.statedDate,
      );
}
