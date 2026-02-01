import 'package:flutter/material.dart';
import 'models.dart';
import 'storage_service.dart';
import 'hebrew_utils.dart';

const List<String> _expenseCategories = [
  "קורס סת\"ם",
  "שולחן, כסא, פנס, מכשיר אדים",
  "הוצאות שוטפות",
  "קולמוס מגילות",
  "קולמוס מזוזות",
  "קולמוס תש\"י",
  "קולמוס תש\"ר",
  "משלוחים ונסיעות",
  "תעודה",
  "דיו, מי קלף, ציוד",
  "תיקון סופרים",
  "משקפיים",
  "קלף והגהות מגילות",
  "מחיקות מזוזות",
  "קלף מזוזות",
  "הגהות מזוזות",
  "קלף תפילין",
  "הגהות תפילין",
  "חדר סופרים",
];

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final StorageService _storage = StorageService();
  List<Expense> _expenses = [];
  bool _useGregorianDates = false;
  bool _loading = true;

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
        _expenses = list;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await _storage.saveExpenses(_expenses);
  }

  double get _totalExpenses => _expenses.fold(0, (sum, e) => sum + e.amount);

  void _showAddOrEdit([Expense? existing]) {
    final isEdit = existing != null;
    final productCtrl = TextEditingController(text: existing?.product ?? '');
    final amountCtrl = TextEditingController(
        text: existing != null ? existing.amount.toString() : '');
    DateTime pickedDate = existing?.date ?? DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? "עריכת הוצאה" : "הוספת הוצאה"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _expenseCategories.contains(productCtrl.text)
                      ? productCtrl.text
                      : '',
                  decoration: const InputDecoration(
                    labelText: "מוצר / קטגוריה (אופציונלי)",
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text("בחר קטגוריה או הזן למטה")),
                    ..._expenseCategories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                  ],
                  onChanged: (v) {
                    productCtrl.text = v ?? '';
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
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: pickedDate,
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) {
                          setDialogState(() => pickedDate = d);
                        }
                      },
                      icon: const Icon(Icons.calendar_today),
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ביטול"),
            ),
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
                if (isEdit) {
                  final idx = _expenses.indexWhere((e) => e.id == existing.id);
                  if (idx >= 0) {
                    _expenses[idx] = Expense(
                      id: existing.id,
                      product: product,
                      date: pickedDate,
                      amount: amount,
                    );
                  }
                } else {
                  _expenses.add(Expense(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    product: product,
                    date: pickedDate,
                    amount: amount,
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
              _expenses.removeWhere((x) => x.id == e.id);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("הוצאות"),
        centerTitle: true,
      ),
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
                    const Text(
                      "סה\"כ הוצאות",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "₪${_totalExpenses.toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ],
                ),
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
                        Text(
                          "אין הוצאות עדיין",
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                        ),
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
                            child: Icon(Icons.receipt,
                                color: Colors.orange.shade800),
                          ),
                          title: Text(e.product),
                          subtitle: Text(
                              formatDisplayDate(e.date, _useGregorianDates)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "₪${e.amount.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
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
              child: const Icon(Icons.add),
              tooltip: "הוסף הוצאה",
            )
          : null,
    );
  }
}
