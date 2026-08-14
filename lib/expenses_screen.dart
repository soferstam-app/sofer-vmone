import 'package:flutter/material.dart';

import 'expenses/expense_editor.dart';
import 'hebrew_utils.dart';
import 'logic/expense_logic.dart';
import 'models.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/sofer_widgets.dart';
import 'format.dart';
import 'logic/currency.dart';

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

  Future<void> _save() async => _storage.saveExpenses(_all);

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
    return 'פרויקט שנמחק';
  }

  /// One line describing where this expense lands, so the list is readable
  /// without opening each row.
  String _allocationSummary(Expense e) {
    switch (e.allocation) {
      case ExpenseAllocation.project:
        if (e.projectIds.isEmpty) return '⚠ לא שויך לפרויקט';
        if (e.projectIds.length == 1) return _projectName(e.projectIds.first);
        return '${e.projectIds.length} פרויקטים (${formatMoney(e.amountPerProject, e.currency)} כל אחד)';
      case ExpenseAllocation.period:
        final s = e.periodStart, en = e.periodEnd;
        if (s == null || en == null) return 'תקופה לא הוגדרה';
        return '${formatDisplayDate(s, _useGregorianDates)} – ${formatDisplayDate(en, _useGregorianDates)}';
      case ExpenseAllocation.month:
        return 'חודשי';
    }
  }

  /// Opens the shared editor, then applies whatever came back.
  ///
  /// The form itself lives in expenses/expense_editor.dart, so the quote screen
  /// can use the very same one. This method only decides what a result means for
  /// the stored list.
  Future<void> _showAddOrEdit([Expense? existing]) async {
    final edit = await showExpenseEditor(
      context: context,
      existing: existing,
      projects: widget.projects,
      useGregorianDates: _useGregorianDates,
      currency: _currency,
    );
    if (edit == null || !mounted) return;

    if (edit.deleted) {
      await _softDelete(edit.expense);
      return;
    }

    final idx = _all.indexWhere((x) => x.id == edit.expense.id);
    if (idx >= 0) {
      _all[idx] = edit.expense;
    } else {
      _all.add(edit.expense);
    }
    await _save();
    if (mounted) setState(() {});
  }

  /// Marked deleted rather than dropped from the list, so the removal survives a
  /// merge against a device still holding the row.
  Future<void> _softDelete(Expense e) async {
    final idx = _all.indexWhere((x) => x.id == e.id);
    if (idx >= 0) _all[idx] = _all[idx].copyWith(isDeleted: true);
    await _save();
    if (mounted) setState(() {});
  }

  void _confirmDelete(Expense e) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מחיקת הוצאה"),
        content:
            Text("למחוק \"${e.product}\" (${formatMoneyExact(e.amount, e.currency)})?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SoferTokens.of(ctx).danger),
            onPressed: () {
              Navigator.pop(ctx);
              _softDelete(e);
            },
            child: const Text("מחק"),
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
        title: "לפי פרויקט",
        note: "נכנס לחישוב הרווח של העבודה שהוא נצרך בה"
      ),
      (
        kind: ExpenseAllocation.period,
        title: "לפי תקופה",
        note: "מתפרס על פני הימים שבין שני התאריכים"
      ),
      (
        kind: ExpenseAllocation.month,
        title: "לפי חודש",
        note: "נכנס במלואו לחודש שבו הוא שולם"
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
                child: Text("סך ההוצאות",
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 12,
                        letterSpacing: 1.5,
                        color: t.inkMuted)),
              ),
              Text(_totalExpenses.format(_currency),
                  style: TextStyle(
                      fontFamily: t.numeralFamily,
                      fontSize: 34,
                      color: t.ink)),
            ],
          ),
        ),
        if (unassigned.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 0, 8),
            decoration: BoxDecoration(
              border: BorderDirectional(
                  end: BorderSide(color: t.danger, width: 2)),
            ),
            child: Text(
              "${unassigned.length} הוצאות מסומנות 'לפי פרויקט' בלי פרויקט, "
              "ולכן אינן נכנסות לחישוב של אף עבודה.",
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
            child: Text("אין עוד הוצאות רשומות",
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
                  Text(e.product,
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
        appBar: AppBar(title: const Text("הוצאות")),
        body: SoferPage(maxWidth: 760, child: _ruledLedger(unassigned)),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddOrEdit(),
          child: const Icon(Icons.add),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("הוצאות"), centerTitle: true),
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
                    const Text("סה\"כ הוצאות",
                        style: TextStyle(
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
                  leading: Icon(Icons.warning_amber, color: SoferTokens.of(context).danger),
                  title: Text(
                      "${unassigned.length} הוצאות מסומנות 'לפי פרויקט' ללא פרויקט",
                      style: const TextStyle(fontSize: 13)),
                  subtitle: const Text("הן לא נכללות בחישוב של אף פרויקט",
                      style: TextStyle(fontSize: 12)),
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
                        Text("אין הוצאות עדיין",
                            style: TextStyle(
                                fontSize: 18, color: SoferTokens.of(context).inkMuted)),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _showAddOrEdit(),
                          icon: const Icon(Icons.add),
                          label: const Text("הוסף הוצאה ראשונה"),
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
                                color: SoferTokens.of(context).caution, size: 20),
                          ),
                          title: Text(e.product),
                          subtitle: Text(
                            "${formatDisplayDate(e.date, _useGregorianDates)} · ${_allocationSummary(e)}",
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
                                    size: 20, color: SoferTokens.of(context).danger),
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
              tooltip: "הוסף הוצאה",
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
