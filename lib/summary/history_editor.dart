import 'package:flutter/material.dart';

import '../format.dart';
import '../hebrew_utils.dart';
import '../logic/date_logic.dart';
import '../logic/hebrew_clock.dart';
import '../logic/production_calculator.dart';
import '../logic/session_logic.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm.dart';
import '../widgets/feedback.dart';

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
  required void Function(List<WorkSession>) onHistoryUpdated,
}) {
  final selectedIds = <String>{};
  // Starts on the selected day, which is the common case, but the editor can
  // switch to the full history.
  var showAllDays = false;
  var projectFilter = '';

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
                    ? "עריכת רשומות – כל הימים"
                    : "עריכת רשומות – יום נבחר"),
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
                        const ButtonSegment(
                          value: true,
                          label: Text("כל הימים"),
                          icon: Icon(Icons.all_inbox, size: 18),
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
                          decoration: const InputDecoration(
                            labelText: "סינון לפי פרויקט",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: '', child: Text("כל הפרויקטים")),
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
                          label: Text("מחק נבחרים (${selectedIds.length})"),
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
                            ? "אין רשומות כלל"
                            : "אין רשומות ליום זה"))
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
Project _projectOf(List<Project> projects, String id) => projects.firstWhere(
      (p) => p.id == id,
      orElse: () => Project(
        id: 'deleted',
        name: 'פרויקט נמחק',
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
  required void Function(List<WorkSession>) onHistoryUpdated,
}) {
  final project = _projectOf(projects, session.projectId);
  // Across all days the date is essential to tell otherwise-identical rows
  // apart — and it has to be the day the session was filed under, not its clock
  // date, or this list contradicts the day it was opened from.
  final when = showAllDays
      ? "${formatDisplayDate(DateLogic.workingDateOf(session, dayStart), useGregorianDates)} · "
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
    subtitle:
        Text("$when${session.description}\n${sessionTimeLabel(session)}"),
    isThreeLine: true,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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

/// Marks records deleted. Dropping them from the list instead is what this used
/// to do, and a record that is merely absent is a record another device puts
/// back at the next merge.
Future<void> _deleteSelected({
  required BuildContext context,
  required BuildContext sheetCtx,
  required List<WorkSession> history,
  required Set<String> selectedIds,
  required void Function(List<WorkSession>) onHistoryUpdated,
}) async {
  if (selectedIds.isEmpty) return;
  final confirmed = await confirmAction(
    context,
    title: "מחיקת רשומות",
    message: "למחוק ${selectedIds.length} רשומות?",
    confirmLabel: "מחק",
    danger: true,
  );
  if (!confirmed) return;

  onHistoryUpdated([
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
  required void Function(List<WorkSession>) onHistoryUpdated,
}) async {
  final confirmed = await confirmAction(
    context,
    title: "מחיקת רשומה",
    message: "למחוק את הרשומה \"${session.description}\"?",
    confirmLabel: "מחק",
    danger: true,
  );
  if (!confirmed) return;

  onHistoryUpdated([
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
  required void Function(List<WorkSession>) onHistoryUpdated,
}) async {
  String hhmm(DateTime t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  final startCtrl = TextEditingController(text: hhmm(session.startTime));
  final endCtrl = TextEditingController(text: hhmm(session.endTime));
  final startLineCtrl =
      TextEditingController(text: session.startLine.toString());
  final endLineCtrl = TextEditingController(text: session.endLine.toString());
  final amountCtrl = TextEditingController(text: session.amount.toString());

  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: const Text("עריכת רשומה"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("שעת התחלה (HH:MM)"),
            TextField(controller: startCtrl),
            const SizedBox(height: 8),
            const Text("שעת סיום (HH:MM)"),
            TextField(controller: endCtrl),
            const SizedBox(height: 8),
            TextField(
              controller: startLineCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "שורה התחלה"),
            ),
            TextField(
              controller: endLineCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "שורה סיום"),
            ),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: "כמות (עמוד/מזוזה)"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text("ביטול")),
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text("שמור")),
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

  // Same range builder the entry form uses, so a session running past midnight
  // ends on the next day instead of producing a negative duration.
  final range = SessionLogic.buildTimeRange(
    date: session.startTime,
    startHour: parsedStart?.hour ?? session.startTime.hour,
    startMinute: parsedStart?.minute ?? session.startTime.minute,
    endHour: parsedEnd?.hour ?? session.endTime.hour,
    endMinute: parsedEnd?.minute ?? session.endTime.minute,
  );

  if (project.type == ProjectType.sefer && project.id != 'deleted') {
    final lineError = SessionLogic.validateSeferLines(
      startLine: startLine,
      endLine: endLine,
      linesPerPage: ProductionCalculator.linesPerPageOf(project),
    );
    if (lineError != null) {
      showAppError(context, lineError);
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

  onHistoryUpdated(
      [for (final s in history) s.id == session.id ? updated : s]);
  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
}
