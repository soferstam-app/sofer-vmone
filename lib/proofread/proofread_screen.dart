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
    if (live.isEmpty) {
      showAppNote(context, "צריך פרויקט אחד לפחות כדי לרשום הגהה");
      return;
    }

    final result = await showProofreadEditor(
      context: context,
      existing: existing,
      projects: live,
      currency: _currency,
      useGregorianDates: _useGregorianDates,
      defaultProjectId: _projectId ?? live.first.id,
    );
    if (result == null || !mounted) return;

    if (result.deleted) {
      final sure = await confirmAction(
        context,
        title: "מחיקת רשומת הגהה",
        message: "הרשומה תעבור לסל המיחזור ולא תיספר בעלויות.",
        confirmLabel: "מחק",
        danger: true,
      );
      if (!sure || !mounted) return;
      await _save(result.record.copyWith(isDeleted: true));
      if (mounted) showAppSuccess(context, "נמחק");
      return;
    }

    await _save(result.record);
    if (mounted) showAppSuccess(context, "נשמר");
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
    await _save(next);
  }

  String get _title {
    final id = _projectId;
    if (id == null) return "מעקב הגהה";
    return _projectOf(id)?.name ?? "מעקב הגהה";
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
        label: const Text("הגהה חדשה"),
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
          decoration: const InputDecoration(
            border: UnderlineInputBorder(),
            labelText: "פרויקט",
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text("כל הפרויקטים")),
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
      if (mine > 0) "$mine ממתינות לך",
      if (out > 0) "$out אצל המגיה",
      if (mine == 0 && out == 0 && board.records.isNotEmpty) "הכול הושלם",
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
            Text("$late יצאו לפני יותר משלושה שבועות ולא חזרו",
                style: TextStyle(fontSize: 13.5, color: t.danger)),
          ],
          if (!board.spent.isEmpty) ...[
            const SizedBox(height: 10),
            SoferStatRow("עלות הגהה", board.spent.format(_currency),
                last: board.averageFindings == null),
          ],
          if (board.averageFindings != null)
            SoferStatRow("ממוצע תיקונים לאצווה",
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
        SoferSectionTitle("${stage.label} (${records.length})"),
        for (final r in records) _card(r),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _card(Proofread r) {
    final t = SoferTokens.of(context);
    final project = _projectOf(r.projectId);
    final out = r.turnaround();
    final late = r.stage == ProofreadStage.sent &&
        out != null &&
        out.inDays > 21;

    final facts = <String>[
      if (_projectId == null && project != null) project.name,
      if (r.proofreader.isNotEmpty) r.proofreader,
      if (r.stage == ProofreadStage.sent && out != null)
        "בחוץ ${out.inDays} ימים",
      if (r.stage != ProofreadStage.sent && r.sentAt != null)
        "נשלח ${formatDisplayDate(r.sentAt!, _useGregorianDates)}",
      if (r.findings != null) "${r.findings} תיקונים",
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
                    r.scope.isEmpty ? "ללא פירוט" : r.scope,
                    style: TextStyle(
                      fontFamily: t.numeralFamily,
                      fontSize: 17,
                      color: r.scope.isEmpty ? t.inkMuted : t.ink,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: "עריכה",
                  onPressed: () => _edit(existing: r),
                ),
              ],
            ),
            if (facts.isNotEmpty)
              Text(facts.join(' · '),
                  style: TextStyle(
                      fontSize: 13.5,
                      color: late ? t.danger : t.inkMuted)),
            if (r.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.notes,
                  style: TextStyle(fontSize: 13.5, color: t.inkMuted)),
            ],
            if (r.stage.isOpen) ...[
              const SizedBox(height: 10),
              SoferSecondaryButton(
                _advanceLabel(r.stage),
                icon: Icons.arrow_back,
                expand: true,
                onPressed: () => _advance(r),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _advanceLabel(ProofreadStage stage) => switch (stage) {
        ProofreadStage.waiting => "נשלח למגיה",
        ProofreadStage.sent => "חזר מהמגיה",
        ProofreadStage.returned => "התיקונים הושלמו",
        ProofreadStage.done => "",
      };

  Widget _empty() {
    final t = SoferTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text("אין רשומות הגהה",
              style: TextStyle(
                  fontFamily: t.numeralFamily, fontSize: 20, color: t.ink)),
          const SizedBox(height: 8),
          Text(
            "כאן נרשם מה נשלח למגיה, מתי, מה חזר וכמה זה עלה.",
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
