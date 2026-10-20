import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/expense_logic.dart';
import '../logic/money_input.dart';
import '../logic/id_generator.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../logic/currency.dart';
import '../l10n/app_localizations.dart';

/// What came back from the expense editor.
class ExpenseEdit {
  final Expense expense;

  /// The writer asked for this expense to go. Carrying it back rather than
  /// acting on it keeps the decision with the caller, which is the only side
  /// that knows whether the record is stored and how removal is recorded.
  final bool deleted;

  const ExpenseEdit(this.expense, {this.deleted = false});
}

/// The one place an expense is entered, changed or removed.
///
/// This used to be private to the expenses screen, which left the quote screen —
/// the other place a writer has to say what materials cost — with nothing but a
/// single number to type. It also meant the ruled layouts had no way to delete
/// an expense at all, because the delete lived in the modern list row.
///
/// It returns the expense rather than saving it, so the caller can persist it,
/// merge it, or use it for something that is not stored at all.
Future<ExpenseEdit?> showExpenseEditor({
  required BuildContext context,
  Future<bool> Function(ExpenseEdit)? onCommit,
  Expense? existing,
  List<Project> projects = const [],
  bool useGregorianDates = false,
  Currency currency = Currency.ils,
}) async {
  final isEdit = existing != null;
  final productCtrl = TextEditingController(text: existing?.product ?? '');
  final amountCtrl = TextEditingController(
      text: existing != null ? existing.amount.toString() : '');

  var pickedDate = existing?.date ?? DateTime.now();
  var allocation = existing?.allocation ?? ExpenseAllocation.month;
  final selectedProjects = <String>{...(existing?.projectIds ?? const [])};
  var periodStart = existing?.periodStart;
  var periodEnd = existing?.periodEnd;

  final live = projects.where((p) => !p.isDeleted).toList();

  String? saveError;
  var saving = false;
  final route = DialogRoute<ExpenseEdit>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final ready = productCtrl.text.trim().isNotEmpty;

        DateTime? start() => allocation == ExpenseAllocation.period
            ? (periodStart ?? pickedDate)
            : null;
        DateTime? end() => allocation == ExpenseAllocation.period
            ? (periodEnd ?? pickedDate.add(const Duration(days: 90)))
            : null;

        Future<void> finish(ExpenseEdit edit) async {
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
              setDialogState(() => saveError = ctx.l10n.pick(
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
                      he: isEdit ? "עריכת הוצאה" : "הוספת הוצאה",
                      en: isEdit ? "Edit expense" : "Add expense")),
                  content: SizedBox(
                    width: 400,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (saveError != null)
                            Text(saveError!,
                                style: const TextStyle(color: Colors.red)),
                          if (saving) const LinearProgressIndicator(),
                          DropdownButtonFormField<String>(
                            initialValue: ExpenseLogic.categories
                                    .any((c) => c.name == productCtrl.text)
                                ? productCtrl.text
                                : '',
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText:
                                  ctx.l10n.pick(he: "קטגוריה", en: "Category"),
                              border: const OutlineInputBorder(),
                            ),
                            items: [
                              DropdownMenuItem(
                                  value: '',
                                  child: Text(ctx.l10n.pick(
                                      he: "בחר קטגוריה או הזן למטה",
                                      en: "Select a category or enter one below"))),
                              ...ExpenseLogic.categories.map((c) =>
                                  DropdownMenuItem(
                                      value: c.name,
                                      child: Text(
                                          ctx.l10n.expenseCategory(c.name)))),
                            ],
                            onChanged: (v) {
                              productCtrl.text = v ?? '';
                              // Pick the allocation this category normally uses; the
                              // user can still override it below.
                              if (v != null && v.isNotEmpty) {
                                allocation =
                                    ExpenseLogic.defaultAllocationFor(v);
                              }
                              setDialogState(() {});
                            },
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: productCtrl,
                            decoration: InputDecoration(
                              labelText: ctx.l10n.pick(
                                  he: "מוצר (או הזן ידנית)",
                                  en: "Item (or enter manually)"),
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (_) => setDialogState(() {}),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "${ctx.l10n.pick(he: 'תאריך', en: 'Date')}: ${formatDisplayDate(pickedDate, useGregorianDates, english: ctx.l10n.isEnglish)}",
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: pickedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 365)),
                                  );
                                  if (d != null) {
                                    setDialogState(() => pickedDate = d);
                                  }
                                },
                                icon:
                                    const Icon(Icons.calendar_today, size: 18),
                                label: Text(
                                    ctx.l10n.pick(he: "בחר", en: "Select")),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText:
                                  "${ctx.l10n.pick(he: 'סכום', en: 'Amount')} (${(existing?.currency ?? currency).symbol})",
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const Divider(height: 26),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                                ctx.l10n.pick(
                                    he: "על מה לזקוף את ההוצאה:",
                                    en: "Allocate this expense to:"),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<ExpenseAllocation>(
                            segments: [
                              ButtonSegment(
                                  value: ExpenseAllocation.project,
                                  label: Text(
                                      ctx.l10n
                                          .pick(he: "פרויקט", en: "Project"),
                                      style: const TextStyle(fontSize: 12))),
                              ButtonSegment(
                                  value: ExpenseAllocation.period,
                                  label: Text(
                                      ctx.l10n.pick(he: "תקופה", en: "Period"),
                                      style: const TextStyle(fontSize: 12))),
                              ButtonSegment(
                                  value: ExpenseAllocation.month,
                                  label: Text(
                                      ctx.l10n.pick(he: "חודש", en: "Month"),
                                      style: const TextStyle(fontSize: 12))),
                            ],
                            selected: {allocation},
                            onSelectionChanged: (v) =>
                                setDialogState(() => allocation = v.first),
                          ),
                          const SizedBox(height: 10),
                          if (allocation == ExpenseAllocation.project) ...[
                            if (live.isEmpty)
                              Text(
                                  ctx.l10n.pick(
                                      he: "אין פרויקטים לשייך אליהם",
                                      en: "No projects available"),
                                  style: TextStyle(
                                      color: SoferTokens.of(ctx).danger,
                                      fontSize: 13))
                            else ...[
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                    ctx.l10n.pick(
                                        he: "אפשר לבחור כמה פרויקטים – הסכום יתחלק ביניהם",
                                        en: "You can select several projects; the amount will be split between them"),
                                    style: const TextStyle(fontSize: 12)),
                              ),
                              const SizedBox(height: 6),
                              ...live.map(
                                (p) => CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: selectedProjects.contains(p.id),
                                  title: Text(p.name,
                                      style: const TextStyle(fontSize: 14)),
                                  onChanged: (v) => setDialogState(() {
                                    if (v == true) {
                                      selectedProjects.add(p.id);
                                    } else {
                                      selectedProjects.remove(p.id);
                                    }
                                  }),
                                ),
                              ),
                            ],
                          ],
                          if (allocation == ExpenseAllocation.period) ...[
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                  ctx.l10n.pick(
                                      he: "הסכום יתחלק על פני התקופה שתבחר",
                                      en: "The amount will be spread across the selected period"),
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(height: 6),
                            _PeriodRow(
                              label: ctx.l10n.pick(he: "מתאריך", en: "From"),
                              value: periodStart ?? pickedDate,
                              useGregorianDates: useGregorianDates,
                              onPicked: (d) =>
                                  setDialogState(() => periodStart = d),
                            ),
                            _PeriodRow(
                              label: ctx.l10n.pick(he: "עד תאריך", en: "To"),
                              value: periodEnd ??
                                  pickedDate.add(const Duration(days: 90)),
                              useGregorianDates: useGregorianDates,
                              onPicked: (d) =>
                                  setDialogState(() => periodEnd = d),
                            ),
                          ],
                          if (allocation == ExpenseAllocation.month)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                  ctx.l10n.pick(
                                      he: "ההוצאה תיזקף לחודש שבו היא בוצעה",
                                      en: "The expense will be allocated to the month in which it was paid"),
                                  style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    // Removal lives in the editor so that it exists in every layout.
                    // While it sat in the modern list row, the ruled layouts could open
                    // an expense but never get rid of one.
                    if (isEdit)
                      TextButton(
                        onPressed: () =>
                            finish(ExpenseEdit(existing, deleted: true)),
                        style: TextButton.styleFrom(
                            foregroundColor: SoferTokens.of(ctx).danger),
                        child: Text(ctx.l10n.pick(he: "מחק", en: "Delete")),
                      ),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(ctx.l10n.cancel)),
                    ElevatedButton(
                      // Disabled rather than complained about: a save that refuses and
                      // explains in a snackbar is a save that looked possible.
                      onPressed: !ready
                          ? null
                          : () {
                              final product = productCtrl.text.trim();
                              // Not replaceAll(',', '.'), which read an expense of
                              // 40,000 as forty. See [MoneyInput].
                              final amount =
                                  MoneyInput.parse(amountCtrl.text) ?? 0;
                              final expense = isEdit
                                  ? existing.copyWith(
                                      product: product,
                                      date: pickedDate,
                                      amount: amount,
                                      // Not restated. Editing what a purchase cost does
                                      // not change what it was paid in.
                                      allocation: allocation,
                                      projectIds: selectedProjects.toList(),
                                      periodStart: start(),
                                      periodEnd: end(),
                                    )
                                  : Expense(
                                      id: IdGenerator.generate(),
                                      product: product,
                                      date: pickedDate,
                                      amount: amount,
                                      currency: currency,
                                      allocation: allocation,
                                      projectIds: selectedProjects.toList(),
                                      periodStart: start(),
                                      periodEnd: end(),
                                    );
                              finish(ExpenseEdit(expense));
                            },
                      child: Text(ctx.l10n.pick(
                          he: isEdit ? "שמור" : "הוסף",
                          en: isEdit ? "Save" : "Add")),
                    ),
                  ],
                )));
      },
    ),
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;

  productCtrl.dispose();
  amountCtrl.dispose();
  return result;
}

class _PeriodRow extends StatelessWidget {
  final String label;
  final DateTime value;
  final bool useGregorianDates;
  final ValueChanged<DateTime> onPicked;

  const _PeriodRow({
    required this.label,
    required this.value,
    required this.useGregorianDates,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text("$label: ${formatDisplayDate(value, useGregorianDates)}",
              style: const TextStyle(fontSize: 14)),
        ),
        TextButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2020),
              lastDate: DateTime(DateTime.now().year + 5),
            );
            if (d != null) onPicked(d);
          },
          child: Text(context.l10n.pick(he: "בחר", en: "Select")),
        ),
      ],
    );
  }
}

/// A cost typed into a quote, for work that does not exist yet.
///
/// There is no commission to charge it to and nothing to store, so it carries
/// only what a quote needs: what it is, how much it is, and whether it is spent
/// once for the whole job or again for every unit. Parchment is per unit; a
/// delivery is not.
class QuoteExpense {
  final String label;
  final double amount;
  final bool perUnit;

  const QuoteExpense({
    required this.label,
    required this.amount,
    required this.perUnit,
  });

  /// What this line adds to the cost of one unit, spread over [units] of them.
  double perUnitOver(double units) =>
      perUnit ? amount : (units <= 0 ? 0 : amount / units);

  QuoteExpense copyWith({String? label, double? amount, bool? perUnit}) =>
      QuoteExpense(
        label: label ?? this.label,
        amount: amount ?? this.amount,
        perUnit: perUnit ?? this.perUnit,
      );
}

/// Enters one line of a quote's costs.
///
/// The same category list as a real expense, because a sofer buys the same
/// things whether the job is booked or still being priced. What it does not ask
/// for is a date or a project: a quote has neither yet.
Future<QuoteExpense?> showQuoteExpenseEditor({
  required BuildContext context,
  required String unitSingular,
  QuoteExpense? existing,
}) async {
  final labelCtrl = TextEditingController(text: existing?.label ?? '');
  final amountCtrl = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(0) : '');
  var perUnit = existing?.perUnit ?? true;

  final result = await showDialog<QuoteExpense>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final ready = labelCtrl.text.trim().isNotEmpty;

        return AlertDialog(
          title: Text(ctx.l10n.pick(
              he: existing == null ? "הוספת הוצאה להצעה" : "עריכת ההוצאה",
              en: existing == null ? "Add quote expense" : "Edit expense")),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: ExpenseLogic.categories
                            .any((c) => c.name == labelCtrl.text)
                        ? labelCtrl.text
                        : '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: ctx.l10n.pick(he: "קטגוריה", en: "Category"),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: '',
                          child: Text(ctx.l10n.pick(
                              he: "בחר קטגוריה או הזן למטה",
                              en: "Select a category or enter one below"))),
                      ...ExpenseLogic.categories.map((c) => DropdownMenuItem(
                          value: c.name,
                          child: Text(ctx.l10n.expenseCategory(c.name)))),
                    ],
                    onChanged: (v) {
                      labelCtrl.text = v ?? '';
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: labelCtrl,
                    decoration: InputDecoration(
                      labelText: ctx.l10n.pick(
                          he: "מה זה (או הזן ידנית)",
                          en: "Item (or enter manually)"),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText:
                          ctx.l10n.pick(he: "סכום (₪)", en: "Amount (₪)"),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                        ctx.l10n
                            .pick(he: "הסכום הזה הוא:", en: "This amount is:"),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                          value: true,
                          label: Text(
                              ctx.l10n.pick(
                                  he: "לכל $unitSingular",
                                  en: "Per $unitSingular"),
                              style: const TextStyle(fontSize: 12))),
                      ButtonSegment(
                          value: false,
                          label: Text(
                              ctx.l10n.pick(
                                  he: "לכל העבודה", en: "For the entire job"),
                              style: const TextStyle(fontSize: 12))),
                    ],
                    selected: {perUnit},
                    onSelectionChanged: (v) =>
                        setDialogState(() => perUnit = v.first),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(ctx.l10n.cancel)),
            ElevatedButton(
              onPressed: !ready
                  ? null
                  : () => Navigator.pop(
                        ctx,
                        QuoteExpense(
                          label: labelCtrl.text.trim(),
                          amount: MoneyInput.parse(amountCtrl.text) ?? 0,
                          perUnit: perUnit,
                        ),
                      ),
              child: Text(ctx.l10n.pick(
                  he: existing == null ? "הוסף" : "שמור",
                  en: existing == null ? "Add" : "Save")),
            ),
          ],
        );
      },
    ),
  );

  labelCtrl.dispose();
  amountCtrl.dispose();
  return result;
}
