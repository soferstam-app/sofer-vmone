import 'dart:async';

import 'package:flutter/cupertino.dart'
    show CupertinoTimerPicker, CupertinoTimerPickerMode;
import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';

import '../format.dart';
import '../hebrew_utils.dart';
import '../logic/date_logic.dart';
import '../logic/entry_builder.dart';
import '../logic/id_generator.dart';
import '../logic/hebrew_clock.dart';
import '../logic/json_compat.dart';
import '../logic/mezuza_state.dart';
import '../logic/session_logic.dart';
import '../logic/tefillin_position.dart';
import '../logic/tefillin_state.dart';
import '../logic/tefillin_units.dart';
import '../models.dart';
import '../projects_screen.dart' show ProjectDialog;
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/sofer_widgets.dart';
import '../widgets/confirm.dart';
import '../l10n/app_localizations.dart';
import 'entry_draft.dart';
import '../logic/tefillin_text.dart';
import 'tefillin_words_dialog.dart';

/// Carries the length of the previous clock range into "save and continue".
/// Clock minutes wrap at midnight; 23:00–01:00 is two hours, not a negative
/// span that should fall back to the one-hour default.
TimeOfDay continuationEndTime(TimeOfDay previousStart, TimeOfDay previousEnd) {
  final from = previousStart.hour * 60 + previousStart.minute;
  final nextStart = previousEnd.hour * 60 + previousEnd.minute;
  final wrappedSpan = (nextStart - from + 24 * 60) % (24 * 60);
  final span = wrappedSpan == 0 ? 60 : wrappedSpan;
  final nextEnd = (nextStart + span) % (24 * 60);
  return TimeOfDay(hour: nextEnd ~/ 60, minute: nextEnd % 60);
}

/// What one save from the entry form produced.
///
/// Handed back rather than written here: which day a record is filed under,
/// where the stored position now is, and whether a daily target has been met
/// are all the caller's business, and the form has no opinion about them.
class EntrySave {
  final Project project;
  final List<WorkSession> sessions;

  /// How far the writer has got, for the stored position.
  final int reachedPage;
  final int reachedLine;

  final bool backlogOnly;
  final bool? tefillinWordEntry;
  final StamScript? tefillinScript;

  const EntrySave({
    required this.project,
    required this.sessions,
    required this.reachedPage,
    required this.reachedLine,
    required this.backlogOnly,
    this.tefillinWordEntry,
    this.tefillinScript,
  });
}

/// Opens the form that records work, and returns the commission it was last
/// used on — so the screen behind it can keep its selection in step.
///
/// A screen of its own on a phone, a dialog on a wide window. The same form and
/// the same actions in both: an AlertDialog on a phone is a small scrolling box
/// with the keyboard over half of it and the buttons below the fold, which is a
/// poor place for the one path every recorded sitting goes through.
Future<Project?> showEntrySheet({
  required BuildContext context,
  required bool isManual,
  required List<Project> projects,
  required List<WorkSession> history,
  required bool useGregorianDates,
  required DayStart dayStart,
  required FutureOr<void> Function(Project project) onProjectCreated,
  required Future<void> Function(EntrySave save) onSave,
  Project? initialProject,
  Duration measuredTime = Duration.zero,
  DateTime? measuredEnd,
  EntryDraft? initialDraft,
  DateTime? initialDate,
}) {
  final asDialog = MediaQuery.of(context).size.width >= 600;

  Widget build(BuildContext _) => _EntrySheet(
        asDialog: asDialog,
        isManual: isManual,
        projects: projects,
        history: history,
        useGregorianDates: useGregorianDates,
        dayStart: dayStart,
        onProjectCreated: onProjectCreated,
        onSave: onSave,
        initialProject: initialProject,
        measuredTime: measuredTime,
        measuredEnd: measuredEnd,
        initialDraft: initialDraft,
        initialDate: initialDate,
      );

  if (asDialog) {
    return showDialog<Project>(
      context: context,
      barrierDismissible: false,
      builder: build,
    );
  }
  return Navigator.of(context).push<Project>(
    MaterialPageRoute(fullscreenDialog: true, builder: build),
  );
}

class _EntrySheet extends StatefulWidget {
  final bool asDialog;
  final bool isManual;
  final List<Project> projects;
  final List<WorkSession> history;
  final bool useGregorianDates;
  final DayStart dayStart;
  final FutureOr<void> Function(Project project) onProjectCreated;
  final Future<void> Function(EntrySave save) onSave;
  final Project? initialProject;
  final Duration measuredTime;
  final DateTime? measuredEnd;
  final EntryDraft? initialDraft;
  final DateTime? initialDate;

  const _EntrySheet({
    required this.asDialog,
    required this.isManual,
    required this.projects,
    required this.history,
    required this.useGregorianDates,
    required this.dayStart,
    required this.onProjectCreated,
    required this.onSave,
    required this.initialProject,
    required this.measuredTime,
    required this.measuredEnd,
    required this.initialDraft,
    required this.initialDate,
  });

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final StorageService _storage = StorageService();
  final ScrollController _scrollController = ScrollController();

  Project? _project;

  final _pageCtrl = TextEditingController();
  final _pageToCtrl = TextEditingController();
  final _lineFromCtrl = TextEditingController();
  final _lineToCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _partialLineCtrl = TextEditingController();

  /// A stopped physical mezuza chosen for continuation. Null means new work.
  int? _mezuzaIndex;

  /// Which pair of the commission a parshiya belongs to. New manual records
  /// require it; a continuation fills and locks it from the physical slot.
  final _pairCtrl = TextEditingController();

  DateTime? _date;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 10, minute: 0);
  bool _includeTime = true;

  /// How long he wrote, when he says it that way.
  ///
  /// The form used to ask only "from what hour to what hour", which is two
  /// pickers and a subtraction to answer a question a sofer already knows the
  /// answer to. He knows he wrote for two hours; he does not necessarily
  /// remember that it was 21:10 to 23:10.
  Duration _worked = const Duration(hours: 1);

  /// Whether he is giving a length or a stretch of the clock.
  ///
  /// A length is the default because it is what he has in his head. The clock
  /// is still there for anyone who wants it — and it is the only one of the two
  /// that says *when* he was writing, which is why the record keeps the
  /// difference rather than guessing.
  bool _byDuration = true;

  String _tefillinMode = 'set';
  String _tefillinPart = 'head';
  int _tefillinParshiya = 1;
  String? _tefillinContinuationKey;
  late String _draftEntryId;
  bool _saving = false;
  bool _tefillinWords = false;
  StamScript _tefillinScript = StamScript.beitYosef;
  int? _untilWord;
  int? _baselineWord;
  String? _formError;

  /// What the position fields were offered with, so that cancelling a form the
  /// writer never touched does not ask them to confirm anything.
  String _prefilledPage = '';
  String _prefilledLine = '';

  /// Whether the measured time of this sitting has already been given to a
  /// record.
  ///
  /// A sitting is one measured stretch. Adding a second record without closing —
  /// two pages that are not next to each other, say — used to hand it the same
  /// hour again, so an hour at the desk was recorded as two. The first record
  /// carries the time; the rest state that they carry none of their own, which
  /// leaves the day's total right and the average across the units right.
  bool _sittingTimeUsed = false;

  // The route receives a history snapshot. Entries saved without closing the
  // route must take part in its next continuation and validation as well.
  final List<WorkSession> _savedInSheet = [];
  List<WorkSession> get _history => [
        ...widget.history,
        ..._savedInSheet.where((saved) =>
            !widget.history.any((existing) => existing.id == saved.id)),
      ];

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
    _loadWordPreferences();
    _draftEntryId = widget.initialDraft?.entryId ?? IdGenerator.generate();
    if (_project == null) _restoreLastProject();
    // Today, for both paths. It used to open blank for a manual entry, so
    // every single record began by asking a writer what day it was — and the
    // overwhelmingly common answer is the one the device already knows. The
    // date row still opens a picker, and "no date" is still in it for backlog.
    _date = widget.initialDate ??
        DateLogic.effectiveDate(DateTime.now(), widget.dayStart);
    final project = _project;
    if (project != null && widget.initialDraft == null) {
      _suggestSingleContinuation(project);
      _prefillPositionFrom(project);
    }
    final draft = widget.initialDraft;
    if (draft != null) _applyDraft(draft);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _pageToCtrl.dispose();
    _lineFromCtrl.dispose();
    _lineToCtrl.dispose();
    _amountCtrl.dispose();
    _partialLineCtrl.dispose();
    _pairCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applyDraft(EntryDraft draft) {
    for (final project in widget.projects) {
      if (project.id == draft.projectId) _project = project;
    }
    _date = draft.date;
    _includeTime = draft.includeTime;
    _byDuration = draft.byDuration;
    _worked = draft.worked;
    _startTime = draft.startTime;
    _endTime = draft.endTime;
    _pageCtrl.text = draft.pageFrom;
    _pageToCtrl.text = draft.pageTo;
    _lineFromCtrl.text = draft.lineFrom;
    _lineToCtrl.text = draft.lineTo;
    _amountCtrl.text = draft.amount;
    _partialLineCtrl.text = draft.partialLine;
    _mezuzaIndex = draft.mezuzaIndex;
    _tefillinMode = draft.tefillinMode;
    _tefillinPart = draft.tefillinPart;
    _tefillinParshiya = draft.tefillinParshiya;
    _pairCtrl.text = draft.tefillinPair;
    _tefillinWords = draft.tefillinWords ||
        (_project != null && TefillinPreferences.usesWords(_project!));
    _tefillinScript = draft.tefillinScript == null
        ? _tefillinScript
        : StamScript.fromId(draft.tefillinScript);
    _untilWord = draft.tefillinUntilWord;
    _baselineWord = draft.tefillinBaselineWord;
    if (_tefillinWords) {
      _tefillinMode = 'parshiya';
      if (_pairCtrl.text.isEmpty && _project != null) {
        _suggestSingleContinuation(_project!);
      }
    }
  }

  EntryDraft _draft() {
    final project = _project!;
    return EntryDraft(
      projectId: project.id,
      entryId: _draftEntryId,
      isManual: widget.isManual,
      measuredTime: widget.measuredTime,
      measuredEnd: widget.measuredEnd,
      date: _date,
      includeTime: _includeTime,
      byDuration: _byDuration,
      worked: _worked,
      startTime: _startTime,
      endTime: _endTime,
      pageFrom: _pageCtrl.text,
      pageTo: _pageToCtrl.text,
      lineFrom: _lineFromCtrl.text,
      lineTo: _lineToCtrl.text,
      amount: _amountCtrl.text,
      partialLine: _partialLineCtrl.text,
      mezuzaIndex: _mezuzaIndex,
      tefillinMode: _tefillinMode,
      tefillinPart: _tefillinPart,
      tefillinParshiya: _tefillinParshiya,
      tefillinPair: _pairCtrl.text,
      tefillinWords: _tefillinWords,
      tefillinUntilWord: _untilWord,
      tefillinBaselineWord: _baselineWord,
      tefillinScript: _tefillinScript.id,
    );
  }

  void _showFormError(String message) {
    if (!mounted) return;
    setState(() => _formError = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  /// Empties every field of the form.
  void _clearFields() {
    _untilWord = null;
    _baselineWord = null;
    _pageCtrl.clear();
    _pageToCtrl.clear();
    _lineFromCtrl.clear();
    _lineToCtrl.clear();
    _amountCtrl.clear();
    _partialLineCtrl.clear();
    _pairCtrl.clear();
    _mezuzaIndex = null;
    _tefillinContinuationKey = null;
    _prefilledPage = '';
    _prefilledLine = '';
  }

  /// Makes the common case require no discovery: when exactly one physical
  /// set has one continuation, continuing it is the safe default. The writer can
  /// still choose new work explicitly from the selector shown above the
  /// fields.
  void _suggestSingleContinuation(Project project) {
    if (project.type == ProjectType.mezuza) {
      final partials = MezuzaState.slots(project, _history)
          .where((slot) => slot.state == MezuzaSlotState.partial)
          .toList();
      if (partials.length == 1) {
        _mezuzaIndex = partials.single.index;
        _partialLineCtrl.text = '22';
      }
      return;
    }
    if (project.type != ProjectType.tefillin) return;
    final available = TefillinState.continuations(project, _history);
    if (available.length == 1) _selectTefillinContinuation(available.single);
  }

  String _tefillinKey(TefillinSlot slot) =>
      '${slot.pair}:${slot.side.name}:${slot.parshiya}';

  void _selectTefillinContinuation(TefillinSlot slot) {
    _untilWord = null;
    _baselineWord = null;
    if (slot.wordBoundary != null) _tefillinWords = true;
    _tefillinContinuationKey = _tefillinKey(slot);
    _tefillinMode = 'parshiya';
    _tefillinPart = slot.side == TefillinSide.head ? 'head' : 'hand';
    _tefillinParshiya = slot.parshiya;
    _pairCtrl.text = slot.pair.toString();
    _partialLineCtrl.text = TefillinUnits.linesIn(slot.side).toString();
    _amountCtrl.clear();
  }

  void _clearTefillinContinuation() {
    _tefillinContinuationKey = null;
    _untilWord = null;
    _baselineWord = null;
  }

  void _loadWordPreferences() {
    final project = _project;
    _tefillinWords = project != null && TefillinPreferences.usesWords(project);
    _tefillinScript = project == null
        ? StamScript.beitYosef
        : TefillinPreferences.script(project);
    if (_tefillinWords) _tefillinMode = 'parshiya';
  }

  TefillinSlot? _wordSlot(Project project) {
    final pair = int.tryParse(_pairCtrl.text);
    for (final s in TefillinState.slots(project, _history)) {
      if (s.pair == pair &&
          s.side.name == _tefillinPart &&
          s.parshiya == _tefillinParshiya) {
        return s;
      }
    }
    return null;
  }

  Future<void> _chooseLastWord(Project project) async {
    final pair = int.tryParse(_pairCtrl.text);
    if (pair == null || pair < 1) {
      _showFormError(context.l10n
          .pick(he: 'יש להזין מספר זוג תחילה', en: 'Enter a set number first'));
      return;
    }
    final all = TefillinState.slots(project, _history);
    final slot = _wordSlot(project) ??
        TefillinSlot(
            pair: pair,
            side:
                _tefillinPart == 'head' ? TefillinSide.head : TefillinSide.hand,
            parshiya: _tefillinParshiya);
    if (!TefillinState.canWrite(slot, all)) {
      _showFormError(context.l10n.pick(
          he: 'יש להשלים את הפרשייה הקודמת; פרשייה שהסתיימה או נפסלה אינה זמינה',
          en: 'Complete the preceding Parashah. Finished or invalid Parashiyot cannot be continued'));
      return;
    }
    final label =
        '${slot.parshiyaName} · ${_tefillinPart == 'head' ? 'ראש' : 'יד'} · ${context.l10n.pick(he: 'זוג', en: 'Set')} $pair';
    if (slot.wordBoundary == null &&
        slot.linesWritten > 0 &&
        _baselineWord == null) {
      final base = await showTefillinWords(
          context: context,
          parshiya: _tefillinParshiya,
          script: _tefillinScript,
          unitLabel: label,
          locatingLegacyPosition: true);
      if (base == null || !mounted) return;
      setState(() => _baselineWord = base);
    }
    if (!mounted) return;
    final chosen = await showTefillinWords(
        context: context,
        parshiya: _tefillinParshiya,
        script: _tefillinScript,
        unitLabel: label,
        fromWord: slot.wordBoundary ?? _baselineWord ?? 0,
        selectedWord: _untilWord);
    if (chosen != null && mounted) setState(() => _untilWord = chosen);
  }

  /// Offers where the writer left off, as a starting point they can change.
  ///
  /// The position is stored per commission and kept in step by manual entries as
  /// well as by the smart workflow, so it is the same answer smart mode resumes
  /// from. Only a sefer has one: mezuzot and tefillin are counted rather than
  /// paginated, and there is nothing there to suggest.
  Future<void> _prefillPositionFrom(Project project) async {
    if (!project.type.isPaged) return;
    final position = await _storage.getLastPosition(project.id);
    if (!mounted || position.isEmpty) return;
    final page =
        (JsonCompat.intOrNull(position['page']) ?? 1).clamp(1, 1 << 20);
    final line =
        (JsonCompat.intOrNull(position['line']) ?? 1).clamp(1, 1 << 20);
    setState(() {
      _prefilledPage = formatHebrewNumber(page);
      _prefilledLine = line.toString();
      _pageCtrl.text = _prefilledPage;
      _lineFromCtrl.text = _prefilledLine;
    });
  }

  /// Falls back to the commission this form was last used on.
  ///
  /// Only when the screen behind did not already have one in hand. A sofer
  /// works on one job for weeks, and being asked to pick it out of a list every
  /// time is being asked something the app already knows.
  Future<void> _restoreLastProject() async {
    final id = await _storage.getLastProjectId();
    if (id == null || !mounted) return;
    for (final p in widget.projects) {
      if (p.id != id) continue;
      setState(() {
        _project = p;
        _loadWordPreferences();
        _suggestSingleContinuation(p);
      });
      _prefillPositionFrom(p);
      return;
    }
  }

  /// Opens a new commission without leaving the form.
  ///
  /// The very dialog the projects screen uses, so a project opened here carries
  /// every field one opened there does. Without it, writing something for a job
  /// not yet in the app meant discarding a measured sitting, going to create it,
  /// and typing the time back in by hand.
  Future<void> _createProject() async {
    Project? created;
    await showDialog(
      context: context,
      builder: (_) => ProjectDialog(
        useGregorianDates: widget.useGregorianDates,
        onSave: (project) => created = project,
      ),
    );
    if (created == null || !mounted) return;
    await widget.onProjectCreated(created!);
    if (!mounted) return;
    setState(() {
      _project = created;
      _loadWordPreferences();
      _suggestSingleContinuation(created!);
    });
  }

  /// Asks before an entry is thrown away.
  ///
  /// The button read "מחיקה / ביטול" and did neither of them — it closed. After a
  /// timed sitting that discards, without a word, the one thing on the form that
  /// cannot simply be typed in again: the time the app just measured.
  Future<bool> _confirmDiscard() async {
    final touched = _untilWord != null ||
        _baselineWord != null ||
        _pageToCtrl.text.trim().isNotEmpty ||
        _lineToCtrl.text.trim().isNotEmpty ||
        _amountCtrl.text.trim().isNotEmpty ||
        _partialLineCtrl.text.trim().isNotEmpty ||
        _pageCtrl.text.trim() != _prefilledPage ||
        _lineFromCtrl.text.trim() != _prefilledLine;

    // Nothing measured and nothing typed — there is nothing to lose, and asking
    // would only be in the way.
    if (widget.isManual && !touched) return true;

    final confirmed = await confirmAction(
      context,
      title: context.l10n.pick(
        he: "לבטל את ההזנה?",
        en: "Discard this entry?",
      ),
      message: widget.isManual
          ? context.l10n.pick(
              he: "מה שהוזן כאן לא יישמר.",
              en: "The information entered here will not be saved.",
            )
          : context.l10n.pick(
              he: "זמן העבודה שנמדד — ${formatClock(widget.measuredTime)} — לא יישמר, ואי אפשר לשחזר אותו.",
              en: "The measured writing time — ${formatClock(widget.measuredTime)} — will not be saved and cannot be recovered.",
            ),
      cancelLabel: context.l10n.pick(
        he: "המשך בהזנה",
        en: "Continue editing",
      ),
      confirmLabel: context.l10n.pick(
        he: "בטל את ההזנה",
        en: "Discard entry",
      ),
      danger: true,
    );
    return confirmed;
  }

  Future<void> _close() async {
    if (_saving) return;
    if (!await _confirmDiscard()) return;
    try {
      await _storage.clearPendingEntry();
    } catch (_) {
      // He explicitly discarded it. A stale recovery prompt is less harmful
      // than trapping him in a form he asked to close.
    }
    if (mounted) Navigator.pop(context, _project);
  }

  // --- Saving ---------------------------------------------------------------

  /// The stretch of time the entry covers.
  ///
  /// Four cases, and they are not interchangeable: a measured sitting, a manual
  /// entry with hours, one with a date but no hours, and one with no date at
  /// all. The last two both come out as an instant rather than a stretch —
  /// which is why the record says outright whether a time was given, instead of
  /// leaving a later reader to guess from a duration of zero.
  ({DateTime start, DateTime end}) _times() {
    if (!widget.isManual) {
      final end = widget.measuredEnd ?? DateTime.now();
      // A sitting's measured time belongs to one record. A second record added
      // without closing carries none of its own.
      return (
        start: _sittingTimeUsed ? end : end.subtract(widget.measuredTime),
        end: end,
      );
    }

    final date = _date;
    if (date == null) {
      // No date at all — a backlog record, counting towards output and nothing
      // else. The timestamp is a placeholder; backlogOnly carries the meaning.
      final placeholder = DateTime(2000, 1, 1, 12, 0);
      return (start: placeholder, end: placeholder);
    }
    if (!_includeTime) {
      final noon = DateTime(date.year, date.month, date.day, 12, 0);
      return (start: noon, end: noon);
    }
    if (_byDuration) {
      // Anchored at midday and run backwards, because a length has to be
      // stored as a pair of timestamps and something has to hold it. The hour
      // means nothing, and `timeOfDayKnown: false` says so — see WorkSession.
      final noon = DateTime(date.year, date.month, date.day, 12, 0);
      return (start: noon.subtract(_worked), end: noon);
    }
    final range = SessionLogic.buildTimeRange(
      date: date,
      startHour: _startTime.hour,
      startMinute: _startTime.minute,
      endHour: _endTime.hour,
      endMinute: _endTime.minute,
    );
    return (start: range.start, end: range.end);
  }

  /// Turns what is on the form into records, and hands them to the caller.
  ///
  /// The reading and the rules live in [EntryBuilder], which is pure and
  /// tested. What is left here is what genuinely needs the screen: the stretch
  /// of time the form is set to, asking the writer about an overlap, and showing
  /// a refusal.
  Future<bool> _save() async {
    final project = _project;
    if (project == null) return false;
    if (project.type == ProjectType.tefillin &&
        _tefillinWords &&
        _untilWord == null) {
      _showFormError(context.l10n.pick(
          he: 'יש לסמן את המילה האחרונה שסיימת לכתוב',
          en: 'Select the last completed word'));
      return false;
    }

    final times = _times();
    final backlogOnly = widget.isManual && _date == null;

    final outcome = EntryBuilder.build(
      input: EntryInput(
        project: project,
        start: times.start,
        end: times.end,
        // Only when he said it. The timer's own records carry no stated date
        // and are filed by the boundary rule, as they should be.
        statedDate: widget.isManual ? _date : null,
        isManual: widget.isManual,
        backlogOnly: backlogOnly,
        // Stated, not inferred later from start == end. A writer who chose not
        // to give a time and a sitting that happened to measure nothing are
        // different facts, and only here is it known which this is.
        timeRecorded: widget.isManual
            ? (_date != null && _includeTime)
            : !_sittingTimeUsed,
        // Whether the hour on the record is a fact or an anchor. The timer
        // always knows; a hand-entered length never does.
        timeOfDayKnown: widget.isManual ? !_byDuration : true,
        pageFrom: _pageCtrl.text,
        pageTo: _pageToCtrl.text,
        lineFrom: _lineFromCtrl.text,
        lineTo: _lineToCtrl.text,
        amount: _amountCtrl.text,
        partialLine: _partialLineCtrl.text,
        mezuzaIndex: _mezuzaIndex,
        tefillinMode: _tefillinMode,
        tefillinPart: _tefillinPart,
        tefillinParshiya: _tefillinParshiya,
        tefillinPair: _pairCtrl.text,
        entryId: _draftEntryId,
        tefillinUntilWord: _tefillinWords ? _untilWord : null,
        tefillinBaselineWord: _baselineWord,
        tefillinScript: _tefillinScript,
      ),
      history: _history,
    );

    switch (outcome) {
      case EntryRejected(:final message):
        _showFormError(context.l10n.businessMessage(message));
        return false;

      case EntryBuilt(
          :final sessions,
          :final overlapsRecordedWork,
          :final reachedPage,
          :final reachedLine
        ):
        if (overlapsRecordedWork &&
            !await _confirmOverlap(sessions.length > 1)) {
          return false;
        }
        try {
          await widget.onSave(EntrySave(
            project: project,
            sessions: sessions,
            reachedPage: reachedPage,
            reachedLine: reachedLine,
            backlogOnly: backlogOnly,
            tefillinWordEntry:
                project.type == ProjectType.tefillin ? _tefillinWords : null,
            tefillinScript:
                project.type == ProjectType.tefillin ? _tefillinScript : null,
          ));
          _savedInSheet.addAll(sessions);
        } catch (error) {
          debugPrint('Entry save failed: $error');
          if (!mounted) return false;
          _showFormError(context.l10n.pick(
            he: 'השמירה לא הושלמה. הנתונים נשמרו כטיוטה ויוצגו שוב בפתיחה הבאה. יש לבדוק שיש מקום פנוי ושהאחסון זמין, ואז לנסות שוב.',
            en: 'Saving did not finish. The entry remains as a draft and will reopen next time. Check that storage is available and has free space, then try again.',
          ));
          return false;
        }
        // Remembered for the next entry, so the list is not asked again.
        try {
          await _storage.setLastProjectId(project.id);
        } catch (_) {
          // History is already durable. Remembering the last project is only a
          // convenience and must not turn a successful save into a retry.
        }
        return true;
    }
  }

  Future<bool> _confirmOverlap(bool isRange) =>
      confirmOverlap(context, range: isRange);

  /// Saves and stays, so a day recorded in parts is one sitting at the keyboard
  /// rather than a form opened and closed for every stretch of it.
  Future<void> _saveAndContinue() async {
    if (!await _attemptSave()) return;
    try {
      await _storage.clearPendingEntry();
    } catch (_) {}
    if (!mounted) return;

    final project = _project;
    final previousTefillin = project?.type == ProjectType.tefillin &&
            _tefillinMode == 'parshiya' &&
            int.tryParse(_pairCtrl.text) != null
        ? TefillinPosition(
            pair: int.parse(_pairCtrl.text),
            side:
                _tefillinPart == 'head' ? TefillinSide.head : TefillinSide.hand,
            parshiya: _tefillinParshiya,
          )
        : null;
    _clearFields();
    _draftEntryId = IdGenerator.generate();
    // The stored position moved on with the entry, so the next record is
    // offered starting where this one ended.
    if (project != null) {
      _suggestSingleContinuation(project);
      if (previousTefillin != null) {
        final available = TefillinState.continuations(project, _history);
        for (final slot in available) {
          final at = TefillinPosition(
              pair: slot.pair, side: slot.side, parshiya: slot.parshiya);
          if (at == previousTefillin || at == previousTefillin.next) {
            _selectTefillinContinuation(slot);
            break;
          }
        }
      }
      await _prefillPositionFrom(project);
    }
    if (!mounted) return;

    setState(() {
      if (widget.isManual && _date != null && _includeTime) {
        // The next stretch of the day begins when the last one ended, keeping
        // the same length. A suggestion, like the position — the row underneath
        // says what it is and one tap changes it.
        final previousStart = _startTime;
        final previousEnd = _endTime;
        final startMinutes = previousEnd.hour * 60 + previousEnd.minute;
        final suggestedEnd = continuationEndTime(previousStart, previousEnd);
        _startTime = TimeOfDay(
            hour: (startMinutes ~/ 60) % 24, minute: startMinutes % 60);
        _endTime = suggestedEnd;
      }
      // The measured time of a sitting is given to one record only.
      if (!widget.isManual) _sittingTimeUsed = true;
    });

    showAppSuccess(
      context,
      context.l10n.pick(
        he: "נוסף. אפשר להזין עוד.",
        en: "Added. You can enter another record.",
      ),
    );
  }

  Future<void> _saveAndClose() async {
    if (!await _attemptSave()) return;
    try {
      await _storage.clearPendingEntry();
    } catch (_) {}
    if (!mounted) return;
    // Said before the route goes, not after: the messenger it reaches is the
    // app's and outlives this sheet either way, and saying it first means there
    // is no captured handle to get wrong.
    showAppSuccess(
      context,
      context.l10n.pick(
        he: "הנתונים נשמרו בהצלחה!",
        en: "Saved successfully",
      ),
    );
    Navigator.pop(context, _project);
  }

  Future<bool> _attemptSave() async {
    if (_saving || _project == null) return false;
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      // The recovery copy is written before validation and before history. A
      // rejected field and a disk failure therefore leave the exact form, and
      // a stopped timer, recoverable.
      await _storage.savePendingEntry(_draft());
      return await _save();
    } catch (error) {
      debugPrint('Pending entry save failed: $error');
      if (!mounted) return false;
      _showFormError(context.l10n.pick(
        he: 'לא ניתן לגשת לאחסון ולכן השמירה לא התחילה. אין לסגור את התוכנה לפני שמפנים מקום או מתקנים את הרשאת האחסון ומנסים שוב.',
        en: 'Storage is unavailable, so saving could not start. Do not close the app until space or storage access is restored and you try again.',
      ));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --- The form -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final title = widget.isManual
        ? context.l10n.pick(he: "הזנה ידנית", en: "Manual entry")
        : context.l10n.pick(he: "סיכום כתיבה", en: "Writing summary");
    final ready = _project != null;

    if (widget.asDialog) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
              controller: _scrollController, child: _body()),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _close,
            child: Text(context.l10n.cancel,
                style: TextStyle(color: SoferTokens.of(context).danger)),
          ),
          OutlinedButton(
            onPressed: ready && !_saving ? _saveAndContinue : null,
            child: Text(context.l10n.pick(he: "הוסף עוד", en: "Add another")),
          ),
          FilledButton(
            onPressed: ready && !_saving ? _saveAndClose : null,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    context.l10n.pick(he: "שמור וסגור", en: "Save and close")),
          ),
        ],
      );
    }

    return PopScope(
      // The back gesture asks too. Otherwise a swipe threw away the measured
      // time as silently as the old button did.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: context.l10n.cancel,
            onPressed: _saving ? null : _close,
          ),
        ),
        body: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: _body(),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: ready && !_saving ? _saveAndContinue : null,
                    child: Text(
                        context.l10n.pick(he: "הוסף עוד", en: "Add another")),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: ready && !_saving ? _saveAndClose : null,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(context.l10n.pick(he: "שמור", en: "Save")),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Which commission, what was written, and — optional, and last — when.
  ///
  /// The order is what has to be answered first. Recording only what was written
  /// and never how long it took is an ordinary way to work, so the time sits
  /// behind one line at the bottom instead of as a switch and two pickers above
  /// the field the writer actually opened the form to fill in.
  Widget _body() {
    final t = SoferTokens.of(context);
    final project = _project;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_formError != null) ...[
          Semantics(
            liveRegion: true,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: .1),
                border: Border.all(color: t.danger),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: t.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _formError!,
                      style: TextStyle(color: t.danger, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        SoferSectionTitle(context.l10n.pick(he: "הפרויקט", en: "Project"),
            padding: EdgeInsets.zero),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: widget.projects.isEmpty
                  ? Text(
                      context.l10n.pick(
                        he: "אין עדיין פרויקטים — אפשר לפתוח אחד כאן",
                        en: "No projects yet — create one here",
                      ),
                      style: TextStyle(color: t.inkMuted))
                  : DropdownButton<Project>(
                      hint: Text(context.l10n.pick(
                        he: "בחר פרויקט",
                        en: "Choose project",
                      )),
                      // Guarded: a project deleted on another screen would
                      // otherwise be a value with no matching item, which the
                      // dropdown asserts on.
                      value: widget.projects.contains(project) ? project : null,
                      isExpanded: true,
                      items: [
                        for (final p in widget.projects)
                          DropdownMenuItem(value: p, child: Text(p.name)),
                      ],
                      onChanged: (value) async {
                        setState(() {
                          _clearFields();
                          _project = value;
                          _loadWordPreferences();
                          if (value != null) _suggestSingleContinuation(value);
                        });
                        if (value != null) await _prefillPositionFrom(value);
                      },
                    ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: context.l10n.pick(he: "פרויקט חדש", en: "New project"),
              onPressed: _createProject,
            ),
          ],
        ),
        if (project != null) ...[
          const SizedBox(height: 20),
          SoferSectionTitle(
              context.l10n.pick(he: "מה נכתב", en: "What was written"),
              padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          _writtenFields(project),
        ],
        const SizedBox(height: 20),
        SoferSectionTitle(context.l10n.pick(he: "מתי", en: "When"),
            padding: EdgeInsets.zero),
        const SizedBox(height: 8),
        _whenRow(),
      ],
    );
  }

  /// One line saying when the work happened — and, in manual entry, one tap to
  /// change it.
  Widget _whenRow() {
    final t = SoferTokens.of(context);
    final box = BoxDecoration(
      border: Border.all(color: t.rule),
      borderRadius: BorderRadius.circular(t.panelRadius),
    );

    // A measured sitting states its time. There is nothing to choose here, and
    // the only thing worth saying is how long it was.
    if (!widget.isManual) {
      return Container(
        decoration: box,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 20, color: t.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _sittingTimeUsed
                    ? context.l10n.pick(
                        he: "זמן הישיבה כבר נרשם ברשומה הקודמת",
                        en: "The session time was already assigned to the previous record",
                      )
                    : context.l10n.pick(
                        he: "נמדדו ${formatClock(widget.measuredTime)}",
                        en: "Measured ${formatClock(widget.measuredTime)}",
                      ),
                style: TextStyle(fontSize: 14, color: t.ink),
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _editWhen,
      borderRadius: BorderRadius.circular(t.panelRadius),
      child: Container(
        decoration: box,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(_date == null ? Icons.event_busy : Icons.event,
                size: 20, color: _date == null ? t.inkMuted : t.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_whenSummary(),
                      style: TextStyle(fontSize: 14, color: t.ink)),
                  const SizedBox(height: 2),
                  Text(_whenNote(),
                      style: TextStyle(fontSize: 11, color: t.inkMuted)),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, size: 18, color: t.inkMuted),
          ],
        ),
      ),
    );
  }

  String _whenSummary() {
    final date = _date;
    if (date == null) {
      return context.l10n.pick(he: "ללא תאריך", en: "No date");
    }
    final label = formatDisplayDate(
      date,
      widget.useGregorianDates,
      english: context.l10n.isEnglish,
    );
    if (!_includeTime) return label;
    if (_byDuration) return "$label · ${formatClock(_worked)}";
    final nextDay = _clockEndsNextDay
        ? context.l10n.pick(he: " (למחרת)", en: " (next day)")
        : "";
    return "$label · ${_clockText(_startTime)}"
        "–${_clockText(_endTime)}$nextDay";
  }

  String _clockText(TimeOfDay time) =>
      "${time.hour.toString().padLeft(2, '0')}:"
      "${time.minute.toString().padLeft(2, '0')}";

  bool get _clockEndsNextDay {
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    return endMinutes < startMinutes;
  }

  Future<void> _pickClockTime({
    required bool isStart,
    required StateSetter setInner,
  }) async {
    final label = isStart
        ? context.l10n.pick(he: "שעת התחלה", en: "Start time")
        : context.l10n.pick(he: "שעת סיום", en: "End time");
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      helpText: label,
      cancelText: context.l10n.cancel,
      confirmText: context.l10n.confirm,
      builder: (pickerContext, child) => MediaQuery(
        data:
            MediaQuery.of(pickerContext).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setInner(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  String _whenNote() {
    final date = _date;
    if (date == null) {
      return context.l10n.pick(
        he: "יירשם כהספק בלבד — בלי רווח, ממוצע או יעד יומי",
        en: "Recorded as Output only — without profit, averages, or a daily target",
      );
    }
    if (!_includeTime) {
      return context.l10n.pick(
        he: "בלי שעות עבודה",
        en: "Without working hours",
      );
    }
    // The duration that will actually be saved. When the writer entered a
    // length rather than two clock times, this line went on computing the gap
    // between the two times anyway — so choosing two and a half hours showed
    // one, and the record saved the two and a half. The figure was right and
    // the confirmation of it was not, which is the worse way round.
    if (_byDuration) {
      return context.l10n.pick(
        he: "סה\"כ ${formatClock(_worked)}",
        en: "Total ${formatClock(_worked)}",
      );
    }
    final range = SessionLogic.buildTimeRange(
      date: date,
      startHour: _startTime.hour,
      startMinute: _startTime.minute,
      endHour: _endTime.hour,
      endMinute: _endTime.minute,
    );
    return context.l10n.pick(
      he: "סה\"כ ${formatClock(range.end.difference(range.start))}",
      en: "Total ${formatClock(range.end.difference(range.start))}",
    );
  }

  /// The date and the hours, behind one tap.
  Future<void> _editWhen() async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(context.l10n.pick(he: "מתי", en: "When")),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(child: _whenFields(setInner)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.pick(he: "סגור", en: "Close")),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _whenFields(StateSetter setInner) {
    final hasDate = _date != null;
    final t = SoferTokens.of(context);

    String durationText = "";
    if (hasDate && _includeTime) {
      if (_byDuration) {
        durationText = context.l10n.pick(
          he: "זמן כתיבה: ${formatSpanLong(_worked)}",
          en: "Writing time: ${formatSpanLong(_worked)}",
        );
      } else {
        final range = SessionLogic.buildTimeRange(
          date: _date!,
          startHour: _startTime.hour,
          startMinute: _startTime.minute,
          endHour: _endTime.hour,
          endMinute: _endTime.minute,
        );
        durationText = context.l10n.pick(
          he: "סה\"כ זמן מחושב: ${formatSpanLong(range.end.difference(range.start))}",
          en: "Calculated total: ${formatSpanLong(range.end.difference(range.start))}",
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasDate)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10n.pick(
                he: "ללא תאריך = גיבוי להספק בלבד (לא ייכנס בממוצעים, רווח או יעד יומי).",
                en: "No date means an Output-only backlog record; it is excluded from averages, profit, and the daily target.",
              ),
              style: TextStyle(
                  fontSize: 12, color: t.inkMuted, fontStyle: FontStyle.italic),
            ),
          ),
        SwitchListTile(
          title: Text(context.l10n.pick(
            he: "חישוב זמן כתיבה",
            en: "Include writing time",
          )),
          value: hasDate && _includeTime,
          onChanged: hasDate ? (v) => setInner(() => _includeTime = v) : null,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (!hasDate)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
                context.l10n.pick(
                    he: "שעות כתיבה זמינות רק לאחר בחירת תאריך.",
                    en: "Writing time is available after selecting a date."),
                style: TextStyle(fontSize: 12, color: t.caution)),
          ),
        if (hasDate && _includeTime) ...[
          // A length or a stretch of the clock. Two answers to one question,
          // and only the second knows *when* — see `timeOfDayKnown`.
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                  value: true,
                  label: Text(context.l10n.pick(he: "משך", en: "Duration"))),
              ButtonSegment(
                  value: false,
                  label: Text(context.l10n.pick(
                    he: "משעה עד שעה",
                    en: "Start and end time",
                  ))),
            ],
            selected: {_byDuration},
            onSelectionChanged: (v) => setInner(() => _byDuration = v.first),
          ),
          const SizedBox(height: 6),
          if (_byDuration)
            SizedBox(
              height: 132,
              child: CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.hm,
                initialTimerDuration: _worked,
                // Five-minute steps. A sofer reporting his own morning is not
                // accurate to the minute, and offering sixty of them to scroll
                // through is offering precision nobody has.
                minuteInterval: 5,
                onTimerDurationChanged: (d) => setInner(() => _worked = d),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _pickClockTime(isStart: true, setInner: setInner),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(context.l10n.pick(
                            he: "שעת התחלה",
                            en: "Start time",
                          )),
                          const SizedBox(height: 2),
                          Text(_clockText(_startTime),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        _pickClockTime(isStart: false, setInner: setInner),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(_clockEndsNextDay
                              ? context.l10n.pick(
                                  he: "שעת סיום (למחרת)",
                                  en: "End time (next day)",
                                )
                              : context.l10n.pick(
                                  he: "שעת סיום",
                                  en: "End time",
                                )),
                          const SizedBox(height: 2),
                          Text(_clockText(_endTime),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
        Text(durationText,
            style: TextStyle(
                fontSize: 12, color: t.accent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(context.l10n.pick(he: "תאריך: ", en: "Date: ")),
            TextButton(
              onPressed: () => _pickHebrewDate(setInner),
              child: Text(_date == null
                  ? context.l10n.pick(
                      he: "ללא תאריך (כללי)",
                      en: "No date (general)",
                    )
                  : formatDisplayDate(
                      _date!,
                      widget.useGregorianDates,
                      english: context.l10n.isEnglish,
                    )),
            ),
            if (_date != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setInner(() => _date = null),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickHebrewDate(StateSetter setInner) async {
    final jewishDate = JewishDate.fromDateTime(_date ?? DateTime.now());

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setPicker) {
          final year = jewishDate.getJewishYear();
          final month = jewishDate.getJewishMonth();
          final day = jewishDate.getJewishDayOfMonth();
          final isLeap = jewishDate.isJewishLeapYear();

          final years = List.generate(21, (i) => (year - 10) + i);
          final months = isLeap
              ? [7, 8, 9, 10, 11, 12, 13, 1, 2, 3, 4, 5, 6]
              : [7, 8, 9, 10, 11, 12, 1, 2, 3, 4, 5, 6];
          final days =
              List.generate(jewishDate.getDaysInJewishMonth(), (i) => i + 1);

          return AlertDialog(
            title: Text(context.l10n.pick(
              he: "בחר תאריך עברי",
              en: "Choose a Hebrew date",
            )),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<int>(
                  value: years.contains(year) ? year : years.first,
                  items: [
                    for (final y in years)
                      DropdownMenuItem(
                        value: y,
                        child: Text(context.l10n.isEnglish
                            ? y.toString()
                            : formatHebrewYear(y)),
                      )
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final probe = JewishDate()..setJewishDate(value, 1, 1);
                    // Adar II exists only in a leap year; a year without one
                    // takes the writer back to Adar.
                    final newMonth =
                        !probe.isJewishLeapYear() && month == 13 ? 12 : month;
                    probe.setJewishDate(value, newMonth, 1);
                    final maxDays = probe.getDaysInJewishMonth();
                    jewishDate.setJewishDate(
                        value, newMonth, day > maxDays ? maxDays : day);
                    setPicker(() {});
                  },
                ),
                DropdownButton<int>(
                  value: months.contains(month) ? month : 1,
                  items: [
                    for (final m in months)
                      DropdownMenuItem(
                        value: m,
                        child: Text(_jewishMonthName(m, year, isLeap)),
                      )
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    jewishDate.setJewishDate(year, value, 1);
                    final maxDays = jewishDate.getDaysInJewishMonth();
                    jewishDate.setJewishDate(
                        year, value, day > maxDays ? maxDays : day);
                    setPicker(() {});
                  },
                ),
                DropdownButton<int>(
                  value: days.contains(day) ? day : 1,
                  items: [
                    for (final d in days)
                      DropdownMenuItem(
                        value: d,
                        child: Text(context.l10n.isEnglish
                            ? d.toString()
                            : formatHebrewNumber(d)),
                      )
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    jewishDate.setJewishDate(year, month, value);
                    setPicker(() {});
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () {
                  setInner(() => _date = jewishDate.getGregorianCalendar());
                  Navigator.pop(ctx);
                },
                child: Text(context.l10n.pick(he: "בחר", en: "Select")),
              ),
            ],
          );
        },
      ),
    );
  }

  String _jewishMonthName(int month, int year, bool isLeap) {
    if (!context.l10n.isEnglish) return getHebrewMonthName(month, isLeap);
    final date = JewishDate()..setJewishDate(year, month, 1);
    final formatter = HebrewDateFormatter()..hebrewFormat = false;
    return formatter.format(date, pattern: 'MM');
  }

  /// The fields that differ by what kind of work the commission is.
  Widget _writtenFields(Project project) {
    final t = SoferTokens.of(context);

    if (project.type.isPaged) {
      return Column(
        children: [
          Text(
              context.l10n.pick(
                  he: "מעמוד (אותיות או מספר) עד עמוד (אופציונלי – ריק = עמוד בודד)",
                  en: "From page (Hebrew letters or number) to page (optional; blank means one page)"),
              style: TextStyle(fontSize: 12, color: t.inkMuted)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pageCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.pick(he: "מעמוד", en: "From page"),
                    prefixIcon: const Icon(Icons.auto_stories),
                    hintText: context.l10n.pick(
                      he: "למשל: א או 1",
                      en: "For example: א or 1",
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _pageToCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.pick(he: "עד עמוד", en: "To page"),
                    hintText: context.l10n.pick(
                      he: "ריק = עמוד בודד",
                      en: "Blank means one page",
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lineFromCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.pick(he: "משורה", en: "From line"),
                    prefixIcon: const Icon(Icons.vertical_align_top),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lineToCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.pick(he: "עד שורה", en: "To line"),
                    prefixIcon: const Icon(Icons.vertical_align_bottom),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (project.type == ProjectType.mezuza) {
      final stopped = MezuzaState.slots(project, _history)
          .where((slot) => slot.state == MezuzaSlotState.partial)
          .toList();
      MezuzaSlot? selected;
      for (final slot in stopped) {
        if (slot.index == _mezuzaIndex) selected = slot;
      }

      return Column(
        children: [
          if (stopped.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              key: ValueKey(_mezuzaIndex ?? 0),
              initialValue: _mezuzaIndex ?? 0,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.pick(
                  he: "מה נכתב",
                  en: "What was written",
                ),
                prefixIcon: const Icon(Icons.history),
              ),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(context.l10n.pick(
                    he: "התחל מזוזה חדשה / דווח מזוזות שלמות",
                    en: "Start a new Mezuzah / report complete Mezuzot",
                  )),
                ),
                for (final slot in stopped)
                  DropdownMenuItem(
                    value: slot.index,
                    child: Text(context.l10n.pick(
                      he: "המשך מזוזה ${slot.index} — משורה ${slot.resumeLine}",
                      en: "Continue Mezuzah ${slot.index} — from line ${slot.resumeLine}",
                    )),
                  ),
              ],
              onChanged: (value) => setState(() {
                _mezuzaIndex = value == 0 ? null : value;
                _amountCtrl.clear();
                // Completing it is the common case; the writer can replace 22
                // when this sitting stopped part-way again.
                _partialLineCtrl.text = value == 0 ? "" : "22";
              }),
            ),
            const SizedBox(height: 10),
          ],
          if (selected == null)
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.pick(
                  he: "כמות מזוזות",
                  en: "Number of Mezuzot",
                ),
                prefixIcon: const Icon(Icons.numbers),
              ),
            )
          else
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.l10n.pick(
                  he: "במזוזה ${selected.index} נכתבו ${selected.linesWritten} מתוך 22 שורות. ממשיכים משורה ${selected.resumeLine}.",
                  en: "Mezuzah ${selected.index} has ${selected.linesWritten} of 22 lines. Continue from line ${selected.resumeLine}.",
                ),
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _partialLineCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: selected == null
                  ? context.l10n.pick(
                      he: "עד שורה (אופציונלי)",
                      en: "To line (optional)",
                    )
                  : context.l10n.pick(
                      he: "עד איזו שורה הגעת עכשיו",
                      en: "Last line reached now",
                    ),
              prefixIcon: const Icon(Icons.format_align_left),
              hintText: selected == null
                  ? context.l10n.pick(
                      he: "השאר ריק למזוזה שלמה",
                      en: "Leave blank for a complete Mezuzah",
                    )
                  : context.l10n.pick(
                      he: "עד שורה 22",
                      en: "Up to line 22",
                    ),
            ),
          ),
        ],
      );
    }

    final tefillinContinuations =
        TefillinState.continuations(project, _history);
    TefillinSlot? continuing;
    for (final slot in tefillinContinuations) {
      if (_tefillinKey(slot) == _tefillinContinuationKey) continuing = slot;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.pick(
                he: 'הזנה לפי המילה האחרונה',
                en: 'Record the last completed word')),
            value: _tefillinWords,
            onChanged: _wordSlot(project)?.wordBoundary != null
                ? null
                : (v) => setState(() {
                      _tefillinWords = v;
                      _untilWord = null;
                      _baselineWord = null;
                      if (v) _tefillinMode = 'parshiya';
                    })),
        if (_tefillinWords) ...[
          DropdownButtonFormField<StamScript>(
              initialValue: _tefillinScript,
              key: ValueKey('script-${_tefillinScript.id}'),
              decoration: InputDecoration(
                  labelText: context.l10n
                      .pick(he: 'כתב לפרשייה', en: 'Parashah script')),
              items: [
                for (final s in StamScript.values)
                  DropdownMenuItem(value: s, child: Text(s.label))
              ],
              onChanged: (v) => setState(() => _tefillinScript = v!)),
          const SizedBox(height: 10),
        ],
        if (tefillinContinuations.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            key:
                ValueKey(continuing == null ? 'new' : _tefillinKey(continuing)),
            initialValue: continuing == null ? 'new' : _tefillinKey(continuing),
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.l10n.pick(
                he: 'המשך כתיבה או כתיבה חדשה',
                en: 'Continue writing or start new work',
              ),
              prefixIcon: const Icon(Icons.history),
            ),
            items: [
              DropdownMenuItem(
                value: 'new',
                child: Text(context.l10n.pick(
                  he: 'התחל יחידת תפילין חדשה',
                  en: 'Start a new Tefillin unit',
                )),
              ),
              for (final slot in tefillinContinuations)
                DropdownMenuItem(
                  value: _tefillinKey(slot),
                  child: Text(context.l10n.pick(
                    he: 'המשך ${slot.parshiyaName} של ${slot.side == TefillinSide.head ? 'ראש' : 'יד'}, זוג ${slot.pair}${slot.wordBoundary != null ? ' — אחרי מילה ${slot.wordBoundary}' : _tefillinWords ? '' : ' — משורה ${slot.linesWritten + 1}'}',
                    en: 'Continue ${slot.parshiyaName}, ${slot.side == TefillinSide.head ? 'Shel Rosh' : 'Shel Yad'}, set ${slot.pair}${slot.wordBoundary != null ? ' — after word ${slot.wordBoundary}' : _tefillinWords ? '' : ' — from line ${slot.linesWritten + 1}'}',
                  )),
                ),
            ],
            onChanged: (value) => setState(() {
              if (value == null) return;
              if (value == 'new') {
                _clearTefillinContinuation();
                _pairCtrl.clear();
                _partialLineCtrl.clear();
                return;
              }
              final slot = tefillinContinuations
                  .firstWhere((candidate) => _tefillinKey(candidate) == value);
              _selectTefillinContinuation(slot);
            }),
          ),
          const SizedBox(height: 10),
        ],
        if (continuing != null && !_tefillinWords) ...[
          SoferPanel(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                context.l10n.pick(
                  he: continuing.state == SlotState.empty
                      ? 'המשך הסט: פרשיית ${continuing.parshiyaName} של ${continuing.side == TefillinSide.head ? 'ראש' : 'יד'}, זוג ${continuing.pair}, משורה 1.'
                      : 'בפרשיית ${continuing.parshiyaName} של ${continuing.side == TefillinSide.head ? 'ראש' : 'יד'}, זוג ${continuing.pair}, נכתבו ${continuing.linesWritten} מתוך ${TefillinUnits.linesIn(continuing.side)} שורות. ההזנה הנוכחית תתחיל משורה ${continuing.linesWritten + 1}.',
                  en: continuing.state == SlotState.empty
                      ? 'Continue this set: ${continuing.parshiyaName}, ${continuing.side == TefillinSide.head ? 'Shel Rosh' : 'Shel Yad'}, set ${continuing.pair}, from line 1.'
                      : '${continuing.parshiyaName}, ${continuing.side == TefillinSide.head ? 'Shel Rosh' : 'Shel Yad'}, set ${continuing.pair}, has ${continuing.linesWritten} of ${TefillinUnits.linesIn(continuing.side)} lines. This entry starts at line ${continuing.linesWritten + 1}.',
                ),
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (!_tefillinWords)
          DropdownButton<String>(
            value: _tefillinMode,
            isExpanded: true,
            items: [
              DropdownMenuItem(
                  value: 'set',
                  child: Text(context.l10n.pick(
                    he: "זוג שלם (ראש+יד)",
                    en: "Complete Tefillin Set (Shel Rosh + Shel Yad)",
                  ))),
              DropdownMenuItem(
                  value: 'head',
                  child: Text(context.l10n.pick(
                    he: "תפילין של ראש (4 פרשיות)",
                    en: "Tefillin Shel Rosh (4 Parashiyot)",
                  ))),
              DropdownMenuItem(
                  value: 'hand',
                  child: Text(context.l10n.pick(
                    he: "תפילין של יד (4 פרשיות)",
                    en: "Tefillin Shel Yad (4 Parashiyot)",
                  ))),
              DropdownMenuItem(
                  value: 'parshiya',
                  child: Text(context.l10n.pick(
                    he: "פרשייה בודדת (ראש/יד)",
                    en: "Single Parashah (Shel Rosh / Shel Yad)",
                  ))),
            ],
            onChanged: continuing != null
                ? null
                : (v) => setState(() {
                      _clearTefillinContinuation();
                      _tefillinMode = v!;
                    }),
          ),
        const SizedBox(height: 10),
        if (_tefillinMode == 'parshiya' || _tefillinWords) ...[
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _tefillinPart,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(
                        value: 'head',
                        child: Text(context.l10n.pick(
                          he: "תפילין של ראש",
                          en: "Tefillin Shel Rosh",
                        ))),
                    DropdownMenuItem(
                        value: 'hand',
                        child: Text(context.l10n.pick(
                          he: "תפילין של יד",
                          en: "Tefillin Shel Yad",
                        ))),
                  ],
                  onChanged: continuing != null
                      ? null
                      : (v) => setState(() {
                            _clearTefillinContinuation();
                            _tefillinPart = v!;
                          }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<int>(
                  value: _tefillinParshiya,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 1, child: Text("1. קדש")),
                    DropdownMenuItem(value: 2, child: Text("2. והיה כי יביאך")),
                    DropdownMenuItem(value: 3, child: Text("3. שמע")),
                    DropdownMenuItem(value: 4, child: Text("4. והיה אם שמע")),
                  ],
                  onChanged: continuing != null
                      ? null
                      : (v) => setState(() {
                            _clearTefillinContinuation();
                            _tefillinParshiya = v!;
                          }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pairCtrl,
                  enabled: continuing == null,
                  onChanged: (_) =>
                      setState(() => _clearTefillinContinuation()),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.pick(
                      he: "זוג מספר (חובה)",
                      en: "Set number (required)",
                    ),
                    prefixIcon: const Icon(Icons.tag),
                    // Without a pair the parshiya has a name and no address,
                    // and the board can only guess where to put it.
                    hintText: context.l10n.pick(
                      he: "למשל 4",
                      en: "For example, 4",
                    ),
                  ),
                ),
              ),
              if (!_tefillinWords) const SizedBox(width: 10),
              if (!_tefillinWords)
                Expanded(
                  child: TextField(
                    controller: _partialLineCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText:
                          context.l10n.pick(he: "עד שורה", en: "To line"),
                      prefixIcon: const Icon(Icons.format_align_left),
                      hintText: _tefillinPart == 'head'
                          ? context.l10n.pick(he: "מתוך 4", en: "Out of 4")
                          : context.l10n.pick(he: "מתוך 7", en: "Out of 7"),
                    ),
                  ),
                ),
            ],
          ),
          if (_tefillinWords) ...[
            const SizedBox(height: 12),
            if (_wordSlot(project)?.wordBoundary case final int boundary)
              Text(context.l10n.pick(
                  he: 'מילה אחרונה שנשמרה: ${TefillinText.of(_tefillinParshiya).wordAt(boundary)} ($boundary)',
                  en: 'Last saved word: ${TefillinText.of(_tefillinParshiya).wordAt(boundary)} ($boundary)')),
            if (_untilWord != null)
              Text(context.l10n.pick(
                  he: 'עד מילה $_untilWord: ${TefillinText.of(_tefillinParshiya).wordAt(_untilWord!)}',
                  en: 'Through word $_untilWord: ${TefillinText.of(_tefillinParshiya).wordAt(_untilWord!)}')),
            OutlinedButton.icon(
                onPressed: _saving ? null : () => _chooseLastWord(project),
                icon: const Icon(Icons.touch_app),
                label: Text(context.l10n.pick(
                    he: 'פתח פרשייה וסמן מילה',
                    en: 'Open Parashah and select word'))),
          ],
        ] else ...[
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.pick(
                he: "כמות יחידות",
                en: "Number of units",
              ),
              prefixIcon: const Icon(Icons.numbers),
            ),
          ),
        ],
      ],
    );
  }
}
