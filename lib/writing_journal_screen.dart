import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'entry/entry_draft.dart';
import 'entry/entry_sheet.dart';
import 'entry/journal_inline_editor.dart';
import 'summary/history_editor.dart';
import 'l10n/app_localizations.dart';
import 'logic/calendar_days.dart';
import 'logic/hebrew_clock.dart';
import 'logic/id_generator.dart';
import 'logic/writing_journal.dart';
import 'models.dart';
import 'plan/plan_export.dart';
import 'settings/writing_journal_settings_screen.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/feedback.dart';

class WritingJournalScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;
  final Future<void> Function(Project project) onProjectCreated;
  final Future<void> Function(EntrySave save) onSave;
  final Future<void> Function(List<WorkSession>)? onHistoryCommitted;
  final bool embedded;
  final VoidCallback? onOpenTimer;

  const WritingJournalScreen({
    super.key,
    required this.projects,
    required this.history,
    required this.onProjectCreated,
    required this.onSave,
    this.embedded = false,
    this.onHistoryCommitted,
    this.onOpenTimer,
  });

  @override
  State<WritingJournalScreen> createState() => _WritingJournalScreenState();
}

class _WritingJournalScreenState extends State<WritingJournalScreen> {
  final StorageService _storage = StorageService();
  late List<Project> _projects;
  late List<WorkSession> _history;
  DateTime _anchor = DateTime.now();
  WritingJournalSettings _settings = WritingJournalSettings.defaults;
  DayStart _dayStart = DayStart.midnight;
  bool _loading = true;
  String? _editingKey;
  DateTime? _editingDay;
  JournalEntry? _editingEntry;

  @override
  void initState() {
    super.initState();
    _projects = [...widget.projects];
    _history = [...widget.history];
    _loadSettings();
  }

  @override
  void didUpdateWidget(covariant WritingJournalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projects != widget.projects ||
        oldWidget.history != widget.history) {
      _projects = [...widget.projects];
      _history = [...widget.history];
    }
  }

  Future<void> _loadSettings() async {
    final values = await Future.wait([
      _storage.getWritingJournalSettings(),
      _storage.getDayStart(),
    ]);
    if (!mounted) return;
    setState(() {
      _settings = values[0] as WritingJournalSettings;
      _dayStart = values[1] as DayStart;
      _loading = false;
    });
  }

  List<DateTime> get _days => WritingJournalLogic.weekDays(_anchor);

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WritingJournalSettingsScreen()),
    );
    await _loadSettings();
  }

  Future<void> _addEntry(DateTime day,
      {EntryDraft? draft, String notes = ''}) async {
    final storedLast = await _storage.getLastProjectId();
    if (!mounted) return;
    Project? initial;
    for (final project in _projects) {
      if (project.id == (draft?.projectId ?? storedLast)) initial = project;
    }
    initial ??= _projects.isEmpty ? null : _projects.first;

    final initialDraft = draft ??
        (initial == null
            ? null
            : EntryDraft(
                projectId: initial.id,
                entryId: IdGenerator.generate(),
                isManual: true,
                date: day,
              ));
    await showEntrySheet(
      context: context,
      isManual: true,
      projects: _projects,
      history: _history,
      useGregorianDates: _settings.dateDisplay == JournalDateDisplay.gregorian,
      dayStart: _dayStart,
      initialProject: initial,
      initialDraft: initialDraft,
      initialDate: day,
      onProjectCreated: (project) async {
        await widget.onProjectCreated(project);
        if (!mounted) return;
        setState(() {
          if (!_projects.any((current) => current.id == project.id)) {
            _projects.add(project);
          }
        });
      },
      onSave: (rawSave) async {
        final save = EntrySave(
            project: rawSave.project,
            sessions: [
              for (final s in rawSave.sessions)
                s.copyWith(extraFields: {...s.extraFields, 'entryNotes': notes})
            ],
            reachedPage: rawSave.reachedPage,
            reachedLine: rawSave.reachedLine,
            backlogOnly: rawSave.backlogOnly,
            tefillinWordEntry: rawSave.tefillinWordEntry,
            tefillinScript: rawSave.tefillinScript);
        await widget.onSave(save);
        if (!mounted) return;
        final entryIds = save.sessions
            .map((session) => session.entryId)
            .whereType<String>()
            .toSet();
        setState(() {
          _history = [
            for (final session in _history)
              if (session.entryId == null ||
                  !entryIds.contains(session.entryId))
                session,
            ...save.sessions,
          ];
        });
      },
    );
  }

  String _rowKey(DateTime day, JournalEntry? entry) =>
      '${day.toIso8601String()}/${entry?.key ?? 'new'}';

  void _beginInline(DateTime day, [JournalEntry? entry]) {
    if (_editingKey != null) return;
    setState(() {
      _editingKey = _rowKey(day, entry);
      _editingDay = day;
      _editingEntry = entry;
    });
  }

  void _closeInline() => setState(() {
        _editingKey = null;
        _editingDay = null;
        _editingEntry = null;
      });

  Future<void> _commitHistory(List<WorkSession> next) async {
    await _storage.saveHistory(next);
    if (mounted) setState(() => _history = next);
    try {
      await widget.onHistoryCommitted?.call(next);
    } catch (error) {
      debugPrint('Journal refresh after saved history failed: $error');
    }
  }

  Widget _inlineEditor() => JournalInlineEditor(
        key: ValueKey(_editingKey),
        day: _editingDay!,
        entry: _editingEntry,
        projects: _projects,
        history: _history,
        onClose: _closeInline,
        onAdd: (save) async {
          await widget.onSave(save);
          if (mounted) {
            setState(() => _history = [
                  for (final s in _history)
                    if (!save.sessions.any((added) => added.id == s.id)) s,
                  ...save.sessions
                ]);
          }
        },
        onEdit: (replacements) async {
          final entry = _editingEntry!;
          final ids = entry.sessions.map((s) => s.id).toSet();
          final notes = replacements
              .where((s) => !s.isDeleted)
              .first
              .extraFields['entryNotes'];
          final source = await _storage.loadHistory();
          await _commitHistory([
            for (final s in source)
              if (!ids.contains(s.id))
                if (entry.sessions.first.entryId != null &&
                    s.projectId == entry.projectId &&
                    s.entryId == entry.sessions.first.entryId &&
                    !s.isDeleted)
                  s.copyWith(
                      extraFields: {...s.extraFields, 'entryNotes': notes})
                else
                  s,
            ...replacements,
          ]);
        },
        onFullForm: (draft, notes) async {
          if (_editingEntry == null) {
            await _addEntry(_editingDay!, draft: draft, notes: notes);
          } else {
            await showHistoryEditor(
                context: context,
                projects: _projects,
                history: _history,
                day: _editingDay!,
                dayLabel: _dayLabel(_editingDay!),
                dayStart: _dayStart,
                useGregorianDates:
                    _settings.dateDisplay == JournalDateDisplay.gregorian,
                initialProjectId: _editingEntry!.projectId,
                onHistoryUpdated: (next) async {
                  final entry = _editingEntry!;
                  final ids = entry.sessions.map((s) => s.id).toSet();
                  await _commitHistory([
                    for (final s in next)
                      if (ids.contains(s.id) ||
                          (entry.sessions.first.entryId != null &&
                              s.projectId == entry.projectId &&
                              s.entryId == entry.sessions.first.entryId))
                        s.copyWith(extraFields: {
                          ...s.extraFields,
                          'entryNotes': notes
                        })
                      else
                        s
                  ]);
                });
          }
          if (mounted) _closeInline();
        },
      );

  Future<void> _print({required bool blank}) async {
    try {
      final table = WritingJournalLogic.exportWeek(
        anyDayInWeek: _anchor,
        projects: _projects,
        history: _history,
        dayStart: _dayStart,
        settings: _settings,
        english: context.l10n.isEnglish,
        blank: blank,
      );
      await Printing.layoutPdf(
        name: PlanExport.fileName(table, 'pdf'),
        onLayout: (_) => PlanExport.toPdf(table),
      );
    } catch (error) {
      if (mounted) {
        showAppError(
          context,
          context.l10n.pick(
            he: 'ההדפסה נכשלה: $error',
            en: 'Printing failed: $error',
          ),
        );
      }
    }
  }

  Future<void> _exportExcel() async {
    try {
      final table = WritingJournalLogic.exportWeek(
        anyDayInWeek: _anchor,
        projects: _projects,
        history: _history,
        dayStart: _dayStart,
        settings: _settings,
        english: context.l10n.isEnglish,
        blank: false,
      );
      final bytes = await PlanExport.toXlsx(table);
      if (!mounted) return;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: context.l10n.pick(
          he: 'שמירת יומן כתיבה',
          en: 'Save Writing Journal',
        ),
        fileName: PlanExport.fileName(table, 'xlsx'),
        bytes: bytes,
      );
      if (path == null) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (mounted) {
        showAppSuccess(
          context,
          context.l10n.pick(he: 'נשמר: $path', en: 'Saved: $path'),
        );
      }
    } catch (error) {
      if (mounted) {
        showAppError(
          context,
          context.l10n.pick(
            he: 'הייצוא נכשל: $error',
            en: 'Export failed: $error',
          ),
        );
      }
    }
  }

  List<Widget> _actions() => [
        PopupMenuButton<String>(
          tooltip:
              context.l10n.pick(he: 'הדפסה וייצוא', en: 'Print and export'),
          icon: const Icon(Icons.print_outlined),
          onSelected: (value) {
            if (value == 'blank') _print(blank: true);
            if (value == 'filled') _print(blank: false);
            if (value == 'excel') _exportExcel();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'blank',
              child: Text(context.l10n.pick(
                he: 'הדפס טבלה ריקה למילוי',
                en: 'Print a blank form',
              )),
            ),
            PopupMenuItem(
              value: 'filled',
              child: Text(context.l10n.pick(
                he: 'הדפס את השבוע המלא',
                en: 'Print the filled week',
              )),
            ),
            PopupMenuItem(
              value: 'excel',
              child: Text(context.l10n.pick(
                he: 'ייצא את השבוע ל־Excel',
                en: 'Export the week to Excel',
              )),
            ),
          ],
        ),
        IconButton(
          onPressed: _openSettings,
          tooltip: context.l10n.settings,
          icon: const Icon(Icons.tune),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _journalBody();
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.pick(he: 'יומן כתיבה', en: 'Writing Journal')),
        actions: _actions(),
      ),
      body: body,
    );
  }

  Widget _journalBody() {
    final days = _days;
    final parsha = WritingJournalLogic.weeklyParsha(
      days.last,
      inIsrael: _settings.inIsrael,
      english: context.l10n.isEnglish,
    );
    return Column(
      children: [
        _periodHeader(days, parsha),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // A physically wide tablet is not a wide layout when the writer
              // asked for 160–200% text. Cards preserve the full wording and
              // touch targets; the grid returns automatically when there is
              // genuinely enough measured text width.
              final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
              return constraints.maxWidth >= 760 * scale
                  ? _wideTable(days)
                  : _dayCards(days);
            },
          ),
        ),
      ],
    );
  }

  Widget _periodHeader(List<DateTime> days, String parsha) {
    final t = SoferTokens.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: t.paper,
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          IconButton(
            onPressed: _editingKey != null
                ? null
                : () =>
                    setState(() => _anchor = CalendarDays.addDays(_anchor, -7)),
            icon: Directionality.of(context) == TextDirection.rtl
                ? const Icon(Icons.chevron_right)
                : const Icon(Icons.chevron_left),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${WritingJournalLogic.dateLabel(days.first, _settings.dateDisplay, english: context.l10n.isEnglish)} – '
                '${WritingJournalLogic.dateLabel(days.last, _settings.dateDisplay, english: context.l10n.isEnglish)}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (_settings.showParsha && parsha.isNotEmpty)
                Text(
                  context.l10n.pick(he: 'פרשת $parsha', en: 'Parashat $parsha'),
                  style: TextStyle(color: t.inkMuted),
                ),
            ],
          ),
          IconButton(
            onPressed: _editingKey != null
                ? null
                : () =>
                    setState(() => _anchor = CalendarDays.addDays(_anchor, 7)),
            icon: Directionality.of(context) == TextDirection.rtl
                ? const Icon(Icons.chevron_left)
                : const Icon(Icons.chevron_right),
          ),
          TextButton(
            onPressed: _editingKey != null
                ? null
                : () => setState(() => _anchor = DateTime.now()),
            child: Text(context.l10n.pick(he: 'השבוע', en: 'This week')),
          ),
          if (widget.embedded && widget.onOpenTimer != null)
            OutlinedButton.icon(
              onPressed: widget.onOpenTimer,
              icon: const Icon(Icons.timer_outlined),
              label: Text(context.l10n.pick(
                he: 'מסך הטיימר',
                en: 'Timer screen',
              )),
            ),
          if (widget.embedded) ..._actions(),
        ],
      ),
    );
  }

  Widget _wideTable(List<DateTime> days) {
    final t = SoferTokens.of(context);
    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(color: t.paper),
        children: [
          _heading(context.l10n.pick(he: 'יום ותאריך', en: 'Day and date')),
          if (_settings.showProject)
            _heading(context.l10n.pick(he: 'פרויקט', en: 'Project')),
          _heading(context.l10n.pick(he: 'מה נכתב', en: 'Written')),
          if (_settings.showTime)
            _heading(context.l10n.pick(he: 'זמן כתיבה', en: 'Writing time')),
          if (_settings.showNotes)
            _heading(context.l10n.pick(he: 'הערות', en: 'Notes')),
        ],
      ),
    ];
    for (final day in days) {
      final sessions =
          WritingJournalLogic.entriesOnDay(_history, day, _dayStart);
      if (sessions.isEmpty) {
        rows.add(_tableRow(day, null, firstForDay: true));
        if (_editingKey == _rowKey(day, null)) rows.add(_editorTableRow());
      } else {
        for (var i = 0; i < sessions.length; i++) {
          rows.add(_tableRow(day, sessions[i], firstForDay: i == 0));
          if (_editingKey == _rowKey(day, sessions[i])) {
            rows.add(_editorTableRow());
          }
        }
        rows.add(_tableRow(day, null, firstForDay: false));
        if (_editingKey == _rowKey(day, null)) rows.add(_editorTableRow());
      }
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Table(
        border: TableBorder.all(color: t.rule),
        columnWidths: {
          0: const FlexColumnWidth(1.5),
          if (_settings.showProject) 1: const FlexColumnWidth(1.4),
          (_settings.showProject ? 2 : 1): const FlexColumnWidth(3),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: rows,
      ),
    );
  }

  TableRow _editorTableRow() => TableRow(children: [
        _cell(''),
        if (_settings.showProject) _cell(''),
        _inlineEditor(),
        if (_settings.showTime) _cell(''),
        if (_settings.showNotes) _cell(''),
      ]);

  TableRow _tableRow(DateTime day, JournalEntry? session,
      {required bool firstForDay}) {
    final project = session == null ? null : _projectFor(session.projectId);
    return TableRow(children: [
      _cell(firstForDay ? _dayLabel(day) : ''),
      if (_settings.showProject) _cell(project?.name ?? ''),
      _cell(
        session?.descriptionFor(project, english: context.l10n.isEnglish) ??
            context.l10n.pick(he: '+ הוסף רשומה', en: '+ Add entry'),
        onTap: () => _beginInline(day, session),
        accent: session == null,
      ),
      if (_settings.showTime)
        _cell(session == null
            ? ''
            : session.durationLabel(english: context.l10n.isEnglish)),
      if (_settings.showNotes)
        _cell(session?.notes ?? '', onTap: () => _beginInline(day, session)),
    ]);
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.all(10),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _cell(String text, {VoidCallback? onTap, bool accent = false}) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Text(
        text,
        style: accent
            ? TextStyle(
                color: SoferTokens.of(context).accent,
                fontWeight: FontWeight.w600)
            : null,
      ),
    );
    return onTap == null ? child : InkWell(onTap: onTap, child: child);
  }

  Widget _dayCards(List<DateTime> days) => ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: days.length,
        itemBuilder: (context, index) {
          final day = days[index];
          final sessions =
              WritingJournalLogic.entriesOnDay(_history, day, _dayStart);
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_dayLabel(day),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  if (sessions.isEmpty)
                    Text(
                      context.l10n.pick(
                        he: 'עדיין לא הוזנה כתיבה ביום זה',
                        en: 'No writing has been entered for this day',
                      ),
                      style: TextStyle(color: SoferTokens.of(context).inkMuted),
                    )
                  else
                    for (final session in sessions) ...[
                      _sessionTile(day, session),
                      if (_editingKey == _rowKey(day, session)) _inlineEditor(),
                    ],
                  if (_editingKey == _rowKey(day, null)) _inlineEditor(),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => _beginInline(day),
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n.pick(
                        he: 'הוסף רשומה',
                        en: 'Add entry',
                      )),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _sessionTile(DateTime day, JournalEntry session) {
    final project = _projectFor(session.projectId);
    final detail = <String>[
      if (_settings.showProject && project != null) project.name,
      if (_settings.showTime)
        session.durationLabel(english: context.l10n.isEnglish),
      if (_settings.showNotes && session.notes.isNotEmpty) session.notes,
    ].join(' · ');
    return ListTile(
      onTap: () => _beginInline(day, session),
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.edit_note),
      title: Text(
          session.descriptionFor(project, english: context.l10n.isEnglish)),
      subtitle: detail.isEmpty ? null : Text(detail),
    );
  }

  String _dayLabel(DateTime day) {
    final weekday = context.l10n.isEnglish
        ? const [
            'Sunday',
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Shabbat'
          ][day.weekday % 7]
        : const [
            'ראשון',
            'שני',
            'שלישי',
            'רביעי',
            'חמישי',
            'שישי',
            'שבת'
          ][day.weekday % 7];
    return '$weekday · ${WritingJournalLogic.dateLabel(day, _settings.dateDisplay, english: context.l10n.isEnglish)}';
  }

  Project? _projectFor(String id) {
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }
}
