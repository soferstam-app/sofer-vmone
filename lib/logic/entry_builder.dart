import '../hebrew_utils.dart';
import '../models.dart';
import 'id_generator.dart';
import 'production_calculator.dart';
import 'session_logic.dart';

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

  final bool isManual;
  final bool backlogOnly;
  final bool timeRecorded;

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

  const EntryInput({
    required this.project,
    required this.start,
    required this.end,
    required this.isManual,
    this.backlogOnly = false,
    this.timeRecorded = true,
    this.pageFrom = '',
    this.pageTo = '',
    this.lineFrom = '',
    this.lineTo = '',
    this.amount = '',
    this.partialLine = '',
    this.tefillinMode = 'set',
    this.tefillinPart = 'head',
    this.tefillinParshiya = 1,
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
    return switch (input.project.type) {
      ProjectType.sefer => _sefer(input, history),
      ProjectType.mezuza => _counted(input),
      ProjectType.tefillin => input.tefillinMode == 'parshiya'
          ? _parshiya(input)
          : _counted(input),
    };
  }

  static EntryOutcome _sefer(EntryInput input, Iterable<WorkSession> history) {
    final project = input.project;
    final totalPages = project.totalPages;
    final linesPerPage = ProductionCalculator.linesPerPageOf(project);

    final pageFrom = _page(input.pageFrom);
    if (pageFrom == 0) {
      return const EntryRejected("יש להזין לפחות עמוד התחלה תקין");
    }
    if (totalPages != null && pageFrom > totalPages) {
      return EntryRejected("מספר העמוד חורג מהגדרת הספר ($totalPages)");
    }

    final pageToParsed = _page(input.pageTo);
    final pageTo = pageToParsed == 0 ? null : pageToParsed;
    final isRange = pageTo != null && pageTo >= pageFrom && pageTo != pageFrom;

    if (isRange) {
      if (totalPages != null && pageTo > totalPages) {
        return EntryRejected("עמוד הסיום חורג מהגדרת הספר ($totalPages)");
      }

      var overlaps = false;
      for (var p = pageFrom; p <= pageTo; p++) {
        if (_overlaps(history, project, p, 1, linesPerPage)) {
          overlaps = true;
          break;
        }
      }

      // One stretch of time was entered for the whole range, so it is divided
      // between the pages rather than handed to each of them whole.
      final pageCount = pageTo - pageFrom + 1;
      final slices = SessionLogic.splitRange(
          start: input.start, end: input.end, parts: pageCount);

      return EntryBuilt(
        sessions: [
          for (var i = 0; i < pageCount; i++)
            _session(
              input,
              id: IdGenerator.generate(suffix: '${pageFrom + i}'),
              start: slices[i].start,
              end: slices[i].end,
              amount: pageFrom + i,
              startLine: 1,
              endLine: linesPerPage,
              description:
                  "עמוד ${formatHebrewNumber(pageFrom + i)} (1-$linesPerPage)",
              linesPerPageAtEntry: linesPerPage,
            ),
        ],
        overlapsRecordedWork: overlaps,
        reachedPage: pageTo,
        reachedLine: linesPerPage,
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
  static EntryOutcome _parshiya(EntryInput input) {
    final endLine = int.tryParse(input.partialLine.trim()) ?? 0;
    final lineError = SessionLogic.validateTefillinLine(
      tefillinType: input.tefillinPart,
      line: endLine,
    );
    if (lineError != null) return EntryRejected(lineError);

    const names = ["קדש", "והיה כי יביאך", "שמע", "והיה אם שמוע"];
    final name = input.tefillinParshiya >= 1 && input.tefillinParshiya <= 4
        ? names[input.tefillinParshiya - 1]
        : "";
    final part = input.tefillinPart == 'head' ? "ראש" : "יד";
    var description = "פרשיית $name של $part";
    if (endLine > 0) description += " (עד שורה $endLine)";

    return EntryBuilt(
      sessions: [
        _session(
          input,
          id: IdGenerator.generate(),
          start: input.start,
          end: input.end,
          amount: 1,
          startLine: 0,
          endLine: endLine,
          description: description,
          tefillinType: input.tefillinPart,
          parshiya: input.tefillinParshiya,
        ),
      ],
      overlapsRecordedWork: false,
      reachedPage: 1,
      reachedLine: endLine,
    );
  }

  /// Mezuzot, and tefillin counted as sets or as head/hand units.
  static EntryOutcome _counted(EntryInput input) {
    final amount = int.tryParse(input.amount.trim()) ?? 0;
    if (amount == 0) return const EntryRejected("יש להזין כמות");

    var endLine = 0;
    String description;
    String? tefillinType;

    if (input.project.type == ProjectType.mezuza) {
      endLine = int.tryParse(input.partialLine.trim()) ?? 0;
      final lineError = SessionLogic.validateMezuzaLine(endLine);
      if (lineError != null) return EntryRejected(lineError);
      description = endLine > 0
          ? "$amount מזוזות (עד שורה $endLine)"
          : "$amount מזוזות";
    } else {
      switch (input.tefillinMode) {
        case 'set':
          description = "$amount סטים של תפילין";
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
  /// `workingDateAtEntry` is deliberately left unset. Which day a session is
  /// filed under depends on the writer's day-boundary setting, which is not
  /// this file's business — the caller stamps every record it saves through one
  /// place, so the two paths cannot answer it differently.
  static WorkSession _session(
    EntryInput input, {
    required String id,
    required DateTime start,
    required DateTime end,
    required int amount,
    required int startLine,
    required int endLine,
    required String description,
    String? tefillinType,
    int? parshiya,
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
        description: description,
        isManual: input.isManual,
        backlogOnly: input.backlogOnly,
        timeRecorded: input.timeRecorded,
        linesPerPageAtEntry: linesPerPageAtEntry,
      );
}
