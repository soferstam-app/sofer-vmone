import 'package:flutter/material.dart';

import 'hebrew_utils.dart';
import 'logic/expense_logic.dart';
import 'logic/id_generator.dart';
import 'models.dart';
import 'storage_service.dart';

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
    final list = await _storage.loadExpenses();
    if (mounted) {
      setState(() {
        _useGregorianDates = useGregorian;
        _all = list;
        _loading = false;
      });
    }
  }

  Future<void> _save() async => _storage.saveExpenses(_all);

  double get _totalExpenses => _expenses.fold(0, (sum, e) => sum + e.amount);

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
        return '${e.projectIds.length} פרויקטים (₪${e.amountPerProject.toStringAsFixed(0)} כל אחד)';
      case ExpenseAllocation.period:
        final s = e.periodStart, en = e.periodEnd;
        if (s == null || en == null) return 'תקופה לא הוגדרה';
        return '${formatDisplayDate(s, _useGregorianDates)} – ${formatDisplayDate(en, _useGregorianDates)}';
      case ExpenseAllocation.month:
        return 'חודשי';
    }
  }

  void _showAddOrEdit([Expense? existing]) {
    final isEdit = existing != null;
    final productCtrl = TextEditingController(text: existing?.product ?? '');
    final amountCtrl = TextEditingController(
        text: existing != null ? existing.amount.toString() : '');

    var pickedDate = existing?.date ?? DateTime.now();
    var allocation = existing?.allocation ?? ExpenseAllocation.month;
    final selectedProjects = <String>{...(existing?.projectIds ?? const [])};
    var periodStart = existing?.periodStart;
    var periodEnd = existing?.periodEnd;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "תאריך: ${formatDisplayDate(pickedDate, _useGregorianDates)}",
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
                    if (widget.projects.where((p) => !p.isDeleted).isEmpty)
                      const Text("אין פרויקטים לשייך אליהם",
                          style: TextStyle(color: Colors.red, fontSize: 13))
                    else ...[
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                            "אפשר לבחור כמה פרויקטים – הסכום יתחלק ביניהם",
                            style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(height: 6),
                      ...widget.projects.where((p) => !p.isDeleted).map(
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
                    const Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text("הסכום יתחלק על פני התקופה שתבחר",
                          style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(height: 6),
                    _periodRow(ctx, "מתאריך", periodStart ?? pickedDate,
                        (d) => setDialogState(() => periodStart = d)),
                    _periodRow(
                        ctx,
                        "עד תאריך",
                        periodEnd ?? pickedDate.add(const Duration(days: 90)),
                        (d) => setDialogState(() => periodEnd = d)),
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
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("ביטול")),
            ElevatedButton(
              onPressed: () {
                final product = productCtrl.text.trim();
                final amount =
                    double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0;
                if (product.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("יש להזין מוצר/קטגוריה")),
                  );
                  return;
                }
                final start = allocation == ExpenseAllocation.period
                    ? (periodStart ?? pickedDate)
                    : null;
                final end = allocation == ExpenseAllocation.period
                    ? (periodEnd ?? pickedDate.add(const Duration(days: 90)))
                    : null;

                if (isEdit) {
                  final idx = _all.indexWhere((e) => e.id == existing.id);
                  if (idx >= 0) {
                    _all[idx] = existing.copyWith(
                      product: product,
                      date: pickedDate,
                      amount: amount,
                      allocation: allocation,
                      projectIds: selectedProjects.toList(),
                      periodStart: start,
                      periodEnd: end,
                    );
                  }
                } else {
                  _all.add(Expense(
                    id: IdGenerator.generate(),
                    product: product,
                    date: pickedDate,
                    amount: amount,
                    allocation: allocation,
                    projectIds: selectedProjects.toList(),
                    periodStart: start,
                    periodEnd: end,
                  ));
                }
                _save();
                setState(() {});
                Navigator.pop(ctx);
              },
              child: Text(isEdit ? "שמור" : "הוסף"),
            ),
          ],
        ),
      ),
    ).then((_) {
      productCtrl.dispose();
      amountCtrl.dispose();
    });
  }

  Widget _periodRow(BuildContext ctx, String label, DateTime value,
      ValueChanged<DateTime> onPicked) {
    return Row(
      children: [
        Expanded(
          child: Text("$label: ${formatDisplayDate(value, _useGregorianDates)}",
              style: const TextStyle(fontSize: 14)),
        ),
        TextButton(
          onPressed: () async {
            final d = await showDatePicker(
              context: ctx,
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

  void _confirmDelete(Expense e) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מחיקת הוצאה"),
        content:
            Text("למחוק \"${e.product}\" (₪${e.amount.toStringAsFixed(2)})?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              // Soft delete so the removal survives a merge.
              final idx = _all.indexWhere((x) => x.id == e.id);
              if (idx >= 0) _all[idx] = e.copyWith(isDeleted: true);
              _save();
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text("מחק"),
          ),
        ],
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

    return Scaffold(
      appBar: AppBar(title: const Text("הוצאות"), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("סה\"כ הוצאות",
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text("₪${_totalExpenses.toStringAsFixed(2)}",
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange)),
                  ],
                ),
              ),
            ),
          ),
          if (unassigned.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.red.shade50,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber, color: Colors.red),
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
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text("אין הוצאות עדיין",
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey.shade600)),
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
                            backgroundColor: Colors.orange.shade100,
                            child: Icon(_allocationIcon(e.allocation),
                                color: Colors.orange.shade800, size: 20),
                          ),
                          title: Text(e.product),
                          subtitle: Text(
                            "${formatDisplayDate(e.date, _useGregorianDates)} · ${_allocationSummary(e)}",
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("₪${e.amount.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: () => _showAddOrEdit(e),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete,
                                    size: 20, color: Colors.red.shade700),
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
