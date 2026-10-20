import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/currency.dart';
import '../logic/id_generator.dart';
import '../logic/proofread_board.dart';
import '../models.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm.dart';
import '../widgets/feedback.dart';
import '../widgets/sofer_widgets.dart';
import 'proofread_editor.dart';
import '../l10n/app_localizations.dart';

/// Proofreading, laid out by stage.
///
/// The stage of the job the app had been charging for and not recording. Four
/// columns in the order the work moves, so a batch travels left along the board
/// as it goes out and comes back.
///
/// The question a sofer opens this to answer is not "what exists" but **whose
/// turn is it** — so what is waiting on him is stated at the top in words,
/// before any of the columns.
class ProofreadScreen extends StatefulWidget {
  final List<Project> projects;

  const ProofreadScreen({super.key, required this.projects});

  @override
  State<ProofreadScreen> createState() => _ProofreadScreenState();
}

class _ProofreadScreenState extends State<ProofreadScreen> {
  final StorageService _storage = StorageService();
  List<Proofread> _all = const [];
  Currency _currency = Currency.ils;
  bool _useGregorianDates = false;
  bool _loaded = false;

  /// Null means every commission.
  String? _projectId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _storage.loadProofreads();
    final currency = await _storage.getCurrency();
    final gregorian = await _storage.getUseGregorianDates();
    if (!mounted) return;
    setState(() {
      _all = all;
      _currency = currency;
      _useGregorianDates = gregorian;
      _loaded = true;
    });
  }

  Project? _projectOf(String id) {
    for (final p in widget.projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _save(Proofread record) async {
    // The stored list, not the filtered view: saving what is on screen would
    // be saving a subset, and a save must never mean "and nothing else exists".
    final next = [..._all];
    final at = next.indexWhere((r) => r.id == record.id);
    if (at == -1) {
      next.add(record);
    } else {
      next[at] = record;
    }
    await _storage.saveProofreads(next);
    if (!mounted) return;
    setState(() => _all = next);
  }

  Future<void> _edit({Proofread? existing}) async {
    final live = widget.projects.where((p) => !p.isDeleted).toList();
    // Only a *new* record needs a commission to attach to. Blocking the editor
    // outright also blocked correcting or deleting a record that already
    // existed, which is exactly what a writer wants after deleting the job.
    if (live.isEmpty && existing == null) {
      showAppNote(
          context,
          context.l10n.pick(
              he: "צריך פרויקט אחד לפחות כדי לרשום הגהה",
              en: "At least one project is required to record proofreading"));
      return;
    }

    await showProofreadEditor(
      context: context,
      existing: existing,
      projects: live,
      currency: _currency,
      useGregorianDates: _useGregorianDates,
      defaultProjectId: _projectId ?? (live.isNotEmpty ? live.first.id : ''),
      onCommit: (result) async {
        if (result.deleted) {
          final sure = await confirmAction(context,
              title: context.l10n.pick(
                  he: 'מחיקת רשומת הגהה', en: 'Delete proofreading record'),
              message: context.l10n.pick(
                  he: 'הרשומה תעבור לסל המיחזור ולא תיספר בעלויות.',
                  en: 'The record will move to the Recycle Bin and will not be included in costs.'),
              confirmLabel: context.l10n.pick(he: 'מחק', en: 'Delete'),
              danger: true);
          if (!sure) return false;
        }
        await _save(result.deleted
            ? result.record.copyWith(isDeleted: true)
            : result.record);
        return true;
      },
    );
  }

  /// Moves a batch to the next stage, stamping the date that stage happened.
  ///
  /// The dates are what the board is worth anything for — how long something
  /// has been out, and how long it took — and asking a writer to type them when
  /// the app is watching him press the button would be asking for what it
  /// already knows.
  Future<void> _advance(Proofread r) async {
    final now = DateTime.now();
    final next = switch (r.stage) {
      ProofreadStage.waiting =>
        r.copyWith(stage: ProofreadStage.sent, sentAt: r.sentAt ?? now),
      ProofreadStage.sent => r.copyWith(
          stage: ProofreadStage.returned, returnedAt: r.returnedAt ?? now),
      ProofreadStage.returned =>
        r.copyWith(stage: ProofreadStage.done, doneAt: r.doneAt ?? now),
      ProofreadStage.done => r,
    };
    if (identical(next, r)) return;
    try {
      await _save(next);
    } catch (error) {
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'עדכון ההגהה נכשל: $error',
                en: 'Proofreading update failed: $error'));
      }
    }
  }

  String get _title {
    final id = _projectId;
    if (id == null) {
      return context.l10n.pick(he: "מעקב הגהה", en: "Proofreading Tracker");
    }
    return _projectOf(id)?.name ??
        context.l10n.pick(he: "מעקב הגהה", en: "Proofreading Tracker");
  }

  @override
  Widget build(BuildContext context) {
    final board = ProofreadBoard.of(_all, projectId: _projectId);
    final live = widget.projects.where((p) => !p.isDeleted).toList();

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(
            context.l10n.pick(he: "הגהה חדשה", en: "New proofreading batch")),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SoferPage(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  if (live.length > 1) _projectPicker(live),
                  _summary(board),
                  const SizedBox(height: 8),
                  for (final stage in ProofreadStage.values)
                    _column(board, stage),
                  if (board.records.isEmpty) _empty(),
                ],
              ),
            ),
    );
  }

  Widget _projectPicker(List<Project> live) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<String?>(
          initialValue: _projectId,
          isExpanded: true,
          decoration: InputDecoration(
            border: const UnderlineInputBorder(),
            labelText: context.l10n.pick(he: "פרויקט", en: "Project"),
          ),
          items: [
            DropdownMenuItem(
                value: null,
                child: Text(
                    context.l10n.pick(he: "כל הפרויקטים", en: "All projects"))),
            for (final p in live)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: (v) => setState(() => _projectId = v),
        ),
      );

  /// Whose turn it is, in a sentence, before any column.
  Widget _summary(ProofreadBoard board) {
    final t = SoferTokens.of(context);
    final mine = board.mine.length;
    final out = board.at(ProofreadStage.sent).length;
    final late = board.overdue().length;

    final lines = <String>[
      if (mine > 0)
        context.l10n.pick(
            he: "$mine ממתינות לך", en: "$mine awaiting your corrections"),
      if (out > 0)
        context.l10n
            .pick(he: "$out אצל המגיה", en: "$out with the proofreader"),
      if (mine == 0 && out == 0 && board.records.isNotEmpty)
        context.l10n.pick(he: "הכול הושלם", en: "Everything is complete"),
    ];

    return SoferPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isNotEmpty)
            Text(lines.join(' · '),
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 19, color: t.ink)),
          if (late > 0) ...[
            const SizedBox(height: 6),
            Text(
                context.l10n.pick(
                    he: "$late יצאו לפני יותר משלושה שבועות ולא חזרו",
                    en: "$late have been with the proofreader for more than three weeks"),
                style: TextStyle(fontSize: 13.5, color: t.danger)),
          ],
          if (!board.spent.isEmpty) ...[
            const SizedBox(height: 10),
            SoferStatRow(
                context.l10n.pick(he: "עלות הגהה", en: "Proofreading cost"),
                board.spent.format(_currency),
                last: board.averageFindings == null),
          ],
          if (board.averageFindings != null)
            SoferStatRow(
                context.l10n.pick(
                    he: "ממוצע תיקונים לאצווה",
                    en: "Average corrections per batch"),
                board.averageFindings!.toStringAsFixed(1),
                last: true),
        ],
      ),
    );
  }

  Widget _column(ProofreadBoard board, ProofreadStage stage) {
    final records = board.at(stage).toList();
    if (records.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SoferSectionTitle(
            "${context.l10n.proofreadingStage(stage.label)} (${records.length})"),
        for (final r in records) _card(r),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _card(Proofread r) {
    final t = SoferTokens.of(context);
    final project = _projectOf(r.projectId);
    final out = r.turnaround();
    final late =
        r.stage == ProofreadStage.sent && out != null && out.inDays > 21;

    final facts = <String>[
      if (_projectId == null && project != null) project.name,
      if (r.proofreader.isNotEmpty) r.proofreader,
      if (r.stage == ProofreadStage.sent && out != null)
        context.l10n.pick(
            he: "בחוץ ${out.inDays} ימים", en: "Out for ${out.inDays} days"),
      if (r.stage != ProofreadStage.sent && r.sentAt != null)
        context.l10n.pick(
          he: "נשלח ${formatDisplayDate(r.sentAt!, _useGregorianDates)}",
          en: "Sent ${formatDisplayDate(r.sentAt!, _useGregorianDates, english: true)}",
        ),
      if (r.findings != null)
        context.l10n
            .pick(he: "${r.findings} תיקונים", en: "${r.findings} corrections"),
      if (r.cost > 0) r.currency.format(r.cost),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoferPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.scope.isEmpty
                        ? context.l10n.pick(he: "ללא פירוט", en: "No details")
                        : r.scope,
                    style: TextStyle(
                      fontFamily: t.numeralFamily,
                      fontSize: 17,
                      color: r.scope.isEmpty ? t.inkMuted : t.ink,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: context.l10n.pick(he: "עריכה", en: "Edit"),
                  onPressed: () => _edit(existing: r),
                ),
              ],
            ),
            if (facts.isNotEmpty)
              Text(facts.join(' · '),
                  style: TextStyle(
                      fontSize: 13.5, color: late ? t.danger : t.inkMuted)),
            if (r.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.notes,
                  style: TextStyle(fontSize: 13.5, color: t.inkMuted)),
            ],
            if (r.stage.isOpen) ...[
              const SizedBox(height: 10),
              SoferSecondaryButton(
                _advanceLabel(context, r.stage),
                icon: Directionality.of(context) == TextDirection.rtl
                    ? Icons.arrow_back
                    : Icons.arrow_forward,
                expand: true,
                onPressed: () => _advance(r),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _advanceLabel(BuildContext context, ProofreadStage stage) =>
      switch (stage) {
        ProofreadStage.waiting =>
          context.l10n.pick(he: "נשלח למגיה", en: "Sent to Proofreader"),
        ProofreadStage.sent =>
          context.l10n.pick(he: "חזר מהמגיה", en: "Returned from Proofreader"),
        ProofreadStage.returned =>
          context.l10n.pick(he: "התיקונים הושלמו", en: "Corrections Completed"),
        ProofreadStage.done => "",
      };

  Widget _empty() {
    final t = SoferTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(
              context.l10n
                  .pick(he: "אין רשומות הגהה", en: "No proofreading records"),
              style: TextStyle(
                  fontFamily: t.numeralFamily, fontSize: 20, color: t.ink)),
          const SizedBox(height: 8),
          Text(
            context.l10n.pick(
              he: "כאן נרשם מה נשלח למגיה, מתי, מה חזר וכמה זה עלה.",
              en: "Record what was sent to the proofreader, when it was sent, what came back, and what it cost.",
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.6, color: t.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// What the editor gave back.
class ProofreadEdit {
  final Proofread record;
  final bool deleted;

  const ProofreadEdit(this.record, {this.deleted = false});
}

/// A new record, with the fields a writer would fill in first.
Proofread newProofread(String projectId, Currency currency) => Proofread(
      id: IdGenerator.generate(),
      projectId: projectId,
      currency: currency,
    );
