import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/currency.dart';
import '../logic/money_input.dart';
import '../models.dart';
import 'proofread_screen.dart';

/// Entering or changing one batch of proofreading.
///
/// Deliberately short. What a sofer knows when he hands the work over is which
/// commission, roughly what he sent, and to whom; the cost and the corrections
/// are only known later, and asking for them up front would make the form look
/// like it wanted answers he does not have yet.
Future<ProofreadEdit?> showProofreadEditor({
  required BuildContext context,
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

  final result = await showDialog<ProofreadEdit>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> pick(DateTime? current, void Function(DateTime) apply) async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: current ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (d != null) setDialogState(() => apply(d));
        }

        Widget dateRow(String label, DateTime? value, void Function(DateTime) apply) =>
            Row(
              children: [
                Expanded(
                  child: Text(
                    value == null
                        ? "$label: —"
                        : "$label: ${formatDisplayDate(value, useGregorianDates)}",
                    style: const TextStyle(fontSize: 14.5),
                  ),
                ),
                TextButton(onPressed: () => pick(value, apply), child: const Text("בחר")),
              ],
            );

        return AlertDialog(
          title: Text(isEdit ? "עריכת הגהה" : "הגהה חדשה"),
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
                    decoration: const InputDecoration(
                        labelText: "פרויקט", border: OutlineInputBorder()),
                    items: [
                      // A record whose commission has since been deleted keeps
                      // an id that is in no list. Dropdown asserts on a value it
                      // cannot find, so the record became uneditable — and
                      // undeletable, since delete lives in this dialog. It is
                      // offered as an entry of its own, and can be reassigned.
                      if (projects.every((p) => p.id != projectId))
                        DropdownMenuItem(
                          value: projectId,
                          child: Text("פרויקט שנמחק",
                              style: TextStyle(color: Colors.grey.shade600)),
                        ),
                      for (final p in projects)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => projectId = v ?? projectId),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: scopeCtrl,
                    decoration: const InputDecoration(
                      labelText: "מה נשלח",
                      hintText: "עמודים א-ל / 12 מזוזות",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: proofreaderCtrl,
                    decoration: const InputDecoration(
                        labelText: "המגיה", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ProofreadStage>(
                    initialValue: stage,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: "שלב", border: OutlineInputBorder()),
                    items: [
                      for (final s in ProofreadStage.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (v) => setDialogState(() => stage = v ?? stage),
                  ),
                  const SizedBox(height: 6),
                  if (stage != ProofreadStage.waiting)
                    dateRow("נשלח", sentAt, (d) => sentAt = d),
                  if (stage == ProofreadStage.returned ||
                      stage == ProofreadStage.done)
                    dateRow("חזר", returnedAt, (d) => returnedAt = d),
                  const SizedBox(height: 6),
                  TextField(
                    controller: costCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: "עלות (${currency.symbol})",
                      border: const OutlineInputBorder(),
                      errorText: costError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: findingsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "כמה תיקונים חזרו",
                      // Blank and zero are different answers, and the app keeps
                      // them apart — so the field has to say so.
                      hintText: "השאר ריק אם לא נספר",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: "הערות", border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (isEdit)
              TextButton(
                onPressed: () =>
                    Navigator.pop(ctx, ProofreadEdit(record, deleted: true)),
                child: const Text("מחק"),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("ביטול")),
            ElevatedButton(
              onPressed: () {
                // The same reader the project form uses, so a cost typed with a
                // thousands separator is that cost and not a fraction of it.
                final costText = costCtrl.text.trim();
                final cost = costText.isEmpty ? 0.0 : MoneyInput.parse(costText);
                if (cost == null) {
                  setDialogState(() => costError = "עלות חייבת להיות מספר");
                  return;
                }

                final findingsText = findingsCtrl.text.trim();
                Navigator.pop(
                  ctx,
                  ProofreadEdit(record.copyWith(
                    projectId: projectId,
                    stage: stage,
                    scope: scopeCtrl.text.trim(),
                    proofreader: proofreaderCtrl.text.trim(),
                    sentAt: sentAt,
                    returnedAt: returnedAt,
                    cost: cost,
                    // Left blank stays blank: "nobody counted" is not zero.
                    findings:
                        findingsText.isEmpty ? null : int.tryParse(findingsText),
                    notes: notesCtrl.text.trim(),
                  )),
                );
              },
              child: const Text("שמור"),
            ),
          ],
        );
      },
    ),
  );

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
