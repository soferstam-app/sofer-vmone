import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/expense_logic.dart';
import '../logic/id_generator.dart';
import '../models.dart';
import '../theme/app_theme.dart';

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
  Expense? existing,
  List<Project> projects = const [],
  bool useGregorianDates = false,
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

  final result = await showDialog<ExpenseEdit>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final ready = productCtrl.text.trim().isNotEmpty;

        DateTime? start() => allocation == ExpenseAllocation.period
            ? (periodStart ?? pickedDate)
            : null;
        DateTime? end() => allocation == ExpenseAllocation.period
            ? (periodEnd ?? pickedDate.add(const Duration(days: 90)))
            : null;

        return AlertDialog(
          title: Text(isEdit ? "עריכת הוצאה" : "הוספת הוצאה"),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: ExpenseLogic.categories
                            .any((c) => c.name == productCtrl.text)
                        ? productCtrl.text
                        : '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "קטגוריה",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text("בחר קטגוריה או הזן למטה")),
                      ...ExpenseLogic.categories.map((c) =>
                          DropdownMenuItem(value: c.name, child: Text(c.name))),
                    ],
                    onChanged: (v) {
                      productCtrl.text = v ?? '';
                      // Pick the allocation this category normally uses; the
                      // user can still override it below.
                      if (v != null && v.isNotEmpty) {
                        allocation = ExpenseLogic.defaultAllocationFor(v);
                      }
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: productCtrl,
                    decoration: const InputDecoration(
                      labelText: "מוצר (או הזן ידנית)",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "תאריך: ${formatDisplayDate(pickedDate, useGregorianDates)}",
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: pickedDate,
                            firstDate: DateTime(2020),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (d != null) setDialogState(() => pickedDate = d);
                        },
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: const Text("בחר"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "סכום (₪)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const Divider(height: 26),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text("על מה לזקוף את ההוצאה:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<ExpenseAllocation>(
                    segments: const [
                      ButtonSegment(
                          value: ExpenseAllocation.project,
                          label:
                              Text("פרויקט", style: TextStyle(fontSize: 12))),
                      ButtonSegment(
                          value: ExpenseAllocation.period,
                          label: Text("תקופה", style: TextStyle(fontSize: 12))),
                      ButtonSegment(
                          value: ExpenseAllocation.month,
                          label: Text("חודש", style: TextStyle(fontSize: 12))),
                    ],
                    selected: {allocation},
                    onSelectionChanged: (v) =>
                        setDialogState(() => allocation = v.first),
                  ),
                  const SizedBox(height: 10),
                  if (allocation == ExpenseAllocation.project) ...[
                    if (live.isEmpty)
                      Text("אין פרויקטים לשייך אליהם",
                          style: TextStyle(
                              color: SoferTokens.of(ctx).danger, fontSize: 13))
                    else ...[
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                            "אפשר לבחור כמה פרויקטים – הסכום יתחלק ביניהם",
                            style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(height: 6),
                      ...live.map(
                        (p) => CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: selectedProjects.contains(p.id),
                          title:
                              Text(p.name, style: const TextStyle(fontSize: 14)),
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
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text("הסכום יתחלק על פני התקופה שתבחר",
                          style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(height: 6),
                    _PeriodRow(
                      label: "מתאריך",
                      value: periodStart ?? pickedDate,
                      useGregorianDates: useGregorianDates,
                      onPicked: (d) => setDialogState(() => periodStart = d),
                    ),
                    _PeriodRow(
                      label: "עד תאריך",
                      value: periodEnd ??
                          pickedDate.add(const Duration(days: 90)),
                      useGregorianDates: useGregorianDates,
                      onPicked: (d) => setDialogState(() => periodEnd = d),
                    ),
                  ],
                  if (allocation == ExpenseAllocation.month)
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text("ההוצאה תיזקף לחודש שבו היא בוצעה",
                          style: TextStyle(fontSize: 12)),
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
                    Navigator.pop(ctx, ExpenseEdit(existing, deleted: true)),
                style: TextButton.styleFrom(
                    foregroundColor: SoferTokens.of(ctx).danger),
                child: const Text("מחק"),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
            ElevatedButton(
              // Disabled rather than complained about: a save that refuses and
              // explains in a snackbar is a save that looked possible.
              onPressed: !ready
                  ? null
                  : () {
                      final product = productCtrl.text.trim();
                      final amount = double.tryParse(
                              amountCtrl.text.replaceAll(',', '.')) ??
                          0;
                      final expense = isEdit
                          ? existing.copyWith(
                              product: product,
                              date: pickedDate,
                              amount: amount,
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
                              allocation: allocation,
                              projectIds: selectedProjects.toList(),
                              periodStart: start(),
                              periodEnd: end(),
                            );
                      Navigator.pop(ctx, ExpenseEdit(expense));
                    },
              child: Text(isEdit ? "שמור" : "הוסף"),
            ),
          ],
        );
      },
    ),
  );

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
          child: const Text("בחר"),
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
          title: Text(existing == null ? "הוספת הוצאה להצעה" : "עריכת ההוצאה"),
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
                    decoration: const InputDecoration(
                      labelText: "קטגוריה",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text("בחר קטגוריה או הזן למטה")),
                      ...ExpenseLogic.categories.map((c) =>
                          DropdownMenuItem(value: c.name, child: Text(c.name))),
                    ],
                    onChanged: (v) {
                      labelCtrl.text = v ?? '';
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: "מה זה (או הזן ידנית)",
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "סכום (₪)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text("הסכום הזה הוא:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                          value: true,
                          label: Text("לכל $unitSingular",
                              style: const TextStyle(fontSize: 12))),
                      const ButtonSegment(
                          value: false,
                          label: Text("לכל העבודה",
                              style: TextStyle(fontSize: 12))),
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
                onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
            ElevatedButton(
              onPressed: !ready
                  ? null
                  : () => Navigator.pop(
                        ctx,
                        QuoteExpense(
                          label: labelCtrl.text.trim(),
                          amount: double.tryParse(
                                  amountCtrl.text.replaceAll(',', '.')) ??
                              0,
                          perUnit: perUnit,
                        ),
                      ),
              child: Text(existing == null ? "הוסף" : "שמור"),
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
