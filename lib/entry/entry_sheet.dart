import 'package:flutter/cupertino.dart'
    show CupertinoTimerPicker, CupertinoTimerPickerMode;
import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';

import '../format.dart';
import '../hebrew_utils.dart';
import '../logic/date_logic.dart';
import '../logic/entry_builder.dart';
import '../logic/hebrew_clock.dart';
import '../logic/session_logic.dart';
import '../models.dart';
import '../projects_screen.dart' show ProjectDialog;
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';
import '../widgets/sofer_widgets.dart';
import '../widgets/confirm.dart';

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

  const EntrySave({
    required this.project,
    required this.sessions,
    required this.reachedPage,
    required this.reachedLine,
    required this.backlogOnly,
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
  required void Function(Project project) onProjectCreated,
  required Future<void> Function(EntrySave save) onSave,
  Project? initialProject,
  Duration measuredTime = Duration.zero,
  DateTime? measuredEnd,
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
  final void Function(Project project) onProjectCreated;
  final Future<void> Function(EntrySave save) onSave;
  final Project? initialProject;
  final Duration measuredTime;
  final DateTime? measuredEnd;

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
  });

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final StorageService _storage = StorageService();

  Project? _project;

  final _pageCtrl = TextEditingController();
  final _pageToCtrl = TextEditingController();
  final _lineFromCtrl = TextEditingController();
  final _lineToCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _partialLineCtrl = TextEditingController();

  /// Which pair of the commission a parshiya belongs to. Left blank it falls
  /// into the first free slot, which is what the app did before pairs existed.
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

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
    if (_project == null) _restoreLastProject();
    // Today, for both paths. It used to open blank for a manual entry, so
    // every single record began by asking a writer what day it was — and the
    // overwhelmingly common answer is the one the device already knows. The
    // date row still opens a picker, and "no date" is still in it for backlog.
    _date = DateLogic.effectiveDate(DateTime.now(), widget.dayStart);
    final project = _project;
    if (project != null) _prefillPositionFrom(project);
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
    super.dispose();
  }

  /// Empties every field of the form.
  void _clearFields() {
    _pageCtrl.clear();
    _pageToCtrl.clear();
    _lineFromCtrl.clear();
    _lineToCtrl.clear();
    _amountCtrl.clear();
    _partialLineCtrl.clear();
    _prefilledPage = '';
    _prefilledLine = '';
  }

  /// Offers where the writer left off, as a starting point they can change.
  ///
  /// The position is stored per commission and kept in step by manual entries as
  /// well as by the smart workflow, so it is the same answer smart mode resumes
  /// from. Only a sefer has one: mezuzot and tefillin are counted rather than
  /// paginated, and there is nothing there to suggest.
  Future<void> _prefillPositionFrom(Project project) async {
    if (project.type != ProjectType.sefer) return;
    final position = await _storage.getLastPosition(project.id);
    if (!mounted || position.isEmpty) return;
    final page = ((position['page'] as int?) ?? 1).clamp(1, 1 << 20);
    final line = ((position['line'] as int?) ?? 1).clamp(1, 1 << 20);
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
      setState(() => _project = p);
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
  void _createProject() {
    showDialog(
      context: context,
      builder: (_) => ProjectDialog(
        useGregorianDates: widget.useGregorianDates,
        onSave: (project) {
          widget.onProjectCreated(project);
          setState(() => _project = project);
        },
      ),
    );
  }

  /// Asks before an entry is thrown away.
  ///
  /// The button read "מחיקה / ביטול" and did neither of them — it closed. After a
  /// timed sitting that discards, without a word, the one thing on the form that
  /// cannot simply be typed in again: the time the app just measured.
  Future<bool> _confirmDiscard() async {
    final touched = _pageToCtrl.text.trim().isNotEmpty ||
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
      title: "לבטל את ההזנה?",
      message: widget.isManual
          ? "מה שהוזן כאן לא יישמר."
          : "זמן העבודה שנמדד — ${formatClock(widget.measuredTime)} — "
              "לא יישמר, ואי אפשר לשחזר אותו.",
      cancelLabel: "המשך בהזנה",
      confirmLabel: "בטל את ההזנה",
      danger: true,
    );
    return confirmed;
  }

  Future<void> _close() async {
    if (!await _confirmDiscard()) return;
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
        tefillinMode: _tefillinMode,
        tefillinPart: _tefillinPart,
        tefillinParshiya: _tefillinParshiya,
        tefillinPair: _pairCtrl.text,
      ),
      history: widget.history,
    );

    switch (outcome) {
      case EntryRejected(:final message):
        showAppError(context, message);
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
        await widget.onSave(EntrySave(
          project: project,
          sessions: sessions,
          reachedPage: reachedPage,
          reachedLine: reachedLine,
          backlogOnly: backlogOnly,
        ));
        // Remembered for the next entry, so the list is not asked again.
        await _storage.setLastProjectId(project.id);
        return true;
    }
  }

  Future<bool> _confirmOverlap(bool isRange) =>
      confirmOverlap(context, range: isRange);

  /// Saves and stays, so a day recorded in parts is one sitting at the keyboard
  /// rather than a form opened and closed for every stretch of it.
  Future<void> _saveAndContinue() async {
    if (!await _save()) return;
    if (!mounted) return;

    final project = _project;
    _clearFields();
    // The stored position moved on with the entry, so the next record is
    // offered starting where this one ended.
    if (project != null) await _prefillPositionFrom(project);
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

    showAppSuccess(context, "נוסף. אפשר להזין עוד.");
  }

  Future<void> _saveAndClose() async {
    if (!await _save()) return;
    if (!mounted) return;
    // Said before the route goes, not after: the messenger it reaches is the
    // app's and outlives this sheet either way, and saying it first means there
    // is no captured handle to get wrong.
    showAppSuccess(context, "הנתונים נשמרו בהצלחה!");
    Navigator.pop(context, _project);
  }

  // --- The form -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final title = widget.isManual ? "הזנה ידנית" : "סיכום כתיבה";
    final ready = _project != null;

    if (widget.asDialog) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(child: _body()),
        ),
        actions: [
          TextButton(
            onPressed: _close,
            child: Text("ביטול",
                style: TextStyle(color: SoferTokens.of(context).danger)),
          ),
          OutlinedButton(
            onPressed: ready ? _saveAndContinue : null,
            child: const Text("הוסף עוד"),
          ),
          FilledButton(
            onPressed: ready ? _saveAndClose : null,
            child: const Text("שמור וסגור"),
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
            tooltip: "ביטול",
            onPressed: _close,
          ),
        ),
        body: SingleChildScrollView(
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
                    onPressed: ready ? _saveAndContinue : null,
                    child: const Text("הוסף עוד"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: ready ? _saveAndClose : null,
                    child: const Text("שמור"),
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
        const SoferSectionTitle("הפרויקט", padding: EdgeInsets.zero),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: widget.projects.isEmpty
                  ? Text("אין עדיין פרויקטים — אפשר לפתוח אחד כאן",
                      style: TextStyle(color: t.inkMuted))
                  : DropdownButton<Project>(
                      hint: const Text("בחר פרויקט"),
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
                        });
                        if (value != null) await _prefillPositionFrom(value);
                      },
                    ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: "פרויקט חדש",
              onPressed: _createProject,
            ),
          ],
        ),
        if (project != null) ...[
          const SizedBox(height: 20),
          const SoferSectionTitle("מה נכתב", padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          _writtenFields(project),
        ],
        const SizedBox(height: 20),
        const SoferSectionTitle("מתי", padding: EdgeInsets.zero),
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
                    ? "זמן הישיבה כבר נרשם ברשומה הקודמת"
                    : "נמדדו ${formatClock(widget.measuredTime)}",
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
    if (date == null) return "ללא תאריך";
    final label = formatDisplayDate(date, widget.useGregorianDates);
    if (!_includeTime) return label;
    if (_byDuration) return "$label · ${formatClock(_worked)}";
    final nextDay = _clockEndsNextDay ? " (למחרת)" : "";
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
    final label = isStart ? "שעת התחלה" : "שעת סיום";
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      helpText: label,
      cancelText: "ביטול",
      confirmText: "אישור",
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
      return "יירשם כהספק בלבד — בלי רווח, ממוצע או יעד יומי";
    }
    if (!_includeTime) return "בלי שעות עבודה";
    // The duration that will actually be saved. When the writer entered a
    // length rather than two clock times, this line went on computing the gap
    // between the two times anyway — so choosing two and a half hours showed
    // one, and the record saved the two and a half. The figure was right and
    // the confirmation of it was not, which is the worse way round.
    if (_byDuration) return "סה\"כ ${formatClock(_worked)}";
    final range = SessionLogic.buildTimeRange(
      date: date,
      startHour: _startTime.hour,
      startMinute: _startTime.minute,
      endHour: _endTime.hour,
      endMinute: _endTime.minute,
    );
    return "סה\"כ ${formatClock(range.end.difference(range.start))}";
  }

  /// The date and the hours, behind one tap.
  Future<void> _editWhen() async {
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text("מתי"),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(child: _whenFields(setInner)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("סגור"),
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
        durationText = "זמן כתיבה: ${formatSpanLong(_worked)}";
      } else {
        final range = SessionLogic.buildTimeRange(
          date: _date!,
          startHour: _startTime.hour,
          startMinute: _startTime.minute,
          endHour: _endTime.hour,
          endMinute: _endTime.minute,
        );
        durationText =
            "סה\"כ זמן מחושב: ${formatSpanLong(range.end.difference(range.start))}";
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasDate)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              "ללא תאריך = גיבוי להספק בלבד (לא ייכנס בממוצעים, רווח או יעד יומי).",
              style: TextStyle(
                  fontSize: 12, color: t.inkMuted, fontStyle: FontStyle.italic),
            ),
          ),
        SwitchListTile(
          title: const Text("חישוב זמן כתיבה"),
          value: hasDate && _includeTime,
          onChanged: hasDate ? (v) => setInner(() => _includeTime = v) : null,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (!hasDate)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text("שעות כתיבה זמינות רק לאחר בחירת תאריך.",
                style: TextStyle(fontSize: 12, color: t.caution)),
          ),
        if (hasDate && _includeTime) ...[
          // A length or a stretch of the clock. Two answers to one question,
          // and only the second knows *when* — see `timeOfDayKnown`.
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text("משך")),
              ButtonSegment(value: false, label: Text("משעה עד שעה")),
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
                          const Text("שעת התחלה"),
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
                              ? "שעת סיום (למחרת)"
                              : "שעת סיום"),
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
            const Text("תאריך: "),
            TextButton(
              onPressed: () => _pickHebrewDate(setInner),
              child: Text(_date == null
                  ? "ללא תאריך (כללי)"
                  : formatDisplayDate(_date!, widget.useGregorianDates)),
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
            title: const Text("בחר תאריך עברי"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<int>(
                  value: years.contains(year) ? year : years.first,
                  items: [
                    for (final y in years)
                      DropdownMenuItem(
                          value: y, child: Text(formatHebrewYear(y)))
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
                          value: m, child: Text(getHebrewMonthName(m, isLeap)))
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
                          value: d, child: Text(formatHebrewNumber(d)))
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
                child: const Text("ביטול"),
              ),
              ElevatedButton(
                onPressed: () {
                  setInner(() => _date = jewishDate.getGregorianCalendar());
                  Navigator.pop(ctx);
                },
                child: const Text("בחר"),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The fields that differ by what kind of work the commission is.
  Widget _writtenFields(Project project) {
    final t = SoferTokens.of(context);

    if (project.type == ProjectType.sefer) {
      return Column(
        children: [
          Text("מעמוד (אותיות או מספר) עד עמוד (אופציונלי – ריק = עמוד בודד)",
              style: TextStyle(fontSize: 12, color: t.inkMuted)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pageCtrl,
                  decoration: const InputDecoration(
                    labelText: "מעמוד",
                    prefixIcon: Icon(Icons.auto_stories),
                    hintText: "למשל: א או 1",
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _pageToCtrl,
                  decoration: const InputDecoration(
                    labelText: "עד עמוד",
                    hintText: "ריק = עמוד בודד",
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
                  decoration: const InputDecoration(
                    labelText: "משורה",
                    prefixIcon: Icon(Icons.vertical_align_top),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lineToCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "עד שורה",
                    prefixIcon: Icon(Icons.vertical_align_bottom),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (project.type == ProjectType.mezuza) {
      return Column(
        children: [
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "כמות מזוזות",
              prefixIcon: Icon(Icons.numbers),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _partialLineCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "עד שורה (אופציונלי)",
              prefixIcon: Icon(Icons.format_align_left),
              hintText: "השאר ריק למזוזה שלמה",
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          value: _tefillinMode,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'set', child: Text("זוג שלם (ראש+יד)")),
            DropdownMenuItem(
                value: 'head', child: Text("תפילין של ראש (4 פרשיות)")),
            DropdownMenuItem(
                value: 'hand', child: Text("תפילין של יד (4 פרשיות)")),
            DropdownMenuItem(
                value: 'parshiya', child: Text("פרשייה בודדת (ראש/יד)")),
          ],
          onChanged: (v) => setState(() => _tefillinMode = v!),
        ),
        const SizedBox(height: 10),
        if (_tefillinMode == 'parshiya') ...[
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _tefillinPart,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'head', child: Text("תפילין של ראש")),
                    DropdownMenuItem(
                        value: 'hand', child: Text("תפילין של יד")),
                  ],
                  onChanged: (v) => setState(() => _tefillinPart = v!),
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
                  onChanged: (v) => setState(() => _tefillinParshiya = v!),
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
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "זוג מספר (חובה)",
                    prefixIcon: Icon(Icons.tag),
                    // Without a pair the parshiya has a name and no address,
                    // and the board can only guess where to put it.
                    hintText: "למשל 4",
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _partialLineCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "עד שורה",
                    prefixIcon: const Icon(Icons.format_align_left),
                    hintText: _tefillinPart == 'head' ? "מתוך 4" : "מתוך 7",
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "כמות יחידות",
              prefixIcon: Icon(Icons.numbers),
            ),
          ),
        ],
      ],
    );
  }
}
