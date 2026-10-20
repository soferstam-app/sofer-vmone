import 'package:flutter/material.dart';

import 'expenses/expense_editor.dart';
import 'hebrew_utils.dart';
import 'logic/expense_logic.dart';
import 'models.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'widgets/feedback.dart';
import 'format.dart';
import 'logic/currency.dart';
import 'l10n/app_localizations.dart';

class ExpensesScreen extends StatefulWidget {
  /// Needed so an expense can be charged to the work it belongs to.
  final List<Project> projects;

  const ExpensesScreen({super.key, this.projects = const []});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final StorageService _storage = StorageService();

  /// All expenses including soft-deleted ones. Deleted entries must stay in the
  /// list so a merge sees the deletion instead of restoring the row.
  List<Expense> _all = [];
  bool _useGregorianDates = false;
  bool _loading = true;

  List<Expense> get _expenses => _all.where((e) => !e.isDeleted).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final useGregorian = await _storage.getUseGregorianDates();
    final currency = await _storage.getCurrency();
    final list = await _storage.loadExpenses();
    if (mounted) {
      setState(() {
        _useGregorianDates = useGregorian;
        _currency = currency;
        _all = list;
        _loading = false;
      });
    }
  }

  Future<void> _storeExpense(Expense expense) async {
    final next = [
      for (final e in _all)
        if (e.id != expense.id) e,
      expense
    ];
    await _storage.saveExpenses(next);
    if (mounted) setState(() => _all = next);
  }

  /// Every expense, kept apart by currency.
  ///
  /// Adding shekels to dollars produces a number that is not a sum of anything.
  /// Almost always there is one currency and this reads as an ordinary figure.
  MoneyTotal get _totalExpenses =>
      MoneyTotal.of(_expenses.map((e) => Money(e.amount, e.currency)));

  /// What a new expense is entered in. Only that — each stored one keeps its own.
  Currency _currency = Currency.ils;

  String _projectName(String id) {
    for (final p in widget.projects) {
      if (p.id == id) return p.name;
    }
    return context.l10n.pick(he: 'פרויקט שנמחק', en: 'Deleted project');
  }

  /// One line describing where this expense lands, so the list is readable
  /// without opening each row.
  String _allocationSummary(Expense e) {
    switch (e.allocation) {
      case ExpenseAllocation.project:
        if (e.projectIds.isEmpty) {
          return context.l10n
              .pick(he: '⚠ לא שויך לפרויקט', en: '⚠ Not assigned to a project');
        }
        if (e.projectIds.length == 1) return _projectName(e.projectIds.first);
        return context.l10n.pick(
          he: '${e.projectIds.length} פרויקטים (${formatMoney(e.amountPerProject, e.currency)} כל אחד)',
          en: '${e.projectIds.length} projects (${formatMoney(e.amountPerProject, e.currency)} each)',
        );
      case ExpenseAllocation.period:
        final s = e.periodStart, en = e.periodEnd;
        if (s == null || en == null) {
          return context.l10n
              .pick(he: 'תקופה לא הוגדרה', en: 'Period not defined');
        }
        return '${formatDisplayDate(s, _useGregorianDates, english: context.l10n.isEnglish)} – ${formatDisplayDate(en, _useGregorianDates, english: context.l10n.isEnglish)}';
      case ExpenseAllocation.month:
        return context.l10n.pick(he: 'חודשי', en: 'Monthly');
    }
  }

  /// Opens the shared editor, then applies whatever came back.
  ///
  /// The form itself lives in expenses/expense_editor.dart, so the quote screen
  /// can use the very same one. This method only decides what a result means for
  /// the stored list.
  Future<void> _showAddOrEdit([Expense? existing]) async {
    await showExpenseEditor(
      context: context,
      existing: existing,
      projects: widget.projects,
      useGregorianDates: _useGregorianDates,
      currency: _currency,
      onCommit: (edit) async {
        await _storeExpense(edit.deleted
            ? edit.expense.copyWith(isDeleted: true)
            : edit.expense);
        return true;
      },
    );
  }

  /// Marked deleted rather than dropped from the list, so the removal survives a
  /// merge against a device still holding the row.
  Future<void> _softDelete(Expense e) async {
    try {
      await _storeExpense(e.copyWith(isDeleted: true));
    } catch (error) {
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'מחיקת ההוצאה נכשלה: $error',
                en: 'Expense deletion failed: $error'));
      }
    }
  }

  void _confirmDelete(Expense e) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.pick(he: "מחיקת הוצאה", en: "Delete expense")),
        content: Text(context.l10n.pick(
          he: "למחוק \"${e.product}\" (${formatMoneyExact(e.amount, e.currency)})?",
          en: "Delete \"${context.l10n.expenseCategory(e.product)}\" (${formatMoneyExact(e.amount, e.currency)})?",
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: SoferTokens.of(ctx).danger),
            onPressed: () {
              Navigator.pop(ctx);
              _softDelete(e);
            },
            child: Text(context.l10n.pick(he: "מחק", en: "Delete")),
          ),
        ],
      ),
    );
  }

  /// The expenses as an accountant's page, grouped by how each cost is charged.
  ///
  /// The modern layout is one flat list of cards, which hides the thing that
  /// actually matters: whether a cost lands on a commission, on a stretch of
  /// time, or on the month. Here each of the three is its own ruled block with
  /// its own subtotal, so where the money is attributed is visible without
  /// opening anything.
  Widget _ruledLedger(List<Expense> unassigned) {
    final t = SoferTokens.of(context);

    List<Expense> of(ExpenseAllocation a) =>
        _expenses.where((e) => e.allocation == a).toList();
    MoneyTotal sum(List<Expense> list) =>
        MoneyTotal.of(list.map((e) => Money(e.amount, e.currency)));

    final groups = <({ExpenseAllocation kind, String title, String note})>[
      (
        kind: ExpenseAllocation.project,
        title: context.l10n.pick(he: "לפי פרויקט", en: "By Project"),
        note: context.l10n.pick(
            he: "נכנס לחישוב הרווח של העבודה שהוא נצרך בה",
            en: "Included in the profit calculation of the project that used it")
      ),
      (
        kind: ExpenseAllocation.period,
        title: context.l10n.pick(he: "לפי תקופה", en: "By Period"),
        note: context.l10n.pick(
            he: "מתפרס על פני הימים שבין שני התאריכים",
            en: "Spread across the days between the two dates")
      ),
      (
        kind: ExpenseAllocation.month,
        title: context.l10n.pick(he: "לפי חודש", en: "By Month"),
        note: context.l10n.pick(
            he: "נכנס במלואו לחודש שבו הוא שולם",
            en: "Included in full in the month in which it was paid")
      ),
    ];

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                    context.l10n.pick(he: "סך ההוצאות", en: "Total expenses"),
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 12,
                        letterSpacing: 1.5,
                        color: t.inkMuted)),
              ),
              Text(_totalExpenses.format(_currency),
                  style: TextStyle(
                      fontFamily: t.numeralFamily, fontSize: 34, color: t.ink)),
            ],
          ),
        ),
        if (unassigned.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 0, 8),
            decoration: BoxDecoration(
              border:
                  BorderDirectional(end: BorderSide(color: t.danger, width: 2)),
            ),
            child: Text(
              context.l10n.pick(
                he: "${unassigned.length} הוצאות מסומנות 'לפי פרויקט' בלי פרויקט, ולכן אינן נכנסות לחישוב של אף עבודה.",
                en: "${unassigned.length} expenses are marked 'By Project' without a project, so they are not included in any project's calculation.",
              ),
              style: TextStyle(
                  fontFamily: t.labelFamily,
                  fontSize: 13,
                  height: 1.6,
                  color: t.danger),
            ),
          ),
        const SoferRule(strong: true),
        if (_expenses.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Text(
                context.l10n.pick(
                    he: "אין עוד הוצאות רשומות", en: "No expenses recorded"),
                style: TextStyle(
                    fontFamily: t.numeralFamily,
                    fontSize: 19,
                    color: t.inkMuted)),
          ),
        for (final group in groups)
          if (of(group.kind).isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(group.title,
                        style: TextStyle(
                            fontFamily: t.numeralFamily,
                            fontSize: 18,
                            color: t.ink)),
                  ),
                  Text(sum(of(group.kind)).format(_currency),
                      style: TextStyle(
                          fontFamily: t.numeralFamily,
                          fontSize: 18,
                          color: t.accent)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(group.note,
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 12,
                      color: t.inkFaint)),
            ),
            for (final e in of(group.kind)) _ruledExpenseRow(e),
            const SizedBox(height: 6),
            const SoferRule(strong: true),
          ],
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _ruledExpenseRow(Expense e) {
    final t = SoferTokens.of(context);
    return InkWell(
      onTap: () => _showAddOrEdit(e),
      child: Container(
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: t.rule))),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.expenseCategory(e.product),
                      style: TextStyle(
                          fontFamily: t.numeralFamily,
                          fontSize: 16,
                          color: t.ink)),
                  const SizedBox(height: 2),
                  Text(_allocationSummary(e),
                      style: TextStyle(
                          fontFamily: t.labelFamily,
                          fontSize: 12,
                          color: t.inkMuted)),
                ],
              ),
            ),
            Text(formatMoney(e.amount, e.currency),
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 19, color: t.ink)),
          ],
        ),
      ),
    );
  }

  IconData _allocationIcon(ExpenseAllocation a) => switch (a) {
        ExpenseAllocation.project => Icons.folder,
        ExpenseAllocation.period => Icons.date_range,
        ExpenseAllocation.month => Icons.calendar_month,
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final unassigned = ExpenseLogic.unassigned(_expenses);

    if (SoferTokens.of(context).isRules) {
      return Scaffold(
        appBar: AppBar(
            title: Text(context.l10n.pick(he: "הוצאות", en: "Expenses"))),
        body: SoferPage(maxWidth: 760, child: _ruledLedger(unassigned)),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddOrEdit(),
          child: const Icon(Icons.add),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(context.l10n.pick(he: "הוצאות", en: "Expenses")),
          centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              color: SoferTokens.of(context).paper,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                        context.l10n
                            .pick(he: "סה\"כ הוצאות", en: "Total expenses"),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(_totalExpenses.format(_currency, decimals: 2),
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: SoferTokens.of(context).caution)),
                  ],
                ),
              ),
            ),
          ),
          if (unassigned.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: SoferTokens.of(context).paper,
                child: ListTile(
                  leading: Icon(Icons.warning_amber,
                      color: SoferTokens.of(context).danger),
                  title: Text(
                      context.l10n.pick(
                        he: "${unassigned.length} הוצאות מסומנות 'לפי פרויקט' ללא פרויקט",
                        en: "${unassigned.length} expenses marked 'By Project' have no project",
                      ),
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      context.l10n.pick(
                          he: "הן לא נכללות בחישוב של אף פרויקט",
                          en: "They are not included in any project's calculation"),
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
          Expanded(
            child: _expenses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long,
                            size: 64, color: SoferTokens.of(context).inkFaint),
                        const SizedBox(height: 16),
                        Text(
                            context.l10n.pick(
                                he: "אין הוצאות עדיין", en: "No expenses yet"),
                            style: TextStyle(
                                fontSize: 18,
                                color: SoferTokens.of(context).inkMuted)),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _showAddOrEdit(),
                          icon: const Icon(Icons.add),
                          label: Text(context.l10n.pick(
                              he: "הוסף הוצאה ראשונה",
                              en: "Add first expense")),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _expenses.length,
                    itemBuilder: (context, index) {
                      final e = _expenses[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: SoferTokens.of(context).paper,
                            child: Icon(_allocationIcon(e.allocation),
                                color: SoferTokens.of(context).caution,
                                size: 20),
                          ),
                          title: Text(context.l10n.expenseCategory(e.product)),
                          subtitle: Text(
                            "${formatDisplayDate(e.date, _useGregorianDates, english: context.l10n.isEnglish)} · ${_allocationSummary(e)}",
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(formatMoneyExact(e.amount, e.currency),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: () => _showAddOrEdit(e),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete,
                                    size: 20,
                                    color: SoferTokens.of(context).danger),
                                onPressed: () => _confirmDelete(e),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _expenses.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _showAddOrEdit(),
              tooltip: context.l10n.pick(he: "הוסף הוצאה", en: "Add expense"),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
