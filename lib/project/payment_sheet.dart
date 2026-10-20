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
import '../l10n/app_localizations.dart';

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
          if (ctx.mounted) setSheet(() => all = next);
        }

        Future<void> edit({Payment? existing}) async {
          await _showPaymentEditor(
            context: ctx,
            project: project,
            existing: existing,
            useGregorianDates: useGregorianDates,
            onCommit: (result) async {
              if (result.deleted) {
                final sure = await confirmAction(ctx,
                    title:
                        ctx.l10n.pick(he: 'מחיקת תשלום', en: 'Delete payment'),
                    message: ctx.l10n.pick(
                        he: 'התשלום לא ייספר עוד בהכנסות ובדוח השנתי.',
                        en: 'The payment will no longer be included in income or the annual report.'),
                    confirmLabel: ctx.l10n.pick(he: 'מחק', en: 'Delete'),
                    danger: true);
                if (!sure) return false;
              }
              await save(result.payment, delete: result.deleted);
              return true;
            },
          );
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
                Text(
                    ctx.l10n.pick(
                        he: "תשלומים · ${project.name}",
                        en: "Payments · ${project.name}"),
                    style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 20,
                        color: t.ink)),
                const SizedBox(height: 14),
                SoferStatRow(ctx.l10n.pick(he: "התקבל", en: "Received"),
                    ledger.received.format(project.currency)),
                SoferStatRow(
                    ctx.l10n.pick(he: "שווי מה שנכתב", en: "Value written"),
                    ledger.earnedSoFar.format()),
                if (outstanding != null)
                  SoferStatRow(
                      ctx.l10n.pick(he: "נותר לתשלום", en: "Outstanding"),
                      outstanding.format(),
                      last: advance == null),
                if (advance != null)
                  // Paid ahead of the writing, which is ordinary at the start of
                  // a commission and better said than hidden.
                  SoferStatRow(
                      ctx.l10n.pick(he: "שולם מראש", en: "Paid in advance"),
                      advance.format(),
                      last: true),
                if (outstanding == null && advance == null)
                  SoferStatRow(
                      ctx.l10n.pick(he: "נותר לתשלום", en: "Outstanding"),
                      ctx.l10n.pick(
                          he: "לא ניתן לחשב — תשלומים בכמה מטבעות",
                          en: "Cannot calculate — payments use multiple currencies"),
                      last: true),
                const SizedBox(height: 16),
                if (ledger.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      ctx.l10n.pick(
                          he: "לא נרשמו תשלומים על העבודה הזו.",
                          en: "No payments recorded for this project."),
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
                              formatDisplayDate(p.receivedAt, useGregorianDates,
                                  english: ctx.l10n.isEnglish),
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
                SoferPrimaryButton(
                    ctx.l10n.pick(he: "רישום תשלום", en: "Record payment"),
                    icon: Icons.add,
                    expand: true,
                    onPressed: () => edit()),
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
  Future<bool> Function(_PaymentEdit)? onCommit,
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

  var saving = false;
  final route = DialogRoute<_PaymentEdit>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) {
        Future<void> finish(_PaymentEdit edit) async {
          if (saving) return;
          setDialog(() => saving = true);
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
              setDialog(() => amountError = ctx.l10n.pick(
                  he: 'השמירה נכשלה. אפשר לנסות שוב: $error',
                  en: 'Save failed. Try again: $error'));
            }
          } finally {
            if (ctx.mounted && !closing) setDialog(() => saving = false);
          }
        }

        return PopScope(
            canPop: !saving,
            child: AbsorbPointer(
                absorbing: saving,
                child: AlertDialog(
                  title: Text(ctx.l10n.pick(
                      he: isEdit ? "עריכת תשלום" : "רישום תשלום",
                      en: isEdit ? "Edit payment" : "Record payment")),
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
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText:
                                  "${ctx.l10n.pick(he: 'סכום', en: 'Amount')} (${record.currency.symbol})",
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
                                  "${ctx.l10n.pick(he: 'התקבל', en: 'Received')}: ${formatDisplayDate(receivedAt, useGregorianDates, english: ctx.l10n.isEnglish)}",
                                  style: const TextStyle(fontSize: 14.5),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: receivedAt,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 365)),
                                  );
                                  if (d != null) {
                                    setDialog(() => receivedAt = d);
                                  }
                                },
                                child: Text(
                                    ctx.l10n.pick(he: "בחר", en: "Select")),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: methodCtrl,
                            decoration: InputDecoration(
                              labelText: ctx.l10n.pick(
                                  he: "אופן התשלום", en: "Payment method"),
                              hintText: ctx.l10n.pick(
                                  he: "מזומן / העברה / צ׳ק",
                                  en: "Cash / transfer / check"),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: notesCtrl,
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
                            finish(_PaymentEdit(record, deleted: true)),
                        child: Text(ctx.l10n.pick(he: "מחק", en: "Delete")),
                      ),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(ctx.l10n.cancel)),
                    ElevatedButton(
                      onPressed: () {
                        // The same reader the rest of the app uses, so 12,000 is twelve
                        // thousand and not twelve.
                        final amount = MoneyInput.parse(amountCtrl.text);
                        if (amount == null || amount <= 0) {
                          setDialog(() => amountError = ctx.l10n.pick(
                              he: "יש להזין סכום גדול מאפס",
                              en: "Enter an amount greater than zero"));
                          return;
                        }
                        finish(
                          _PaymentEdit(record.copyWith(
                            amount: amount,
                            receivedAt: receivedAt,
                            method: methodCtrl.text.trim(),
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

  for (final c in [amountCtrl, methodCtrl, notesCtrl]) {
    c.dispose();
  }
  return result;
}
