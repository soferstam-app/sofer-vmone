import '../hebrew_utils.dart';
import '../models.dart';
import 'id_generator.dart';
import 'mezuza_state.dart';
import 'production_calculator.dart';
import 'session_logic.dart';
import 'tefillin_state.dart';
import 'tefillin_units.dart';
import 'tefillin_text.dart';

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

  /// Mezuza only: the part-written physical mezuza being resumed.
  ///
  /// Null means new work. The identity already exists on smart-mode records;
  /// carrying it through manual entry is what lets two separately entered
  /// halves become one mezuza instead of two unrelated partial ones.
  final int? mezuzaIndex;

  /// Tefillin only: `set`, `head`, `hand` or `parshiya`.
  final String tefillinMode;

  /// Tefillin parshiya mode only: `head` or `hand`.
  final String tefillinPart;

  /// Tefillin parshiya mode only, 1–4.
  final int tefillinParshiya;

  /// Which pair the parshiya belongs to, as typed or filled by a continuation.
  /// New manual parshiya records require a physical pair address.
  final String tefillinPair;

  /// Stable while a pending form is retried after a crash or storage error.
  /// Reusing it makes the durable write idempotent rather than duplicating the
  /// same work if history was saved but clearing the draft was interrupted.
  final String? entryId;
  final int? tefillinUntilWord;
  final int? tefillinBaselineWord;
  final StamScript tefillinScript;

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
    this.mezuzaIndex,
    this.tefillinMode = 'set',
    this.tefillinPart = 'head',
    this.tefillinParshiya = 1,
    this.tefillinPair = '',
    this.entryId,
    this.tefillinUntilWord,
    this.tefillinBaselineWord,
    this.tefillinScript = StamScript.beitYosef,
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
    final entryId = input.entryId ?? IdGenerator.generate();
    return switch (input.project.type) {
      ProjectType.sefer ||
      ProjectType.megillah =>
        _sefer(input, history, entryId),
      ProjectType.mezuza => _counted(input, history, entryId),
      ProjectType.tefillin => input.tefillinUntilWord != null
          ? _words(input, history, entryId)
          : input.tefillinMode == 'parshiya'
              ? _parshiya(input, history, entryId)
              : _counted(input, history, entryId),
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
  static EntryOutcome _words(
      EntryInput input, Iterable<WorkSession> history, String entryId) {
    history = history.where((s) => s.entryId != entryId);
    final p = input.tefillinParshiya;
    final pair = int.tryParse(input.tefillinPair);
    if (p < 1 ||
        p > 4 ||
        pair == null ||
        pair < 1 ||
        !const {'head', 'hand'}.contains(input.tefillinPart)) {
      return const EntryRejected('יש לבחור זוג, צד ופרשייה תקינים');
    }
    final side =
        input.tefillinPart == 'head' ? TefillinSide.head : TefillinSide.hand;
    final all = TefillinState.slots(input.project, history);
    final slot = all.firstWhere(
        (s) => s.pair == pair && s.side == side && s.parshiya == p,
        orElse: () => TefillinSlot(pair: pair, side: side, parshiya: p));
    if (!TefillinState.canWrite(slot, all) || slot.state == SlotState.stuck) {
      return const EntryRejected(
          'הפרשייה אינה זמינה לכתיבה. יש להשלים את הקודמת או לטפל בפסילה');
    }
    final previous = history
        .where((s) =>
            s.projectId == input.project.id &&
            !s.isDeleted &&
            !s.isInvalid &&
            s.countsAsOutput &&
            s.pairIndex == pair &&
            s.tefillinType == input.tefillinPart &&
            s.parshiya == p &&
            TefillinWordRange.isWordRecord(s))
        .toList();
    if (previous.isNotEmpty && slot.wordBoundary == null) {
      return const EntryRejected(
          'רישומי המילים אינם תואמים לנקודת ההמשך. יש לתקן את ההיסטוריה לפני הוספה');
    }
    final priorRange =
        previous.isEmpty ? null : TefillinWordRange.read(previous.first);
    final legacy = slot.linesWritten / TefillinUnits.linesIn(side);
    final base = priorRange?.baselineWord ??
        (legacy > 0 ? input.tefillinBaselineWord : 0);
    final text = TefillinText.of(p);
    if (base == null ||
        base < 0 ||
        base >= text.words.length ||
        (legacy > 0 && base == 0)) {
      return const EntryRejected(
          'יש לסמן את המילה האחרונה שכבר נרשמה לפי שורות לפני המעבר למילים');
    }
    final from = slot.wordBoundary ?? base;
    final until = input.tefillinUntilWord!;
    if (until <= from || until > text.words.length) {
      return const EntryRejected('יש לסמן מילה חדשה אחרי המילה האחרונה שנשמרה');
    }
    // Reject overlap with disconnected later stretches too, so deletion of an
    // earlier record can never make the later words count a second time.
    if (previous.any((s) {
      final r = TefillinWordRange.read(s);
      return r == null || (from < r.until && until > r.from);
    })) {
      return const EntryRejected(
          'טווח המילים חופף לרישום קיים. יש לתקן את ההיסטוריה לפני שמירה');
    }
    final range = TefillinWordRange(
        parshiya: p,
        from: from,
        until: until,
        baselineWord: base,
        baselineFraction: priorRange?.baselineFraction ?? legacy,
        script: input.tefillinScript.id);
    final session = _session(input,
            id: '$entryId-tefillin-words',
            entryId: entryId,
            start: input.start,
            end: input.end,
            amount: 0,
            startLine: 0,
            endLine: 0,
            tefillinType: input.tefillinPart,
            parshiya: p,
            pairIndex: pair,
            description:
                'פרשיית ${TefillinUnits.names[p - 1]} של ${side == TefillinSide.head ? 'ראש' : 'יד'} (זוג $pair, מילים ${from + 1}–$until, עד ${text.wordAt(until)})')
        .copyWith(
            isPartialLine: true,
            partialLineCompleted: true,
            extraFields: {TefillinWordRange.key: range.toJson()});
    return EntryBuilt(
        sessions: [session],
        overlapsRecordedWork: false,
        reachedPage: (pair - 1) * 8 + (side == TefillinSide.head ? 0 : 4) + p,
        reachedLine:
            until == text.words.length ? TefillinUnits.linesIn(side) : 0);
  }

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
    if (history.any((s) =>
        s.projectId == input.project.id &&
        !s.isDeleted &&
        !s.isInvalid &&
        s.pairIndex == pairIndex &&
        s.tefillinType == input.tefillinPart &&
        s.parshiya == input.tefillinParshiya &&
        TefillinWordRange.isWordRecord(s))) {
      return const EntryRejected(
          'הפרשייה נרשמת לפי מילים. יש להמשיך לפי המילה האחרונה שנשמרה');
    }
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
    if (target.state == SlotState.partial) {
      if (!TefillinState.canWrite(target, slots)) {
        return EntryRejected(
            "אי אפשר להמשיך את $name לפני שהפרשייה הקודמת הסתיימה באותו סט");
      }
      if (endLine <= 0) {
        return const EntryRejected("יש להזין עד איזו שורה הגעת עכשיו");
      }
      if (endLine <= target.linesWritten) {
        return EntryRejected(
            "פרשיית $name בזוג $pairIndex כבר נכתבה עד שורה ${target.linesWritten}");
      }
      final maxLines = TefillinUnits.linesIn(side);
      final complete = endLine >= maxLines;
      final from = target.linesWritten + 1;
      final description = complete
          ? "השלמת פרשיית $name של $part (זוג $pairIndex, שורות $from–$endLine)"
          : "פרשיית $name של $part (זוג $pairIndex, שורות $from–$endLine)";
      return EntryBuilt(
        sessions: [
          _session(
            input,
            id: IdGenerator.generate(),
            entryId: entryId,
            start: input.start,
            end: input.end,
            // The first stretch already introduced this physical parshiya.
            // Zero keeps old readers and count-based totals from treating the
            // continuation as another complete unit.
            amount: 0,
            startLine: from,
            endLine: endLine,
            description: description,
            tefillinType: input.tefillinPart,
            parshiya: input.tefillinParshiya,
            pairIndex: pairIndex,
          ),
        ],
        overlapsRecordedWork: false,
        reachedPage: pairIndex,
        reachedLine: endLine,
      );
    }
    if (target.state == SlotState.done) {
      return EntryRejected("פרשיית $name בזוג $pairIndex כבר הסתיימה");
    }
    if (target.state == SlotState.voided) {
      return EntryRejected(
          "פרשיית $name בזוג $pairIndex נפסלה; יש להסיר אותה לפני התחלה מחדש");
    }
    if (target.state != SlotState.empty) {
      return EntryRejected("פרשיית $name בזוג $pairIndex אינה זמינה לכתיבה");
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
          // A partial new parshiya is an exact first range. A blank line still
          // retains the compatible whole-parshiya shape.
          startLine: endLine > 0 ? 1 : 0,
          endLine: endLine,
          description: description,
          tefillinType: input.tefillinPart,
          parshiya: input.tefillinParshiya,
          pairIndex: pairIndex,
        ),
      ],
      overlapsRecordedWork: false,
      // Smart mode folds the physical tefillin address into the page field.
      // Returning one here made a manually entered parshiya reset the smart
      // workflow to the first slot of the first pair.
      reachedPage: (pairIndex - 1) * 8 +
          (side == TefillinSide.head ? 0 : 4) +
          input.tefillinParshiya,
      reachedLine: endLine,
    );
  }

  /// Mezuzot, and tefillin counted as sets or as head/hand units.
  static EntryOutcome _counted(
      EntryInput input, Iterable<WorkSession> history, String entryId) {
    if (input.project.type == ProjectType.mezuza && input.mezuzaIndex != null) {
      final index = input.mezuzaIndex!;
      MezuzaSlot? slot;
      for (final candidate in MezuzaState.slots(input.project, history)) {
        if (candidate.index == index) slot = candidate;
      }
      if (slot == null || slot.state != MezuzaSlotState.partial) {
        return const EntryRejected(
            "המזוזה שנבחרה כבר אינה חלקית. יש לרענן ולבחור שוב");
      }

      final reached = int.tryParse(input.partialLine.trim()) ?? 0;
      if (reached <= 0) {
        return const EntryRejected("יש להזין עד איזו שורה הגעת");
      }
      final lineError = SessionLogic.validateMezuzaLine(reached);
      if (lineError != null) return EntryRejected(lineError);
      if (reached <= slot.linesWritten) {
        return EntryRejected(
            "מזוזה $index כבר נכתבה עד שורה ${slot.linesWritten}");
      }

      final added = reached - slot.linesWritten;
      final complete = reached >= ProductionCalculator.linesPerMezuza;
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
            // For an identified mezuza this is the contribution of this
            // stretch. MezuzaState adds it to the earlier stretch.
            endLine: added,
            description: complete
                ? "השלמת מזוזה $index (שורות ${slot.linesWritten + 1}–$reached)"
                : "מזוזה $index (שורות ${slot.linesWritten + 1}–$reached)",
            mezuzaIndex: index,
          ),
        ],
        overlapsRecordedWork: false,
        reachedPage: index,
        reachedLine: reached,
      );
    }

    // Negative as well as absent. A minus typed in front of a quantity used to
    // be accepted whole: five mezuzot entered as "-5" subtracted five from the
    // commission and five hundred shekels from its income, and nothing on any
    // screen said so — the totals simply went down.
    final amount = int.tryParse(input.amount.trim()) ?? 0;
    if (amount <= 0) return const EntryRejected("יש להזין כמות");

    var endLine = 0;
    String description;
    String? tefillinType;
    int? mezuzaIndex;

    if (input.project.type == ProjectType.mezuza) {
      endLine = int.tryParse(input.partialLine.trim()) ?? 0;
      final lineError = SessionLogic.validateMezuzaLine(endLine);
      if (lineError != null) return EntryRejected(lineError);
      description =
          endLine > 0 ? "$amount מזוזות (עד שורה $endLine)" : "$amount מזוזות";
      // Give a single new partial an identity immediately, so its second half
      // can be selected later even when its date is edited or other mezuzot
      // are entered in between. Larger counted entries retain their compatible
      // legacy shape; their last partial is still reconstructed by MezuzaState.
      if (amount == 1 && endLine > 0) {
        final slots = MezuzaState.slots(input.project, history);
        for (final slot in slots) {
          if (slot.state == MezuzaSlotState.empty) {
            mezuzaIndex = slot.index;
            break;
          }
        }
        mezuzaIndex ??= slots.length + 1;
      }
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
          mezuzaIndex: mezuzaIndex,
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
    int? mezuzaIndex,
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
        mezuzaIndex: mezuzaIndex,
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
