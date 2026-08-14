import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/id_generator.dart';
import '../logic/money_input.dart';
import '../logic/payment_ledger.dart';
import '../models.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm.dart';
import '../widgets/sofer_widgets.dart';

/// What has come in on this commission, and the way to record more.
///
/// Opened from the commission screen, which is where the question is asked:
/// the price is there, the progress is there, and "how much of this have I
/// actually been paid" belongs beside them rather than in a screen of its own.
Future<bool> showPaymentSheet({
  required BuildContext context,
  required Project project,
  required List<WorkSession> history,
  required bool useGregorianDates,
}) async {
  final storage = StorageService();
  var all = await storage.loadPayments();
  var changed = false;
  if (!context.mounted) return false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final ledger = PaymentLedger.of(
          project: project,
          allPayments: all,
          history: history,
        );
        final t = SoferTokens.of(ctx);

        Future<void> save(Payment p, {bool delete = false}) async {
          final next = [...all];
          final at = next.indexWhere((e) => e.id == p.id);
          final record = delete ? p.copyWith(isDeleted: true) : p;
          if (at == -1) {
            next.add(record);
          } else {
            next[at] = record;
          }
          await storage.savePayments(next);
          changed = true;
          setSheet(() => all = next);
        }

        Future<void> edit({Payment? existing}) async {
          final result = await _showPaymentEditor(
            context: ctx,
            project: project,
            existing: existing,
            useGregorianDates: useGregorianDates,
          );
          if (result == null) return;
          if (result.deleted) {
            if (!ctx.mounted) return;
            final sure = await confirmAction(
              ctx,
              title: "מחיקת תשלום",
              message: "התשלום לא ייספר עוד בהכנסות ובדוח השנתי.",
              confirmLabel: "מחק",
              danger: true,
            );
            if (!sure) return;
            await save(result.payment, delete: true);
            return;
          }
          await save(result.payment);
        }

        final outstanding = ledger.outstanding;
        final advance = ledger.inAdvance;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text("תשלומים · ${project.name}",
                    style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 20,
                        color: t.ink)),
                const SizedBox(height: 14),

                SoferStatRow("התקבל", ledger.received.format(project.currency)),
                SoferStatRow("שווי מה שנכתב", ledger.earnedSoFar.format()),
                if (outstanding != null)
                  SoferStatRow("נותר לתשלום", outstanding.format(),
                      last: advance == null),
                if (advance != null)
                  // Paid ahead of the writing, which is ordinary at the start of
                  // a commission and better said than hidden.
                  SoferStatRow("שולם מראש", advance.format(), last: true),
                if (outstanding == null && advance == null)
                  SoferStatRow(
                      "נותר לתשלום", "לא ניתן לחשב — תשלומים בכמה מטבעות",
                      last: true),

                const SizedBox(height: 16),
                if (ledger.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      "לא נרשמו תשלומים על העבודה הזו.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.inkMuted, fontSize: 14),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in ledger.payments)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(p.currency.format(p.amount),
                                style: TextStyle(
                                    fontFamily: t.numeralFamily, fontSize: 17)),
                            subtitle: Text([
                              formatDisplayDate(p.receivedAt, useGregorianDates),
                              if (p.method.isNotEmpty) p.method,
                              if (p.notes.isNotEmpty) p.notes,
                            ].join(' · ')),
                            trailing: const Icon(Icons.edit_outlined, size: 20),
                            onTap: () => edit(existing: p),
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),
                SoferPrimaryButton("רישום תשלום",
                    icon: Icons.add, expand: true, onPressed: () => edit()),
              ],
            ),
          ),
        );
      },
    ),
  );

  return changed;
}

class _PaymentEdit {
  final Payment payment;
  final bool deleted;
  const _PaymentEdit(this.payment, {this.deleted = false});
}

/// One payment. Three fields that matter and two that do not always.
Future<_PaymentEdit?> _showPaymentEditor({
  required BuildContext context,
  required Project project,
  required bool useGregorianDates,
  Payment? existing,
}) async {
  final isEdit = existing != null;
  final record = existing ??
      Payment(
        id: IdGenerator.generate(),
        projectId: project.id,
        amount: 0,
        currency: project.currency,
        receivedAt: DateTime.now(),
      );

  final amountCtrl =
      TextEditingController(text: record.amount > 0 ? '${record.amount}' : '');
  final methodCtrl = TextEditingController(text: record.method);
  final notesCtrl = TextEditingController(text: record.notes);
  var receivedAt = record.receivedAt;
  String? amountError;

  final result = await showDialog<_PaymentEdit>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: Text(isEdit ? "עריכת תשלום" : "רישום תשלום"),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: amountCtrl,
                  autofocus: !isEdit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: "סכום (${record.currency.symbol})",
                    border: const OutlineInputBorder(),
                    errorText: amountError,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        // The date decides which tax year this belongs to, so it
                        // is the one field that is never guessed silently.
                        "התקבל: ${formatDisplayDate(receivedAt, useGregorianDates)}",
                        style: const TextStyle(fontSize: 14.5),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: receivedAt,
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) setDialog(() => receivedAt = d);
                      },
                      child: const Text("בחר"),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: methodCtrl,
                  decoration: const InputDecoration(
                    labelText: "אופן התשלום",
                    hintText: "מזומן / העברה / צ׳ק",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
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
                  Navigator.pop(ctx, _PaymentEdit(record, deleted: true)),
              child: const Text("מחק"),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          ElevatedButton(
            onPressed: () {
              // The same reader the rest of the app uses, so 12,000 is twelve
              // thousand and not twelve.
              final amount = MoneyInput.parse(amountCtrl.text);
              if (amount == null || amount <= 0) {
                setDialog(() => amountError = "יש להזין סכום גדול מאפס");
                return;
              }
              Navigator.pop(
                ctx,
                _PaymentEdit(record.copyWith(
                  amount: amount,
                  receivedAt: receivedAt,
                  method: methodCtrl.text.trim(),
                  notes: notesCtrl.text.trim(),
                )),
              );
            },
            child: const Text("שמור"),
          ),
        ],
      ),
    ),
  );

  for (final c in [amountCtrl, methodCtrl, notesCtrl]) {
    c.dispose();
  }
  return result;
}
