import 'dart:async';
import 'package:flutter/material.dart';

import '../format.dart';
import '../hebrew_utils.dart';
import '../l10n/app_localizations.dart';
import '../logic/hebrew_clock.dart';
import '../logic/mezuza_state.dart';
import '../logic/production_calculator.dart';
import '../logic/work_correction.dart';
import '../models.dart';
import '../summary/history_editor.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm.dart';
import '../widgets/feedback.dart';
import '../widgets/sofer_widgets.dart';

enum WritingView { units, records }

/// The work itself, editable in the physical units a sofer handles.
class ProjectWritingTab extends StatefulWidget {
  final Project project;
  final List<Project> projects;
  final List<WorkSession> history;
  final DayStart dayStart;
  final bool useGregorianDates;
  final FutureOr<void> Function(List<WorkSession>) onHistoryUpdated;
  final Widget? tefillinBoard;

  const ProjectWritingTab({
    super.key,
    required this.project,
    required this.projects,
    required this.history,
    required this.dayStart,
    required this.useGregorianDates,
    required this.onHistoryUpdated,
    this.tefillinBoard,
  });

  @override
  State<ProjectWritingTab> createState() => _ProjectWritingTabState();
}

class _ProjectWritingTabState extends State<ProjectWritingTab> {
  WritingView _view = WritingView.units;
  bool _applying = false;

  List<WorkSession> get _projectHistory => widget.history
      .where((session) => session.projectId == widget.project.id)
      .toList();

  List<WorkSession> get _live =>
      _projectHistory.where((session) => !session.isDeleted).toList();

  Future<void> _apply(
    WorkCorrectionResult result, {
    required String message,
  }) async {
    if (!result.changed || _applying) return;
    _applying = true;
    try {
      await widget.onHistoryUpdated(result.history);
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: context.l10n.pick(he: 'ביטול', en: 'Undo'),
          onPressed: () async {
            try {
              await widget.onHistoryUpdated(result.undo());
            } catch (error) {
              if (mounted) {
                showAppError(
                    context,
                    context.l10n.pick(
                        he: 'ביטול התיקון לא נשמר: $error',
                        en: 'Undo could not be saved: $error'));
              }
            }
          },
        ),
      ));
    } catch (error) {
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'התיקון לא נשמר. אפשר לנסות שוב: $error',
                en: 'The correction could not be saved. Try again: $error'));
      }
    } finally {
      _applying = false;
    }
  }

  Future<void> _deleteIds(Set<String> ids, String what) async {
    if (ids.isEmpty) return;
    final doneMessage =
        context.l10n.pick(he: '$what נמחק', en: '$what deleted');
    final confirmed = await confirmAction(
      context,
      title: context.l10n.pick(he: 'מחיקת $what', en: 'Delete $what'),
      message: context.l10n.pick(
        he: 'הרישום יועבר לסל המחזור ויהיה ניתן לשחזר אותו.',
        en: 'The record will move to the Recycle Bin and can be restored.',
      ),
      confirmLabel: context.l10n.pick(he: 'מחק', en: 'Delete'),
      danger: true,
    );
    if (!confirmed) return;
    await _apply(
      WorkCorrection.delete(widget.history, ids),
      message: doneMessage,
    );
  }

  Future<void> _invalidateIds(Set<String> ids, String what) async {
    if (ids.isEmpty) return;
    final doneMessage =
        context.l10n.pick(he: '$what סומן כנפסל', en: '$what marked invalid');
    final confirmed = await confirmAction(
      context,
      title: context.l10n.pick(he: '$what נפסל?', en: 'Mark $what invalid?'),
      message: context.l10n.pick(
        he: 'ההספק והרווח יוסרו, אך זמן הכתיבה יישמר כזמן על עבודה שנפסלה.',
        en: 'Output and profit will be removed, while the writing time will remain as time spent on invalid work.',
      ),
      confirmLabel: context.l10n.pick(he: 'סמן כנפסל', en: 'Mark invalid'),
      danger: true,
    );
    if (!confirmed) return;
    await _apply(
      WorkCorrection.markInvalid(widget.history, ids),
      message: doneMessage,
    );
  }

  Future<void> _restoreInvalid(Set<String> ids) async {
    await _apply(
      WorkCorrection.markInvalid(widget.history, ids, invalid: false),
      message: context.l10n
          .pick(he: 'העבודה הוחזרה להספק', en: 'Work restored to output'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SegmentedButton<WritingView>(
            segments: [
              ButtonSegment(
                value: WritingView.units,
                icon: const Icon(Icons.view_timeline_outlined),
                label: Text(context.l10n.pick(he: 'לפי יחידות', en: 'By unit')),
              ),
              ButtonSegment(
                value: WritingView.records,
                icon: const Icon(Icons.receipt_long_outlined),
                label:
                    Text(context.l10n.pick(he: 'לפי רשומות', en: 'By record')),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (value) => setState(() => _view = value.first),
          ),
        ),
        Expanded(
          child: _view == WritingView.records ? _recordsView() : _unitsView(),
        ),
      ],
    );
  }

  Widget _unitsView() => switch (widget.project.type) {
        ProjectType.sefer || ProjectType.megillah => _seferView(),
        ProjectType.mezuza => _mezuzaView(),
        ProjectType.tefillin => widget.tefillinBoard ?? const SizedBox.shrink(),
      };

  Widget _recordsView() {
    final sessions = _live..sort((a, b) => b.startTime.compareTo(a.startTime));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.edit_note),
            label: Text(context.l10n
                .pick(he: 'פתח עריכת רשומות מלאה', en: 'Open full editor')),
            onPressed: () => showHistoryEditor(
              context: context,
              projects: widget.projects,
              history: widget.history,
              day: DateTime.now(),
              dayLabel: context.l10n.pick(he: 'היום', en: 'Today'),
              dayStart: widget.dayStart,
              useGregorianDates: widget.useGregorianDates,
              onHistoryUpdated: widget.onHistoryUpdated,
              initialProjectId: widget.project.id,
              startWithAllDays: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(context.l10n
                  .pick(he: 'אין רשומות בפרויקט', en: 'No project records')),
            ),
          ),
        for (final session in sessions)
          Card(
            child: ListTile(
              leading: session.isTimeOnly
                  ? const Icon(Icons.hourglass_bottom)
                  : session.isInvalid
                      ? Icon(Icons.block, color: SoferTokens.of(context).danger)
                      : const Icon(Icons.edit_note),
              title: Text(session.description),
              subtitle: Text(
                '${formatDisplayDate(session.startTime, widget.useGregorianDates, english: context.l10n.isEnglish)} · '
                '${sessionTimeLabel(session, english: context.l10n.isEnglish)}'
                '${session.isTimeOnly ? context.l10n.pick(he: ' · זמן שורה חלקית', en: ' · Partial line time') : ''}'
                '${session.isInvalid ? context.l10n.pick(he: ' · נפסל', en: ' · Invalid') : ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  final ids = {session.id};
                  if (action == 'invalid') {
                    _invalidateIds(
                        ids, context.l10n.pick(he: 'הרשומה', en: 'record'));
                  } else if (action == 'restore') {
                    _restoreInvalid(ids);
                  } else if (action == 'delete') {
                    _deleteIds(
                        ids, context.l10n.pick(he: 'הרשומה', en: 'record'));
                  }
                },
                itemBuilder: (_) => [
                  if (!session.isTimeOnly &&
                      !session.isInvalid &&
                      widget.project.type != ProjectType.tefillin)
                    PopupMenuItem(
                      value: 'invalid',
                      child: Text(context.l10n
                          .pick(he: 'סמן כנפסל', en: 'Mark invalid')),
                    ),
                  if (session.isInvalid &&
                      widget.project.type != ProjectType.tefillin)
                    PopupMenuItem(
                      value: 'restore',
                      child: Text(context.l10n
                          .pick(he: 'החזר להספק', en: 'Restore to output')),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(context.l10n.pick(he: 'מחק', en: 'Delete')),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _seferView() {
    final t = SoferTokens.of(context);
    final linesPerPage = ProductionCalculator.linesPerPageOf(widget.project);
    final pages = <int, Set<int>>{};
    for (final session in _live
        .where((session) => !session.isInvalid && session.countsAsOutput)) {
      if (session.amount <= 0) continue;
      final lines = pages.putIfAbsent(session.amount, () => <int>{});
      for (var line = session.startLine; line <= session.endLine; line++) {
        lines.add(line);
      }
    }
    final total =
        widget.project.totalPages ?? ProductionCalculator.defaultTotalPages;
    final writtenPages = pages.entries
        .where((entry) =>
            entry.key >= 1 && entry.key <= total && entry.value.isNotEmpty)
        .length;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoferSectionTitle(
                  context.l10n.pick(he: 'מפת העמודים', en: 'Page map'),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 5),
                Text(
                  context.l10n.pick(
                    he: '$writtenPages מתוך $total עמודים החלו · לחיצה על עמוד פותחת את השורות שלו',
                    en: '$writtenPages of $total pages started · tap a page to open its lines',
                  ),
                  style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12,
                    color: t.inkMuted,
                  ),
                ),
                if (t.isRules) ...[
                  const SizedBox(height: 10),
                  Container(height: 1, color: t.ruleStrong),
                ],
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: t.isRules ? 82 : 92,
              childAspectRatio: t.isRules ? 0.76 : 0.82,
              crossAxisSpacing: t.isRules ? 7 : 10,
              mainAxisSpacing: t.isRules ? 8 : 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final page = index + 1;
                final written = pages[page]?.length ?? 0;
                return _seferPageTile(
                  page: page,
                  written: written,
                  linesPerPage: linesPerPage,
                );
              },
              childCount: total,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: _invalidSection(),
          ),
        ),
      ],
    );
  }

  Widget _seferPageTile({
    required int page,
    required int written,
    required int linesPerPage,
  }) {
    final t = SoferTokens.of(context);
    final progress = (written / linesPerPage).clamp(0.0, 1.0);
    final complete = written >= linesPerPage;
    final state = complete
        ? context.l10n.pick(he: 'הושלם', en: 'Complete')
        : written == 0
            ? context.l10n.pick(he: 'טרם', en: 'Not started')
            : context.l10n.pick(
                he: '$written/$linesPerPage שורות',
                en: '$written/$linesPerPage lines',
              );
    final radius = BorderRadius.circular(t.isCards ? 12 : 1);
    final background = Color.alphaBlend(
      t.accent.withValues(alpha: progress > 0 ? (t.isRules ? 0.055 : 0.10) : 0),
      t.paper,
    );

    Widget pageFace = Padding(
      padding: EdgeInsets.all(t.isRules ? 5 : 7),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Text(
                formatHebrewNumber(page),
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: TextStyle(
                  fontFamily: t.numeralFamily,
                  fontSize: t.isRules ? 17 : 16,
                  fontWeight: t.isCards ? FontWeight.w700 : FontWeight.w500,
                  color: written > 0 ? t.ink : t.inkMuted,
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (complete) ...[
                Icon(Icons.check, size: 12, color: t.accent),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(
                  state,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 9,
                    color: written > 0 ? t.accent : t.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SoferProgress(progress),
        ],
      ),
    );

    // In the ruled themes the second hairline makes each cell read as a small
    // parchment folio. There is no card, radius or shadow competing with the
    // writing; modern keeps its familiar raised-tile language.
    if (t.isRules) {
      pageFace = Padding(
        padding: const EdgeInsets.all(2),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: t.rule)),
          child: pageFace,
        ),
      );
    }

    return Semantics(
      button: true,
      label: context.l10n.pick(
        he: 'עמוד ${formatHebrewNumber(page)}, $state',
        en: 'Page ${formatHebrewNumber(page)}, $state',
      ),
      child: Material(
        key: ValueKey('sefer-page-$page'),
        color: background,
        elevation: t.isCards ? 1 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: t.isRules ? t.ruleStrong : t.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: () => _openSeferPage(page, linesPerPage),
          child: pageFace,
        ),
      ),
    );
  }

  Future<void> _openSeferPage(int page, int linesPerPage) async {
    final sessions = _live
        .where((session) =>
            session.amount == page &&
            !session.isInvalid &&
            session.countsAsOutput)
        .toList();
    final ids = sessions.map((session) => session.id).toSet();
    final written = <int>{};
    for (final session in sessions) {
      for (var line = session.startLine; line <= session.endLine; line++) {
        written.add(line);
      }
    }
    final selected = <int>{};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SoferSectionTitle(context.l10n.pick(
                    he: 'עמוד ${formatHebrewNumber(page)}',
                    en: 'Page ${formatHebrewNumber(page)}',
                  )),
                  Text(context.l10n.pick(
                    he: written.isEmpty
                        ? 'העמוד טרם נכתב.'
                        : 'בחר שורות שנרשמו בטעות, או טפל בעמוד כולו.',
                    en: written.isEmpty
                        ? 'This page has not been written yet.'
                        : 'Select lines recorded by mistake, or manage the whole page.',
                  )),
                  const SizedBox(height: 12),
                  if (written.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var line = 1; line <= linesPerPage; line++)
                          FilterChip(
                            label: Text('$line'),
                            selected: selected.contains(line),
                            onSelected: written.contains(line)
                                ? (value) => setSheetState(() => value
                                    ? selected.add(line)
                                    : selected.remove(line))
                                : null,
                          ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (selected.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: Text(context.l10n.pick(
                          he: 'מחק ${selected.length} שורות שנבחרו',
                          en: 'Delete ${selected.length} selected lines',
                        )),
                        onPressed: () async {
                          final title = context.l10n
                              .pick(he: 'מחיקת שורות', en: 'Delete lines');
                          final question = context.l10n.pick(
                            he: 'השורות יוסרו מהרשומה. הזמן של הרשומה יחולק מחדש בין החלקים שנותרו.',
                            en: 'The lines will be removed. The record time will be redistributed between the remaining parts.',
                          );
                          final confirmLabel =
                              context.l10n.pick(he: 'מחק', en: 'Delete');
                          final doneMessage = context.l10n
                              .pick(he: 'השורות נמחקו', en: 'Lines deleted');
                          Navigator.pop(sheetContext);
                          final confirmed = await confirmAction(
                            this.context,
                            title: title,
                            message: question,
                            confirmLabel: confirmLabel,
                            danger: true,
                          );
                          if (!confirmed) return;
                          await _apply(
                            WorkCorrection.removeSeferLines(
                              history: widget.history,
                              projectId: widget.project.id,
                              page: page,
                              lines: selected,
                            ),
                            message: doneMessage,
                          );
                        },
                      ),
                    ),
                  if (written.isNotEmpty) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.block,
                          color: SoferTokens.of(context).danger),
                      title: Text(context.l10n
                          .pick(he: 'העמוד נפסל', en: 'Page is invalid')),
                      subtitle: Text(context.l10n.pick(
                        he: 'הסר מההספק ושמור את זמן הכתיבה',
                        en: 'Remove from output and keep writing time',
                      )),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _invalidateIds(
                            ids, context.l10n.pick(he: 'העמוד', en: 'page'));
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline,
                          color: SoferTokens.of(context).danger),
                      title: Text(context.l10n.pick(
                          he: 'מחק רישום שגוי', en: 'Delete wrong record')),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _deleteIds(
                            ids, context.l10n.pick(he: 'העמוד', en: 'page'));
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mezuzaView() {
    final slots = MezuzaState.slots(widget.project, _live);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        SoferSectionTitle(
            context.l10n.pick(he: 'המזוזות בהזמנה', en: 'Order Mezuzot')),
        for (final slot in slots)
          if (slot.state != MezuzaSlotState.empty)
            Card(
              child: ListTile(
                leading: Icon(
                  slot.state == MezuzaSlotState.done
                      ? Icons.check_circle
                      : Icons.timelapse,
                  color: SoferTokens.of(context).accent,
                ),
                title: Text(context.l10n.pick(
                    he: 'מזוזה ${slot.index}', en: 'Mezuzah ${slot.index}')),
                subtitle: Text(context.l10n.pick(
                  he: '${slot.linesWritten} מתוך ${ProductionCalculator.linesPerMezuza} שורות',
                  en: '${slot.linesWritten} of ${ProductionCalculator.linesPerMezuza} lines',
                )),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openMezuza(slot.index),
              ),
            ),
        _invalidSection(),
      ],
    );
  }

  Future<void> _openMezuza(int index) async {
    final exact = _live
        .where((session) => session.mezuzaIndex == index)
        .map((session) => session.id)
        .toSet();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                  context.l10n.pick(he: 'מזוזה $index', en: 'Mezuzah $index')),
              subtitle: Text(context.l10n.pick(
                  he: exact.isEmpty
                      ? 'רישום מגרסה ישנה — התוכנה תפריד רק את המזוזה הזאת'
                      : '${exact.length} רשומות כתיבה',
                  en: exact.isEmpty
                      ? 'Older record — only this Mezuzah will be separated'
                      : '${exact.length} writing records')),
            ),
            ListTile(
              leading: Icon(Icons.block, color: SoferTokens.of(context).danger),
              title: Text(context.l10n
                  .pick(he: 'המזוזה נפסלה', en: 'Mezuzah is invalid')),
              subtitle: Text(context.l10n.pick(
                he: 'כל חלקיה יוסרו מההספק והזמן יישמר',
                en: 'All parts leave output while their time is kept',
              )),
              onTap: () => Navigator.pop(context, 'invalid'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: SoferTokens.of(context).danger),
              title: Text(context.l10n
                  .pick(he: 'מחק רישום שגוי', en: 'Delete wrong record')),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final name = context.l10n.pick(he: 'מזוזה $index', en: 'Mezuzah $index');
    final invalidTitle =
        context.l10n.pick(he: '$name נפסלה?', en: 'Mark $name invalid?');
    final invalidMessage = context.l10n.pick(
      he: 'כל חלקיה יוסרו מההספק והרווח, אך זמן הכתיבה יישמר.',
      en: 'All parts will be removed from output and profit, while writing time is kept.',
    );
    final invalidConfirm =
        context.l10n.pick(he: 'סמן כנפסלה', en: 'Mark invalid');
    final invalidDone =
        context.l10n.pick(he: '$name סומנה כנפסלה', en: '$name marked invalid');
    final deleteTitle =
        context.l10n.pick(he: 'מחיקת $name', en: 'Delete $name');
    final deleteMessage = context.l10n.pick(
      he: 'רישום המזוזה יועבר לסל המחזור. אם היא חלק מרשומה ישנה של כמה מזוזות, רק היא תופרד ותימחק.',
      en: 'The Mezuzah record will move to the Recycle Bin. If it belongs to an older bundled record, only this Mezuzah will be separated and deleted.',
    );
    final deleteConfirm = context.l10n.pick(he: 'מחק', en: 'Delete');
    final deleteDone =
        context.l10n.pick(he: '$name נמחקה', en: '$name deleted');
    if (action == 'invalid') {
      final confirmed = await confirmAction(
        context,
        title: invalidTitle,
        message: invalidMessage,
        confirmLabel: invalidConfirm,
        danger: true,
      );
      if (confirmed) {
        await _apply(
          WorkCorrection.markMezuzaInvalid(
            history: widget.history,
            projectId: widget.project.id,
            index: index,
          ),
          message: invalidDone,
        );
      }
      return;
    }
    if (action == 'delete') {
      final confirmed = await confirmAction(
        context,
        title: deleteTitle,
        message: deleteMessage,
        confirmLabel: deleteConfirm,
        danger: true,
      );
      if (confirmed) {
        await _apply(
          WorkCorrection.deleteMezuza(
            history: widget.history,
            projectId: widget.project.id,
            index: index,
          ),
          message: deleteDone,
        );
      }
    }
  }

  Widget _invalidSection() {
    final invalid = _live.where((session) => session.isInvalid).toList();
    if (invalid.isEmpty) return const SizedBox.shrink();
    final groups = <String, List<WorkSession>>{};
    for (final session in invalid) {
      final key = switch (widget.project.type) {
        ProjectType.sefer || ProjectType.megillah => context.l10n.pick(
            he: 'עמוד ${formatHebrewNumber(session.amount)}',
            en: 'Page ${formatHebrewNumber(session.amount)}'),
        ProjectType.mezuza => context.l10n.pick(
            he: 'מזוזה ${session.mezuzaIndex ?? session.amount}',
            en: 'Mezuzah ${session.mezuzaIndex ?? session.amount}'),
        ProjectType.tefillin => session.description,
      };
      groups.putIfAbsent(key, () => []).add(session);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoferSectionTitle(
              context.l10n.pick(he: 'עבודה שנפסלה', en: 'Invalid work')),
          for (final entry in groups.entries)
            ListTile(
              leading: Icon(Icons.block, color: SoferTokens.of(context).danger),
              title: Text(entry.key),
              subtitle: Text(context.l10n.pick(
                he: 'הזמן נשמר · לא נספר בהספק',
                en: 'Time kept · excluded from output',
              )),
              trailing: PopupMenuButton<String>(
                onSelected: (action) {
                  final ids = entry.value.map((session) => session.id).toSet();
                  if (action == 'restore') _restoreInvalid(ids);
                  if (action == 'delete') _deleteIds(ids, entry.key);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'restore',
                    child: Text(context.l10n
                        .pick(he: 'החזר להספק', en: 'Restore to output')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(context.l10n.pick(he: 'מחק', en: 'Delete')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
