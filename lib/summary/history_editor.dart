import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../hebrew_utils.dart';
import '../logic/date_logic.dart';
import '../logic/hebrew_clock.dart';
import '../logic/production_calculator.dart';
import '../logic/session_logic.dart';
import '../models.dart';
import '../logic/tefillin_units.dart';
import '../logic/tefillin_state.dart';
import '../logic/tefillin_text.dart';
import '../entry/tefillin_words_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm.dart';
import '../widgets/feedback.dart';
import '../l10n/app_localizations.dart';

/// Correcting what was recorded.
///
/// The one place in the app where history can be changed after the fact, which
/// makes it the one place where a slip costs a writer work they actually did.
/// It lived inside the summary screen as three hundred and fifty lines of
/// dialogs threaded through a `StatefulBuilder`, sharing that screen's state
/// and its helpers, and none of it could be reached without opening a summary
/// first.
///
/// [history] is the whole list, tombstones included; [onHistoryUpdated] is
/// handed the whole list back. Deleting marks a record rather than dropping it,
/// because a record that is merely absent is a record another device puts back
/// at the next merge.
Future<void> showHistoryEditor({
  required BuildContext context,
  required List<Project> projects,
  required List<WorkSession> history,
  required DateTime day,
  required String dayLabel,
  required DayStart dayStart,
  required bool useGregorianDates,
  required FutureOr<void> Function(List<WorkSession>) onHistoryUpdated,
  String? initialProjectId,
  bool startWithAllDays = false,
}) {
  final selectedIds = <String>{};
  // Starts on the selected day, which is the common case, but the editor can
  // switch to the full history.
  var showAllDays = startWithAllDays;
  var projectFilter = initialProjectId ?? '';

  List<WorkSession> listed() {
    final live = history.where((s) => !s.isDeleted);
    final sessions = showAllDays
        ? (live.toList()..sort((a, b) => b.startTime.compareTo(a.startTime)))
        : live
            .where((s) => DateLogic.sessionIsOnDay(s, day, dayStart))
            .toList();
    if (projectFilter.isEmpty) return sessions;
    return sessions.where((s) => s.projectId == projectFilter).toList();
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (context, setSheetState) {
        final sessions = listed();

        return DraggableScrollableSheet(
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              AppBar(
                title: Text(showAllDays
                    ? context.l10n.pick(
                        he: "עריכת רשומות – כל הימים",
                        en: "Edit records — all days")
                    : context.l10n.pick(
                        he: "עריכת רשומות – יום נבחר",
                        en: "Edit records — selected day")),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(dayLabel),
                          icon: const Icon(Icons.today, size: 18),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(context.l10n
                              .pick(he: "כל הימים", en: "All days")),
                          icon: const Icon(Icons.all_inbox, size: 18),
                        ),
                      ],
                      selected: {showAllDays},
                      onSelectionChanged: (v) => setSheetState(() {
                        showAllDays = v.first;
                        // Selections refer to rows that may no longer be
                        // listed, so clear them when the view changes.
                        selectedIds.clear();
                      }),
                    ),
                    if (showAllDays && projects.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: DropdownButtonFormField<String>(
                          initialValue: projectFilter,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: context.l10n.pick(
                                he: "סינון לפי פרויקט",
                                en: "Filter by project"),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem(
                                value: '',
                                child: Text(context.l10n.pick(
                                    he: "כל הפרויקטים", en: "All projects"))),
                            ...projects.map((p) => DropdownMenuItem(
                                value: p.id, child: Text(p.name))),
                          ],
                          onChanged: (v) => setSheetState(() {
                            projectFilter = v ?? '';
                            selectedIds.clear();
                          }),
                        ),
                      ),
                    if (selectedIds.isNotEmpty)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          icon: const Icon(Icons.delete_sweep),
                          label: Text(context.l10n.pick(
                              he: "מחק נבחרים (${selectedIds.length})",
                              en: "Delete selected (${selectedIds.length})")),
                          onPressed: () => _deleteSelected(
                            context: context,
                            sheetCtx: sheetCtx,
                            history: history,
                            selectedIds: selectedIds,
                            onHistoryUpdated: onHistoryUpdated,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: sessions.isEmpty
                    ? Center(
                        child: Text(showAllDays
                            ? context.l10n
                                .pick(he: "אין רשומות כלל", en: "No records")
                            : context.l10n.pick(
                                he: "אין רשומות ליום זה",
                                en: "No records for this day")))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: sessions.length,
                        itemBuilder: (context, index) => _row(
                          context: context,
                          sheetCtx: sheetCtx,
                          session: sessions[index],
                          projects: projects,
                          history: history,
                          dayStart: dayStart,
                          useGregorianDates: useGregorianDates,
                          showAllDays: showAllDays,
                          selectedIds: selectedIds,
                          setSheetState: setSheetState,
                          onHistoryUpdated: onHistoryUpdated,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// The commission a session belongs to, or a stand-in when it is gone.
Project _projectOf(BuildContext context, List<Project> projects, String id) =>
    projects.firstWhere(
      (p) => p.id == id,
      orElse: () => Project(
        id: 'deleted',
        name: context.l10n.pick(he: 'פרויקט נמחק', en: 'Deleted project'),
        type: ProjectType.sefer,
        price: 0,
        expenses: 0,
        targetDaily: 0,
        targetMonthly: 0,
      ),
    );

Widget _row({
  required BuildContext context,
  required BuildContext sheetCtx,
  required WorkSession session,
  required List<Project> projects,
  required List<WorkSession> history,
  required DayStart dayStart,
  required bool useGregorianDates,
  required bool showAllDays,
  required Set<String> selectedIds,
  required StateSetter setSheetState,
  required FutureOr<void> Function(List<WorkSession>) onHistoryUpdated,
}) {
  final project = _projectOf(context, projects, session.projectId);
  // Across all days the date is essential to tell otherwise-identical rows
  // apart — and it has to be the day the session was filed under, not its clock
  // date, or this list contradicts the day it was opened from.
  final when = showAllDays
      ? "${formatDisplayDate(DateLogic.workingDateOf(session, dayStart), useGregorianDates, english: context.l10n.isEnglish)} · "
      : "";

  return ListTile(
    leading: Checkbox(
      value: selectedIds.contains(session.id),
      onChanged: (v) => setSheetState(() {
        if (v == true) {
          selectedIds.add(session.id);
        } else {
          selectedIds.remove(session.id);
        }
      }),
    ),
    title: Text(project.name),
    subtitle: Text(
        "$when${session.description}\n${sessionTimeLabel(session, english: context.l10n.isEnglish)}${session.isTimeOnly ? context.l10n.pick(he: ' · זמן שורה חלקית', en: ' · Partial line time') : ''}"),
    isThreeLine: true,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!session.isTimeOnly)
          IconButton(
            icon: Icon(Icons.edit, color: SoferTokens.of(context).accent),
            onPressed: () => _editSession(
              context: context,
              sheetCtx: sheetCtx,
              session: session,
              project: project,
              history: history,
              dayStart: dayStart,
              onHistoryUpdated: onHistoryUpdated,
            ),
          ),
        IconButton(
          icon: Icon(Icons.delete, color: SoferTokens.of(context).danger),
          onPressed: () => _deleteSession(
            context: context,
            sheetCtx: sheetCtx,
            session: session,
            history: history,
            onHistoryUpdated: onHistoryUpdated,
          ),
        ),
      ],
    ),
  );
}

Future<void> _editWordSession(
    {required BuildContext context,
    required WorkSession session,
    required List<WorkSession> history,
    required DayStart dayStart,
    required FutureOr<void> Function(List<WorkSession>)
        onHistoryUpdated}) async {
  final words = TefillinWordRange.read(session);
  if (words == null) {
    showAppError(
        context,
        context.l10n.pick(
            he: 'גרסת רישום המילים אינה נתמכת. יש להשתמש בגרסה שיצרה את הרישום.',
            en: 'This word record version is unsupported. Use the app version that created it.'));
    return;
  }
  var until = words.until;
  String clock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final start = TextEditingController(text: clock(session.startTime));
  final end = TextEditingController(text: clock(session.endTime));
  final hasLater = history.any((s) =>
      s.id != session.id &&
      !s.isDeleted &&
      !s.isInvalid &&
      s.projectId == session.projectId &&
      s.pairIndex == session.pairIndex &&
      s.tefillinType == session.tefillinType &&
      s.parshiya == session.parshiya &&
      (TefillinWordRange.read(s)?.from ?? -1) >= words.until);
  final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
                title: Text(ctx.l10n
                    .pick(he: 'עריכת רישום מילים', en: 'Edit word record')),
                scrollable: true,
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                      'מילים ${words.from + 1}–$until · ${words.text.wordAt(until)}'),
                  OutlinedButton(
                      onPressed: hasLater
                          ? null
                          : () async {
                              final chosen = await showTefillinWords(
                                  context: ctx,
                                  parshiya: words.parshiya,
                                  script: StamScript.fromId(words.script),
                                  unitLabel: session.description,
                                  fromWord: words.from,
                                  selectedWord: until);
                              if (chosen != null && ctx.mounted) {
                                setDialog(() => until = chosen);
                              }
                            },
                      child: Text(ctx.l10n.pick(
                          he: 'שינוי המילה האחרונה', en: 'Change last word'))),
                  if (hasLater)
                    Text(ctx.l10n.pick(
                        he: 'יש רישומים מאוחרים יותר בפרשייה; נקודת הסיום נשמרת כדי לשמור על הרצף.',
                        en: 'Later records depend on this boundary; it is kept to preserve continuity.')),
                  TextField(
                      controller: start,
                      decoration: InputDecoration(
                          labelText: ctx.l10n.pick(
                              he: 'שעת התחלה HH:MM', en: 'Start time HH:MM'))),
                  TextField(
                      controller: end,
                      decoration: InputDecoration(
                          labelText: ctx.l10n.pick(
                              he: 'שעת סיום HH:MM', en: 'End time HH:MM'))),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(ctx.l10n.cancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(ctx.l10n.pick(he: 'שמור', en: 'Save')))
                ],
              )));
  final first = SessionLogic.parseTimeString(start.text);
  final last = SessionLogic.parseTimeString(end.text);
  start.dispose();
  end.dispose();
  if (ok != true || !context.mounted) return;
  if (first == null || last == null) {
    showAppError(
        context,
        context.l10n.pick(
            he: 'יש להזין שעות בפורמט HH:MM',
            en: 'Enter times in HH:MM format'));
    return;
  }
  if (history.any((s) {
    if (s.id == session.id ||
        s.isDeleted ||
        s.isInvalid ||
        s.projectId != session.projectId ||
        s.pairIndex != session.pairIndex ||
        s.tefillinType != session.tefillinType ||
        s.parshiya != session.parshiya) {
      return false;
    }
    final r = TefillinWordRange.read(s);
    return r != null && words.from < r.until && until > r.from;
  })) {
    showAppError(
        context,
        context.l10n.pick(
            he: 'טווח המילים חופף לרישום קיים',
            en: 'This word range overlaps another record'));
    return;
  }
  if (until < words.text.words.length &&
      history.any((s) =>
          s.projectId == session.projectId &&
          !s.isDeleted &&
          !s.isInvalid &&
          s.countsAsOutput &&
          s.pairIndex == session.pairIndex &&
          s.tefillinType == session.tefillinType &&
          (s.parshiya ?? 0) > words.parshiya)) {
    showAppError(
        context,
        context.l10n.pick(
            he: 'כבר נכתבה פרשייה מאוחרת יותר. יש לתקן תחילה את ההמשך באותו סט.',
            en: 'A later Parashah was already written. Correct the continuation in this set first.'));
    return;
  }
  final time = SessionLogic.buildTimeRange(
      date: session.startTime,
      startHour: first.hour,
      startMinute: first.minute,
      endHour: last.hour,
      endMinute: last.minute);
  final changed = TefillinWordRange(
      parshiya: words.parshiya,
      from: words.from,
      until: until,
      baselineWord: words.baselineWord,
      baselineFraction: words.baselineFraction,
      script: words.script);
  final updated = session.copyWith(
      startTime: time.start,
      endTime: time.end,
      timeRecorded: true,
      timeOfDayKnown: true,
      dayRule: dayStart,
      workingDateAtEntry: DateLogic.effectiveDate(time.start, dayStart),
      description:
          'פרשיית ${TefillinUnits.names[words.parshiya - 1]} של ${session.tefillinType == 'head' ? 'ראש' : 'יד'} (זוג ${session.pairIndex}, מילים ${words.from + 1}–$until, עד ${words.text.wordAt(until)})',
      extraFields: {
        ...session.extraFields,
        TefillinWordRange.key: changed.toJson()
      });
  await onHistoryUpdated(
      [for (final s in history) s.id == session.id ? updated : s]);
}

/// Marks records deleted. Dropping them from the list instead is what this used
/// to do, and a record that is merely absent is a record another device puts
/// back at the next merge.
Future<void> _deleteSelected({
  required BuildContext context,
  required BuildContext sheetCtx,
  required List<WorkSession> history,
  required Set<String> selectedIds,
  required FutureOr<void> Function(List<WorkSession>) onHistoryUpdated,
}) async {
  if (selectedIds.isEmpty) return;
  final confirmed = await confirmAction(
    context,
    title: context.l10n.pick(he: "מחיקת רשומות", en: "Delete records"),
    message: context.l10n.pick(
        he: "למחוק ${selectedIds.length} רשומות?",
        en: "Delete ${selectedIds.length} records?"),
    confirmLabel: context.l10n.pick(he: "מחק", en: "Delete"),
    danger: true,
  );
  if (!confirmed) return;

  await onHistoryUpdated([
    for (final s in history)
      selectedIds.contains(s.id) ? s.copyWith(isDeleted: true) : s,
  ]);
  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
}

/// Marks one record deleted. See [_deleteSelected].
Future<void> _deleteSession({
  required BuildContext context,
  required BuildContext sheetCtx,
  required WorkSession session,
  required List<WorkSession> history,
  required FutureOr<void> Function(List<WorkSession>) onHistoryUpdated,
}) async {
  final confirmed = await confirmAction(
    context,
    title: context.l10n.pick(he: "מחיקת רשומה", en: "Delete record"),
    message: context.l10n.pick(
        he: "למחוק את הרשומה \"${session.description}\"?",
        en: "Delete the record \"${session.description}\"?"),
    confirmLabel: context.l10n.pick(he: "מחק", en: "Delete"),
    danger: true,
  );
  if (!confirmed) return;

  await onHistoryUpdated([
    for (final s in history)
      s.id == session.id ? s.copyWith(isDeleted: true) : s,
  ]);
  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
}

/// Restates when a session happened and what it covered.
///
/// Every check the entry form applies is applied here too. Editing used to
/// bypass all of them, so the one screen that exists to correct a mistake was
/// the one screen that could not catch one.
Future<void> _editSession({
  required BuildContext context,
  required BuildContext sheetCtx,
  required WorkSession session,
  required Project project,
  required List<WorkSession> history,
  required DayStart dayStart,
  required FutureOr<void> Function(List<WorkSession>) onHistoryUpdated,
}) async {
  String hhmm(DateTime t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  if (TefillinWordRange.isWordRecord(session)) {
    await _editWordSession(
        context: context,
        session: session,
        history: history,
        dayStart: dayStart,
        onHistoryUpdated: onHistoryUpdated);
    return;
  }

  final startCtrl = TextEditingController(text: hhmm(session.startTime));
  final endCtrl = TextEditingController(text: hhmm(session.endTime));
  final startLineCtrl =
      TextEditingController(text: session.startLine.toString());
  final endLineCtrl = TextEditingController(text: session.endLine.toString());
  final amountCtrl = TextEditingController(text: session.amount.toString());

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(context.l10n.pick(he: "עריכת רשומה", en: "Edit record")),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n
                .pick(he: "שעת התחלה (HH:MM)", en: "Start time (HH:MM)")),
            TextField(controller: startCtrl),
            const SizedBox(height: 8),
            Text(context.l10n
                .pick(he: "שעת סיום (HH:MM)", en: "End time (HH:MM)")),
            TextField(controller: endCtrl),
            const SizedBox(height: 8),
            TextField(
              controller: startLineCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText:
                      context.l10n.pick(he: "שורה התחלה", en: "Start line")),
            ),
            TextField(
              controller: endLineCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText:
                      context.l10n.pick(he: "שורה סיום", en: "End line")),
            ),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: context.l10n.pick(
                      he: "כמות (עמוד/מזוזה)", en: "Quantity (page/Mezuzah)")),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(context.l10n.cancel)),
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(context.l10n.pick(he: "שמור", en: "Save"))),
      ],
    ),
  );

  final parsedStart = SessionLogic.parseTimeString(startCtrl.text);
  final parsedEnd = SessionLogic.parseTimeString(endCtrl.text);
  final startLine = int.tryParse(startLineCtrl.text) ?? session.startLine;
  final endLine = int.tryParse(endLineCtrl.text) ?? session.endLine;
  final amount = int.tryParse(amountCtrl.text) ?? session.amount;
  startCtrl.dispose();
  endCtrl.dispose();
  startLineCtrl.dispose();
  endLineCtrl.dispose();
  amountCtrl.dispose();
  if (ok != true || !context.mounted) return;

  // An invalid clock string used to fall back to the old value silently. That
  // made the editor appear to save a correction while retaining the previous
  // time, which was especially confusing when the writer was fixing a single
  // row. Reject it explicitly instead.
  if ((startCtrl.text.trim().isNotEmpty && parsedStart == null) ||
      (endCtrl.text.trim().isNotEmpty && parsedEnd == null)) {
    showAppError(
        context,
        context.l10n.pick(
          he: 'יש להזין שעות בפורמט HH:MM',
          en: 'Enter times in HH:MM format',
        ));
    return;
  }

  final numericFields = <String, String>{
    'startLine': startLineCtrl.text,
    'endLine': endLineCtrl.text,
    'amount': amountCtrl.text,
  };
  for (final entry in numericFields.entries) {
    if (entry.value.trim().isNotEmpty &&
        int.tryParse(entry.value.trim()) == null) {
      showAppError(
          context,
          context.l10n.pick(
            he: 'יש להזין מספר תקין בשדה ${entry.key}',
            en: 'Enter a valid number in ${entry.key}',
          ));
      return;
    }
  }

  if (amount < 0) {
    showAppError(
        context,
        context.l10n.pick(
          he: 'הכמות לא יכולה להיות שלילית',
          en: 'Quantity cannot be negative',
        ));
    return;
  }

  // Same range builder the entry form uses, so a session running past midnight
  // ends on the next day instead of producing a negative duration.
  final range = SessionLogic.buildTimeRange(
    date: session.startTime,
    startHour: parsedStart?.hour ?? session.startTime.hour,
    startMinute: parsedStart?.minute ?? session.startTime.minute,
    endHour: parsedEnd?.hour ?? session.endTime.hour,
    endMinute: parsedEnd?.minute ?? session.endTime.minute,
  );

  if (project.type.isPaged && project.id != 'deleted') {
    final lineError = SessionLogic.validateSeferLines(
      startLine: startLine,
      endLine: endLine,
      linesPerPage: ProductionCalculator.linesPerPageOf(project),
    );
    if (lineError != null) {
      showAppError(context, context.l10n.businessMessage(lineError));
      return;
    }

    final overlaps = SessionLogic.hasSeferOverlap(
      history: history,
      projectId: session.projectId,
      page: amount,
      startLine: startLine,
      endLine: endLine,
      projectType: project.type,
      // Without this the session would always clash with itself.
      excludeSessionId: session.id,
    );
    if (overlaps) {
      if (!await confirmOverlap(context, pages: [amount])) return;
      if (!context.mounted) return;
    }
  }

  if (project.type == ProjectType.mezuza && project.id != 'deleted') {
    // Full mezuzot in older files use 0–0; identified partial entries use a
    // contribution in endLine and keep startLine at zero. Preserve both shapes
    // while still rejecting impossible line numbers.
    if (startLine < 0 ||
        endLine < 0 ||
        startLine > ProductionCalculator.linesPerMezuza ||
        endLine > ProductionCalculator.linesPerMezuza ||
        (startLine > 0 && endLine > 0 && endLine < startLine)) {
      showAppError(
          context,
          context.l10n.pick(
            he: 'שורות המזוזה חייבות להיות בטווח 1–${ProductionCalculator.linesPerMezuza}',
            en: 'Mezuzah lines must be between 1 and ${ProductionCalculator.linesPerMezuza}',
          ));
      return;
    }
  }

  if (project.type == ProjectType.tefillin && project.id != 'deleted') {
    final type = session.tefillinType;
    final parshiya = session.parshiya;
    if (parshiya != null && (parshiya < 1 || parshiya > 4)) {
      showAppError(
          context,
          context.l10n.pick(
            he: 'מספר הפרשייה חייב להיות בין 1 ל־4',
            en: 'Parashah number must be between 1 and 4',
          ));
      return;
    }
    if (parshiya != null && type != null) {
      final maxLines = type == 'head'
          ? TefillinUnits.linesPerHeadParshiya
          : type == 'hand'
              ? TefillinUnits.linesPerHandParshiya
              : 0;
      if (maxLines > 0 &&
          (startLine < 0 ||
              endLine < 0 ||
              startLine > maxLines ||
              endLine > maxLines ||
              (startLine > 0 && endLine > 0 && endLine < startLine))) {
        showAppError(
            context,
            context.l10n.pick(
              he: 'שורות התפילין חייבות להיות בטווח 1–$maxLines',
              en: 'Tefillin lines must be between 1 and $maxLines',
            ));
        return;
      }
      final pair = session.pairIndex;
      if ((type == 'head' || type == 'hand') && pair != null && pair >= 1) {
        final side = type == 'head' ? TefillinSide.head : TefillinSide.hand;
        final withoutCurrent = history.where((s) => s.id != session.id);
        final slots = TefillinState.slots(project, withoutCurrent);
        final target = slots.firstWhere(
          (slot) =>
              slot.pair == pair &&
              slot.side == side &&
              slot.parshiya == parshiya,
          orElse: () => TefillinSlot(
            pair: pair,
            side: side,
            parshiya: parshiya,
          ),
        );
        if (!TefillinState.canStart(target, slots)) {
          showAppError(
              context,
              context.l10n.pick(
                he: 'אי אפשר לערוך את הפרשייה לפני שהקודמת לה באותו סט הסתיימה',
                en: 'This Parashah cannot be edited before its predecessor in the set is complete',
              ));
          return;
        }
      }
    }
  }

  final updated = session.copyWith(
    startTime: range.start,
    endTime: range.end,
    startLine: startLine,
    endLine: endLine,
    amount: amount,
    // Re-settled with today's rule: the writer is actively restating when this
    // work happened, so the current reckoning is the one they mean. Editing a
    // 23:00 session to 00:30 must move it.
    dayRule: dayStart,
    workingDateAtEntry: DateLogic.effectiveDate(range.start, dayStart),
    // The editor asks for a start and an end, so once it is saved the session
    // has a time whether or not it had one before.
    timeRecorded: true,
  );

  await onHistoryUpdated(
      [for (final s in history) s.id == session.id ? updated : s]);
  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
}
