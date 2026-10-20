import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/currency.dart';
import '../logic/money_input.dart';
import '../models.dart';
import 'proofread_screen.dart';
import '../l10n/app_localizations.dart';

/// Entering or changing one batch of proofreading.
///
/// Deliberately short. What a sofer knows when he hands the work over is which
/// commission, roughly what he sent, and to whom; the cost and the corrections
/// are only known later, and asking for them up front would make the form look
/// like it wanted answers he does not have yet.
Future<ProofreadEdit?> showProofreadEditor({
  required BuildContext context,
  Future<bool> Function(ProofreadEdit)? onCommit,
  required List<Project> projects,
  required Currency currency,
  required bool useGregorianDates,
  required String defaultProjectId,
  Proofread? existing,
}) async {
  final isEdit = existing != null;
  final record = existing ?? newProofread(defaultProjectId, currency);

  final scopeCtrl = TextEditingController(text: record.scope);
  final proofreaderCtrl = TextEditingController(text: record.proofreader);
  final costCtrl =
      TextEditingController(text: record.cost > 0 ? '${record.cost}' : '');
  final findingsCtrl =
      TextEditingController(text: record.findings?.toString() ?? '');
  final notesCtrl = TextEditingController(text: record.notes);

  var projectId = record.projectId;
  var stage = record.stage;
  var sentAt = record.sentAt;
  var returnedAt = record.returnedAt;
  String? costError;

  var saving = false;
  final route = DialogRoute<ProofreadEdit>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> pick(
            DateTime? current, void Function(DateTime) apply) async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: current ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (d != null) setDialogState(() => apply(d));
        }

        Widget dateRow(
                String label, DateTime? value, void Function(DateTime) apply) =>
            Row(
              children: [
                Expanded(
                  child: Text(
                    value == null
                        ? "$label: —"
                        : "$label: ${formatDisplayDate(value, useGregorianDates, english: ctx.l10n.isEnglish)}",
                    style: const TextStyle(fontSize: 14.5),
                  ),
                ),
                TextButton(
                    onPressed: () => pick(value, apply),
                    child: Text(ctx.l10n.pick(he: "בחר", en: "Select"))),
              ],
            );

        Future<void> finish(ProofreadEdit edit) async {
          if (saving) return;
          setDialogState(() => saving = true);
          var closing = false;
          try {
            final accepted = onCommit == null || await onCommit(edit);
            if (!ctx.mounted) return;
            if (accepted) {
              closing = true;
              Navigator.pop(ctx, edit);
            }
          } catch (error) {
            if (ctx.mounted) {
              setDialogState(() => costError = ctx.l10n.pick(
                  he: 'השמירה נכשלה. אפשר לנסות שוב: $error',
                  en: 'Save failed. Try again: $error'));
            }
          } finally {
            if (ctx.mounted && !closing) setDialogState(() => saving = false);
          }
        }

        return PopScope(
            canPop: !saving,
            child: AbsorbPointer(
                absorbing: saving,
                child: AlertDialog(
                  title: Text(ctx.l10n.pick(
                      he: isEdit ? "עריכת הגהה" : "הגהה חדשה",
                      en: isEdit
                          ? "Edit proofreading"
                          : "New proofreading batch")),
                  content: SizedBox(
                    width: 420,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: projectId,
                            isExpanded: true,
                            decoration: InputDecoration(
                                labelText:
                                    ctx.l10n.pick(he: "פרויקט", en: "Project"),
                                border: const OutlineInputBorder()),
                            items: [
                              // A record whose commission has since been deleted keeps
                              // an id that is in no list. Dropdown asserts on a value it
                              // cannot find, so the record became uneditable — and
                              // undeletable, since delete lives in this dialog. It is
                              // offered as an entry of its own, and can be reassigned.
                              if (projects.every((p) => p.id != projectId))
                                DropdownMenuItem(
                                  value: projectId,
                                  child: Text(
                                      ctx.l10n.pick(
                                          he: "פרויקט שנמחק",
                                          en: "Deleted project"),
                                      style: TextStyle(
                                          color: Colors.grey.shade600)),
                                ),
                              for (final p in projects)
                                DropdownMenuItem(
                                    value: p.id, child: Text(p.name)),
                            ],
                            onChanged: (v) => setDialogState(
                                () => projectId = v ?? projectId),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: scopeCtrl,
                            decoration: InputDecoration(
                              labelText: ctx.l10n
                                  .pick(he: "מה נשלח", en: "What was sent"),
                              hintText: ctx.l10n.pick(
                                  he: "עמודים א-ל / 12 מזוזות",
                                  en: "Pages א–ל / 12 Mezuzot"),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: proofreaderCtrl,
                            decoration: InputDecoration(
                                labelText: ctx.l10n
                                    .pick(he: "המגיה", en: "Proofreader"),
                                border: const OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<ProofreadStage>(
                            initialValue: stage,
                            isExpanded: true,
                            decoration: InputDecoration(
                                labelText:
                                    ctx.l10n.pick(he: "שלב", en: "Stage"),
                                border: const OutlineInputBorder()),
                            items: [
                              for (final s in ProofreadStage.values)
                                DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                        ctx.l10n.proofreadingStage(s.label))),
                            ],
                            onChanged: (v) =>
                                setDialogState(() => stage = v ?? stage),
                          ),
                          const SizedBox(height: 6),
                          if (stage != ProofreadStage.waiting)
                            dateRow(ctx.l10n.pick(he: "נשלח", en: "Sent"),
                                sentAt, (d) => sentAt = d),
                          if (stage == ProofreadStage.returned ||
                              stage == ProofreadStage.done)
                            dateRow(ctx.l10n.pick(he: "חזר", en: "Returned"),
                                returnedAt, (d) => returnedAt = d),
                          const SizedBox(height: 6),
                          TextField(
                            controller: costCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText:
                                  "${ctx.l10n.pick(he: 'עלות', en: 'Cost')} (${currency.symbol})",
                              border: const OutlineInputBorder(),
                              errorText: costError,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: findingsCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: ctx.l10n.pick(
                                  he: "כמה תיקונים חזרו",
                                  en: "Number of corrections returned"),
                              // Blank and zero are different answers, and the app keeps
                              // them apart — so the field has to say so.
                              hintText: ctx.l10n.pick(
                                  he: "השאר ריק אם לא נספר",
                                  en: "Leave blank if not counted"),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: notesCtrl,
                            maxLines: 2,
                            decoration: InputDecoration(
                                labelText:
                                    ctx.l10n.pick(he: "הערות", en: "Notes"),
                                border: const OutlineInputBorder()),
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    if (isEdit)
                      TextButton(
                        onPressed: () =>
                            finish(ProofreadEdit(record, deleted: true)),
                        child: Text(ctx.l10n.pick(he: "מחק", en: "Delete")),
                      ),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(ctx.l10n.cancel)),
                    ElevatedButton(
                      onPressed: () {
                        // The same reader the project form uses, so a cost typed with a
                        // thousands separator is that cost and not a fraction of it.
                        final costText = costCtrl.text.trim();
                        final cost =
                            costText.isEmpty ? 0.0 : MoneyInput.parse(costText);
                        if (cost == null) {
                          setDialogState(() => costError = ctx.l10n.pick(
                              he: "עלות חייבת להיות מספר",
                              en: "Cost must be a number"));
                          return;
                        }

                        final findingsText = findingsCtrl.text.trim();
                        finish(
                          ProofreadEdit(record.copyWith(
                            projectId: projectId,
                            stage: stage,
                            scope: scopeCtrl.text.trim(),
                            proofreader: proofreaderCtrl.text.trim(),
                            sentAt: sentAt,
                            returnedAt: returnedAt,
                            cost: cost,
                            // Left blank stays blank: "nobody counted" is not zero.
                            findings: findingsText.isEmpty
                                ? null
                                : int.tryParse(findingsText),
                            notes: notesCtrl.text.trim(),
                          )),
                        );
                      },
                      child: Text(ctx.l10n.pick(he: "שמור", en: "Save")),
                    ),
                  ],
                )));
      },
    ),
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;

  for (final c in [
    scopeCtrl,
    proofreaderCtrl,
    costCtrl,
    findingsCtrl,
    notesCtrl
  ]) {
    c.dispose();
  }
  return result;
}
