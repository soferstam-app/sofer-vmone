import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../logic/entry_builder.dart';
import '../logic/id_generator.dart';
import '../logic/production_calculator.dart';
import '../logic/session_logic.dart';
import '../logic/writing_journal.dart';
import '../models.dart';
import '../widgets/confirm.dart';
import 'entry_sheet.dart';
import 'entry_draft.dart';

/// Transient fields live in the journal row until storage accepts the save.
class JournalInlineEditor extends StatefulWidget {
  final DateTime day;
  final JournalEntry? entry;
  final List<Project> projects;
  final List<WorkSession> history;
  final Future<void> Function(EntrySave) onAdd;
  final Future<void> Function(List<WorkSession>) onEdit;
  final VoidCallback onClose;
  final Future<void> Function(EntryDraft?, String) onFullForm;

  const JournalInlineEditor({
    super.key,
    required this.day,
    this.entry,
    required this.projects,
    required this.history,
    required this.onAdd,
    required this.onEdit,
    required this.onClose,
    required this.onFullForm,
  });

  @override
  State<JournalInlineEditor> createState() => _JournalInlineEditorState();
}

class _JournalInlineEditorState extends State<JournalInlineEditor> {
  Project? _project;
  late final TextEditingController _from;
  late final TextEditingController _to;
  late final TextEditingController _firstLine;
  late final TextEditingController _lastLine;
  late final TextEditingController _amount;
  late final TextEditingController _minutes;
  late final TextEditingController _notes;
  late final String _initialMinutes;
  late final List<String> _initialOutput;
  late final String _entryId;
  bool _recordTime = false;
  bool _saving = false;
  String? _error;
  String _mode = 'set';

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    final slices = entry?.sessions ?? const <WorkSession>[];
    for (final p in widget.projects) {
      if (p.id == entry?.projectId) _project = p;
    }
    if (entry == null && widget.projects.isNotEmpty) {
      _project = widget.projects.first;
    }
    final ordered = [...slices]..sort((a, b) => a.amount.compareTo(b.amount));
    final first = ordered.isEmpty ? null : ordered.first;
    final last = ordered.isEmpty ? null : ordered.last;
    _from = TextEditingController(text: first?.amount.toString() ?? '');
    _to = TextEditingController(text: last?.amount.toString() ?? '');
    _firstLine = TextEditingController(text: first?.startLine.toString() ?? '');
    _lastLine = TextEditingController(text: last?.endLine.toString() ?? '');
    _amount = TextEditingController(text: first?.amount.toString() ?? '');
    _initialMinutes =
        entry == null ? '' : (entry.duration.inMilliseconds / 60000).toString();
    _minutes = TextEditingController(text: _initialMinutes);
    _notes = TextEditingController(text: entry?.notes ?? '');
    _recordTime = entry?.timeRecorded ?? false;
    _entryId = slices.isEmpty
        ? IdGenerator.generate()
        : slices.first.entryId ?? IdGenerator.generate();
    _mode = first?.tefillinType ?? 'set';
    _initialOutput = _output;
  }

  List<String> get _output => [
        _from.text,
        _to.text,
        _firstLine.text,
        _lastLine.text,
        _amount.text,
        _mode
      ];

  bool get _simpleOutput {
    final p = _project;
    if (p == null) return false;
    final entry = widget.entry;
    if (entry == null) return true;
    final sessions = entry.sessions;
    if (sessions.any((s) => s.isInvalid || s.isPartialLine || s.backlogOnly)) {
      return false;
    }
    if (p.type.isPaged) {
      final sorted = [...sessions]
        ..sort((a, b) => a.amount.compareTo(b.amount));
      final lines = ProductionCalculator.linesPerPageOf(p);
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].linesPerPageAtEntry != null &&
            sorted[i].linesPerPageAtEntry != lines) {
          return false;
        }
        if (i > 0 &&
            (sorted[i].amount != sorted[i - 1].amount + 1 ||
                sorted[i].startLine != 1 ||
                sorted[i - 1].endLine != lines)) {
          return false;
        }
      }
      return true;
    }
    return sessions.length == 1 &&
        sessions.first.mezuzaIndex == null &&
        sessions.first.pairIndex == null &&
        sessions.first.parshiya == null &&
        sessions.first.startLine == 0 &&
        sessions.first.endLine == 0;
  }

  Future<void> _save() async {
    if (_saving || (_project == null && widget.entry == null)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final parsedMinutes = double.tryParse(_minutes.text.trim());
      if (_recordTime &&
          (parsedMinutes == null ||
              !parsedMinutes.isFinite ||
              parsedMinutes < 0 ||
              parsedMinutes > 7 * 24 * 60)) {
        throw FormatException(context.l10n.pick(
            he: 'יש להזין זמן תקין בדקות (עד שבוע)',
            en: 'Enter valid minutes (up to one week)'));
      }
      final duration = _recordTime
          ? Duration(milliseconds: (parsedMinutes! * 60000).round())
          : Duration.zero;
      final entry = widget.entry;
      final original = entry?.sessions ?? const <WorkSession>[];
      final start = original.isEmpty
          ? DateTime(widget.day.year, widget.day.month, widget.day.day, 12)
          : original.first.startTime;
      final outputChanged = entry == null ||
          List.generate(_output.length, (i) => _output[i] != _initialOutput[i])
              .any((v) => v);
      EntryBuilt? built;
      if (outputChanged && _simpleOutput) {
        final ids = original.map((s) => s.id).toSet();
        final result = EntryBuilder.build(
            input: EntryInput(
              project: _project!,
              start: start,
              end: start.add(duration),
              statedDate: widget.day,
              isManual: true,
              timeRecorded: _recordTime,
              timeOfDayKnown: false,
              entryId: _entryId,
              pageFrom: _from.text,
              pageTo: _to.text,
              lineFrom: _firstLine.text,
              lineTo: _lastLine.text,
              amount: _amount.text,
              tefillinMode: _mode,
            ),
            history: widget.history.where((s) => !ids.contains(s.id)));
        if (result is EntryRejected) {
          throw FormatException(context.l10n.businessMessage(result.message));
        }
        built = result as EntryBuilt;
        if (built.overlapsRecordedWork) {
          if (!await confirmOverlap(context,
              pages: built.sessions.map((s) => s.amount).toList())) {
            return;
          }
          if (!mounted) return;
        }
      }
      var replacements = built?.sessions ?? original;
      final timeChanged = entry != null &&
          (_recordTime != entry.timeRecorded ||
              _minutes.text != _initialMinutes);
      if (built == null && timeChanged) {
        final measured = original.fold<int>(
            0,
            (sum, s) =>
                sum +
                (s.timeRecorded && !s.duration.isNegative
                    ? s.duration.inMilliseconds
                    : 0));
        final ranges = SessionLogic.splitByWeight(
            start: start,
            end: start.add(duration),
            weights: [
              for (final s in original)
                measured == 0
                    ? 1
                    : (s.timeRecorded && !s.duration.isNegative
                        ? s.duration.inMilliseconds
                        : 0)
            ]);
        replacements = [
          for (var i = 0; i < original.length; i++)
            WorkSession.fromJson({
              ...original[i]
                  .copyWith(
                      startTime: ranges[i].start,
                      endTime: ranges[i].end,
                      timeRecorded: _recordTime,
                      timeOfDayKnown: false)
                  .toJson(),
              'dayRule': null,
              'workingDateAtEntry': widget.day.toIso8601String(),
              'isManual': true
            })
        ];
      }
      // Reuse record identities when their physical page remains in the entry.
      // Removed slices become tombstones so backup merge cannot revive them.
      final used = <String>{};
      replacements = [
        for (final s in replacements) _withOriginalIdentity(s, original, used)
      ];
      final next = [
        for (final old in original)
          if (!used.contains(old.id)) old.copyWith(isDeleted: true),
        for (final s in replacements)
          s.copyWith(extraFields: {
            ...s.extraFields,
            'entryNotes': _notes.text.trim()
          }),
      ];
      if (entry == null) {
        await widget.onAdd(EntrySave(
            project: _project!,
            sessions: next,
            reachedPage: built!.reachedPage,
            reachedLine: built.reachedLine,
            backlogOnly: false));
      } else {
        await widget.onEdit(next);
      }
      if (mounted) widget.onClose();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  WorkSession _withOriginalIdentity(
      WorkSession next, List<WorkSession> original, Set<String> used) {
    WorkSession? match;
    for (final old in original) {
      if (!used.contains(old.id) &&
          (next.id == old.id ||
              (_project!.type.isPaged && next.amount == old.amount) ||
              (!_project!.type.isPaged && original.length == 1))) {
        match = old;
        break;
      }
    }
    if (match == null) return next;
    used.add(match.id);
    // Notes/time editing retains every output and extension field. A rebuilt
    // range retains its new output and carries old extensions and identity.
    return WorkSession.fromJson({
      ...match.extraFields,
      ...next.toJson(),
      'id': match.id,
      'deletedAt': match.deletedAt?.toIso8601String(),
      'restoredAt': match.restoredAt?.toIso8601String(),
    });
  }

  Widget _field(
          TextEditingController controller, String he, String en) =>
      SizedBox(
          width: 155,
          child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: context.l10n.pick(he: he, en: en),
                  border: const OutlineInputBorder())));

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: AbsorbPointer(
            absorbing: _saving,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_saving) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (widget.entry == null)
                  DropdownButtonFormField<Project>(
                    initialValue: _project,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText:
                            context.l10n.pick(he: 'פרויקט', en: 'Project')),
                    items: [
                      for (final p in widget.projects)
                        DropdownMenuItem(value: p, child: Text(p.name))
                    ],
                    onChanged: (p) => setState(() => _project = p),
                  )
                else
                  Text(_project?.name ??
                      context.l10n.pick(
                          he: 'פרויקט שאינו זמין', en: 'Unavailable project')),
                const SizedBox(height: 10),
                if (_simpleOutput)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (_project?.type.isPaged == true) ...[
                      _field(_from, 'מעמוד', 'From page'),
                      _field(_to, 'עד עמוד', 'Through page'),
                      _field(_firstLine, 'משורה', 'From line'),
                      _field(_lastLine, 'עד שורה', 'Through line'),
                    ] else ...[
                      _field(_amount, 'כמות', 'Quantity'),
                      if (_project?.type == ProjectType.tefillin)
                        SizedBox(
                            width: 180,
                            child: DropdownButtonFormField<String>(
                                initialValue: _mode,
                                items: [
                                  DropdownMenuItem(
                                      value: 'set',
                                      child: Text(context.l10n
                                          .pick(he: 'זוגות', en: 'Sets'))),
                                  DropdownMenuItem(
                                      value: 'head',
                                      child: Text(context.l10n
                                          .pick(he: 'ראש', en: 'Shel Rosh'))),
                                  DropdownMenuItem(
                                      value: 'hand',
                                      child: Text(context.l10n
                                          .pick(he: 'יד', en: 'Shel Yad'))),
                                ],
                                onChanged: (v) =>
                                    setState(() => _mode = v ?? _mode))),
                    ],
                  ])
                else
                  Text(widget.entry?.description ??
                      context.l10n.pick(
                          he: 'בחר פרויקט או פתח טופס מלא',
                          en: 'Choose a project or open the full form')),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _recordTime,
                    title: Text(context.l10n.pick(
                        he: 'כולל זמן כתיבה', en: 'Include writing time')),
                    onChanged: (v) => setState(() => _recordTime = v ?? false)),
                if (_recordTime) _field(_minutes, 'זמן בדקות', 'Minutes'),
                const SizedBox(height: 8),
                TextField(
                    controller: _notes,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                        labelText: context.l10n.pick(he: 'הערות', en: 'Notes'),
                        border: const OutlineInputBorder())),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  FilledButton(
                      onPressed: _project == null && widget.entry == null
                          ? null
                          : _save,
                      child: Text(
                          context.l10n.pick(he: 'שמור שורה', en: 'Save row'))),
                  OutlinedButton(
                      onPressed: () async {
                        try {
                          final minutes = double.tryParse(_minutes.text.trim());
                          if (_recordTime &&
                              (minutes == null ||
                                  !minutes.isFinite ||
                                  minutes < 0 ||
                                  minutes > 7 * 24 * 60)) {
                            throw FormatException(context.l10n.pick(
                                he: 'יש להזין זמן תקין בדקות (עד שבוע)',
                                en: 'Enter valid minutes (up to one week)'));
                          }
                          await widget.onFullForm(
                              widget.entry == null && _project != null
                                  ? EntryDraft(
                                      projectId: _project!.id,
                                      entryId: _entryId,
                                      isManual: true,
                                      date: widget.day,
                                      includeTime: _recordTime,
                                      worked: Duration(
                                          milliseconds: _recordTime
                                              ? ((minutes ?? 0) * 60000).round()
                                              : 0),
                                      pageFrom: _from.text,
                                      pageTo: _to.text,
                                      lineFrom: _firstLine.text,
                                      lineTo: _lastLine.text,
                                      amount: _amount.text,
                                      tefillinMode: _mode,
                                    )
                                  : null,
                              _notes.text.trim());
                        } catch (error) {
                          if (mounted) setState(() => _error = '$error');
                        }
                      },
                      child: Text(
                          context.l10n.pick(he: 'טופס מלא', en: 'Full form'))),
                  TextButton(
                      onPressed: widget.onClose,
                      child: Text(context.l10n.cancel)),
                ]),
              ],
            )),
      );

  @override
  void dispose() {
    for (final c in [
      _from,
      _to,
      _firstLine,
      _lastLine,
      _amount,
      _minutes,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
