import 'package:flutter/material.dart';

import 'hebrew_utils.dart';
import 'logic/currency.dart';
import 'logic/id_generator.dart';
import 'l10n/app_localizations.dart';
import 'models.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/confirm.dart';
import 'widgets/feedback.dart';
import 'widgets/sofer_widgets.dart';

/// A simple commitment book, separate from the writing projects themselves.
///
/// One order may contain several kinds of work, and a line can be supplied
/// partially. It therefore cannot be represented by a single Project.
class OrdersScreen extends StatefulWidget {
  final List<Project> projects;

  const OrdersScreen({super.key, this.projects = const []});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final StorageService _storage = StorageService();
  final TextEditingController _search = TextEditingController();
  List<Order> _all = const [];
  Currency _currency = Currency.ils;
  bool _useGregorianDates = false;
  bool _loading = true;
  bool _allMonths = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  List<Order> get _visible {
    final query = _search.text.trim().toLowerCase();
    final result = _all.where((order) {
      if (order.isDeleted) {
        return false;
      }
      if (!_allMonths &&
          (order.dueDate.year != _month.year ||
              order.dueDate.month != _month.month)) {
        return false;
      }
      if (query.isNotEmpty &&
          !('${order.customerName} ${order.phone} ${order.email}'
              .toLowerCase()
              .contains(query))) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final due = a.dueDate.compareTo(b.dueDate);
        return due != 0
            ? due
            : a.customerName
                .toLowerCase()
                .compareTo(b.customerName.toLowerCase());
      });
    return result;
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final orders = await _storage.loadOrders();
    final currency = await _storage.getCurrency();
    final gregorian = await _storage.getUseGregorianDates();
    if (!mounted) return;
    setState(() {
      _all = orders;
      _currency = currency;
      _useGregorianDates = gregorian;
      _loading = false;
    });
  }

  Future<void> _save(Order order) async {
    final next = [..._all];
    final index = next.indexWhere((item) => item.id == order.id);
    if (index == -1) {
      next.add(order);
    } else {
      next[index] = order;
    }
    await _storage.saveOrders(next);
    if (!mounted) return;
    setState(() => _all = next);
  }

  Future<void> _edit({Order? existing}) async {
    final order = await showDialog<Order>(
      context: context,
      builder: (_) => OrderEditorDialog(
        existing: existing,
        projects: widget.projects.where((p) => !p.isDeleted).toList(),
        currency: _currency,
        useGregorianDates: _useGregorianDates,
      ),
    );
    if (order == null || !mounted) return;
    try {
      await _save(order);
      if (mounted) {
        showAppSuccess(
            context, context.l10n.pick(he: 'ההזמנה נשמרה', en: 'Order saved'));
      }
    } catch (error) {
      debugPrint('Could not save order: $error');
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
              he: 'שמירת ההזמנה לא הושלמה.',
              en: 'The order could not be saved.',
            ));
      }
    }
  }

  Future<void> _delete(Order order) async {
    final sure = await confirmAction(
      context,
      title: context.l10n.pick(he: 'מחיקת הזמנה', en: 'Delete order'),
      message: context.l10n.pick(
        he: 'ההזמנה תעבור לסל המיחזור ולא תופיע ברשימה.',
        en: 'The order will move to the Recycle Bin and disappear from the list.',
      ),
      confirmLabel: context.l10n.pick(he: 'מחק', en: 'Delete'),
      danger: true,
    );
    if (!sure || !mounted) return;
    await _save(order.copyWith(isDeleted: true));
  }

  Future<void> _markSupplied(Order order) async {
    if (order.unreadableItems.isNotEmpty) {
      showAppError(
          context,
          context.l10n.pick(
            he: 'לא ניתן לסמן אספקה מלאה: יש פריטים שאינם נתמכים בגרסה זו. הפריטים נשמרו; יש לפתוח את ההזמנה בגרסה שתומכת בהם.',
            en: 'Cannot mark as fully supplied: this version cannot read some items. They are retained; open this order in a version that supports them.',
          ));
      return;
    }
    final now = DateTime.now();
    await _save(order.copyWith(
      items: [
        for (final item in order.items)
          item.copyWith(suppliedQuantity: item.quantity),
      ],
      status: OrderStatus.supplied,
      suppliedAt: now,
    ));
  }

  void _moveMonth(int delta) {
    setState(() {
      _allMonths = false;
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  String _date(DateTime date) => formatDisplayDate(
        date,
        _useGregorianDates,
        english: context.l10n.isEnglish,
      );

  String _typeLabel(ProjectType type) => switch (type) {
        ProjectType.sefer =>
          context.l10n.pick(he: 'ספר תורה', en: 'Sefer Torah'),
        ProjectType.mezuza => context.l10n.pick(he: 'מזוזה', en: 'Mezuzah'),
        ProjectType.tefillin => context.l10n.pick(he: 'תפילין', en: 'Tefillin'),
        ProjectType.megillah => context.l10n.pick(he: 'מגילה', en: 'Megillah'),
      };

  String _itemsSummary(Order order) {
    final unknown = order.unreadableItems.length;
    if (unknown > 0) {
      return context.l10n.pick(
        he: '${order.items.length} פריטים מוכרים · $unknown פריטים לא נתמכים שנשמרו',
        en: '${order.items.length} readable items · $unknown unsupported items retained',
      );
    }
    if (order.items.isEmpty) {
      return context.l10n.pick(he: 'ללא פריטים', en: 'No items');
    }
    return order.items
        .map((item) => '${item.quantity} × ${_typeLabel(item.type)}')
        .join(' · ');
  }

  String _statusLabel(Order order) {
    if (order.status == OrderStatus.cancelled) {
      return context.l10n.pick(he: 'בוטלה', en: 'Cancelled');
    }
    if (order.isFullySupplied) {
      return context.l10n.pick(he: 'סופקה', en: 'Supplied');
    }
    if (order.suppliedQuantity > 0) {
      return context.l10n.pick(he: 'סופקה חלקית', en: 'Partially supplied');
    }
    return context.l10n.pick(he: 'פתוחה', en: 'Open');
  }

  Color _statusColor(Order order, SoferTokens tokens) {
    if (order.status == OrderStatus.cancelled) return tokens.inkMuted;
    if (order.isFullySupplied) return Colors.green.shade700;
    if (order.suppliedQuantity > 0) return tokens.accent;
    return tokens.inkMuted;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = SoferTokens.of(context);
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.pick(he: 'הזמנות', en: 'Orders')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.pick(he: 'הזמנה חדשה', en: 'New order')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SoferPage(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  _summary(visible, tokens),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: context.l10n
                          .pick(he: 'חיפוש מזמין', en: 'Search customer'),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _search.clear,
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _monthBar(),
                  const SizedBox(height: 10),
                  if (visible.isEmpty)
                    _empty(tokens)
                  else
                    for (final order in visible) _orderCard(order, tokens),
                ],
              ),
            ),
    );
  }

  Widget _summary(List<Order> visible, SoferTokens tokens) {
    final open = visible
        .where((o) => o.status != OrderStatus.cancelled && !o.isFullySupplied)
        .length;
    final supplied = visible
        .where((o) => o.status != OrderStatus.cancelled && o.isFullySupplied)
        .length;
    return SoferPanel(
      child: Row(
        children: [
          Expanded(
            child: SoferStatRow(
              context.l10n.pick(he: 'פתוחות', en: 'Open'),
              '$open',
              last: false,
            ),
          ),
          Expanded(
            child: SoferStatRow(
              context.l10n.pick(he: 'סופקו', en: 'Supplied'),
              '$supplied',
              last: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthBar() {
    final monthLabel = _allMonths
        ? context.l10n.pick(he: 'כל החודשים', en: 'All months')
        : '${_month.month.toString().padLeft(2, '0')}/${_month.year}';
    return Row(
      children: [
        IconButton(
          tooltip: context.l10n.pick(he: 'חודש קודם', en: 'Previous month'),
          onPressed: _allMonths ? null : () => _moveMonth(-1),
          icon: const Icon(Icons.chevron_right),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _allMonths = !_allMonths),
            icon: const Icon(Icons.calendar_month),
            label: Text(monthLabel),
          ),
        ),
        IconButton(
          tooltip: context.l10n.pick(he: 'חודש הבא', en: 'Next month'),
          onPressed: _allMonths ? null : () => _moveMonth(1),
          icon: const Icon(Icons.chevron_left),
        ),
      ],
    );
  }

  Widget _empty(SoferTokens tokens) => SoferPanel(
        child: Column(
          children: [
            Icon(Icons.assignment_outlined, size: 42, color: tokens.inkFaint),
            const SizedBox(height: 10),
            Text(
              context.l10n.pick(
                he: 'אין הזמנות להצגה בחודש הזה.',
                en: 'There are no orders to show for this month.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.inkMuted),
            ),
          ],
        ),
      );

  Widget _orderCard(Order order, SoferTokens tokens) {
    final color = _statusColor(order, tokens);
    final overdue = order.status != OrderStatus.cancelled &&
        !order.isFullySupplied &&
        DateUtils.dateOnly(order.dueDate)
            .isBefore(DateUtils.dateOnly(DateTime.now()));
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _edit(existing: order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.customerName,
                            style: TextStyle(
                              fontFamily: tokens.numeralFamily,
                              fontSize: 18,
                              color: tokens.ink,
                            ),
                          ),
                        ),
                        Text(
                          _statusLabel(order),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(_itemsSummary(order),
                        style: TextStyle(color: tokens.inkMuted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          context.l10n.pick(he: 'מסירה: ', en: 'Due: ') +
                              _date(order.dueDate),
                          style: TextStyle(
                            color: overdue ? tokens.danger : tokens.inkMuted,
                            fontWeight: overdue ? FontWeight.bold : null,
                          ),
                        ),
                        Text(order.currency.format(order.price),
                            style: TextStyle(color: tokens.inkMuted)),
                        if (order.suppliedQuantity > 0 &&
                            !order.isFullySupplied)
                          Text(
                            '${order.suppliedQuantity}/${order.totalQuantity}',
                            style: TextStyle(color: tokens.accent),
                          ),
                      ],
                    ),
                    if (order.requirements.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        order.requirements,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12.5, color: tokens.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  try {
                    if (value == 'supply') await _markSupplied(order);
                    if (value == 'delete') await _delete(order);
                    if (value == 'cancel') {
                      await _save(
                          order.copyWith(status: OrderStatus.cancelled));
                    }
                    if (value == 'reactivate') {
                      await _save(order.copyWith(
                          status: order.isFullySupplied
                              ? OrderStatus.supplied
                              : order.suppliedQuantity > 0
                                  ? OrderStatus.partial
                                  : OrderStatus.open));
                    }
                  } catch (error) {
                    if (mounted) {
                      showAppError(
                          context,
                          context.l10n.pick(
                              he: 'שינוי ההזמנה נכשל: $error',
                              en: 'Order update failed: $error'));
                    }
                  }
                },
                itemBuilder: (ctx) => [
                  if (order.status != OrderStatus.cancelled &&
                      !order.isFullySupplied)
                    PopupMenuItem(
                      value: 'supply',
                      child: Text(context.l10n
                          .pick(he: 'סמן כסופקה', en: 'Mark as supplied')),
                    ),
                  PopupMenuItem(
                    value: order.status == OrderStatus.cancelled
                        ? 'reactivate'
                        : 'cancel',
                    child: Text(order.status == OrderStatus.cancelled
                        ? context.l10n
                            .pick(he: 'החזר לפעילות', en: 'Reactivate')
                        : context.l10n
                            .pick(he: 'בטל הזמנה', en: 'Cancel order')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(context.l10n.pick(he: 'מחק', en: 'Delete')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderEditorDialog extends StatefulWidget {
  final Order? existing;
  final List<Project> projects;
  final Currency currency;
  final bool useGregorianDates;

  const OrderEditorDialog({
    super.key,
    this.existing,
    required this.projects,
    required this.currency,
    required this.useGregorianDates,
  });

  @override
  State<OrderEditorDialog> createState() => _OrderEditorDialogState();
}

class _OrderEditorDialogState extends State<OrderEditorDialog> {
  late final TextEditingController _customer;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _requirements;
  late final TextEditingController _price;
  late DateTime _dueDate;
  late Currency _currency;
  late List<_OrderItemDraft> _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _customer = TextEditingController(text: existing?.customerName ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _email = TextEditingController(text: existing?.email ?? '');
    _requirements = TextEditingController(text: existing?.requirements ?? '');
    _price = TextEditingController(
        text: existing == null || existing.price == 0
            ? ''
            : existing.price.toString());
    _dueDate = existing?.dueDate ?? DateUtils.dateOnly(DateTime.now());
    _currency = existing?.currency ?? widget.currency;
    _items = existing == null
        ? [_OrderItemDraft()]
        : [for (final item in existing.items) _OrderItemDraft.from(item)];
  }

  @override
  void dispose() {
    _customer.dispose();
    _phone.dispose();
    _email.dispose();
    _requirements.dispose();
    _price.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  String _date(DateTime date) => formatDisplayDate(
        date,
        widget.useGregorianDates,
        english: context.l10n.isEnglish,
      );

  String _typeLabel(ProjectType type) => switch (type) {
        ProjectType.sefer =>
          context.l10n.pick(he: 'ספר תורה', en: 'Sefer Torah'),
        ProjectType.mezuza => context.l10n.pick(he: 'מזוזה', en: 'Mezuzah'),
        ProjectType.tefillin => context.l10n.pick(he: 'תפילין', en: 'Tefillin'),
        ProjectType.megillah => context.l10n.pick(he: 'מגילה', en: 'Megillah'),
      };

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = DateUtils.dateOnly(picked));
    }
  }

  void _save() {
    final customer = _customer.text.trim();
    if (customer.isEmpty) {
      setState(() => _error = context.l10n
          .pick(he: 'יש להזין שם מזמין.', en: 'Enter a customer name.'));
      return;
    }
    if (_items.isEmpty && (widget.existing?.unreadableItems.isEmpty ?? true)) {
      setState(() => _error = context.l10n
          .pick(he: 'יש להוסיף לפחות פריט אחד.', en: 'Add at least one item.'));
      return;
    }
    final parsedItems = <OrderItem>[];
    for (final draft in _items) {
      final quantity = int.tryParse(draft.quantity.text.trim());
      final supplied = int.tryParse(draft.supplied.text.trim().isEmpty
          ? '0'
          : draft.supplied.text.trim());
      if (quantity == null ||
          quantity < 1 ||
          supplied == null ||
          supplied < 0 ||
          supplied > quantity) {
        setState(() => _error = context.l10n.pick(
              he: 'יש לבדוק את הכמויות בכל פריט.',
              en: 'Check the quantities in every item.',
            ));
        return;
      }
      parsedItems.add(OrderItem(
        id: draft.id.isEmpty ? IdGenerator.generate(suffix: 'item') : draft.id,
        type: draft.type,
        quantity: quantity,
        suppliedQuantity: supplied,
        notes: draft.notes.text.trim(),
        projectId: draft.projectId,
        extraFields: draft.extraFields,
      ));
    }
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (price == null || price < 0) {
      setState(() => _error = context.l10n
          .pick(he: 'יש להזין מחיר תקין.', en: 'Enter a valid price.'));
      return;
    }
    final allSupplied = (widget.existing?.unreadableItems.isEmpty ?? true) &&
        parsedItems.every((item) => item.isSupplied);
    final anySupplied = parsedItems.any((item) => item.suppliedQuantity > 0);
    final status = allSupplied
        ? OrderStatus.supplied
        : anySupplied
            ? OrderStatus.partial
            : OrderStatus.open;
    final existing = widget.existing;
    Navigator.pop(
      context,
      Order(
        id: existing?.id ?? IdGenerator.generate(),
        customerName: customer,
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        orderedAt: existing?.orderedAt ?? DateUtils.dateOnly(DateTime.now()),
        dueDate: _dueDate,
        requirements: _requirements.text.trim(),
        price: price,
        currency: _currency,
        items: parsedItems,
        unreadableItems: existing?.unreadableItems ?? const [],
        status: (existing?.unreadableItems.isNotEmpty ?? false)
            ? existing!.status
            : existing?.status == OrderStatus.cancelled
                ? OrderStatus.cancelled
                : status,
        suppliedAt: (existing?.unreadableItems.isNotEmpty ?? false)
            ? existing?.suppliedAt
            : allSupplied
                ? (existing?.suppliedAt ?? DateTime.now())
                : null,
        lastUpdated: DateTime.now(),
        deletedAt: existing?.deletedAt,
        restoredAt: existing?.restoredAt,
        extraFields: existing?.extraFields ?? const {},
      ),
    );
  }

  Widget _itemEditor(_OrderItemDraft item, int index) {
    final tokens = SoferTokens.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ProjectType>(
                    initialValue: item.type,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText:
                          context.l10n.pick(he: 'סוג פריט', en: 'Item type'),
                    ),
                    items: [
                      for (final type in ProjectType.values)
                        DropdownMenuItem(
                            value: type, child: Text(_typeLabel(type))),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => item.type = value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 82,
                  child: TextField(
                    controller: item.quantity,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.l10n.pick(he: 'כמות', en: 'Qty'),
                    ),
                  ),
                ),
                if (_items.length > 1)
                  IconButton(
                    tooltip:
                        context.l10n.pick(he: 'הסר פריט', en: 'Remove item'),
                    onPressed: () => setState(() {
                      _items.removeAt(index);
                      item.dispose();
                    }),
                    icon: Icon(Icons.delete_outline, color: tokens.danger),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: item.supplied,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.l10n.pick(he: 'סופק', en: 'Supplied'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String?>(
                    initialValue: item.projectId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.l10n.pick(
                          he: 'פרויקט מקושר (לא חובה)',
                          en: 'Linked project (optional)'),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(context.l10n
                            .pick(he: 'ללא פרויקט', en: 'No project')),
                      ),
                      if (item.projectId != null &&
                          widget.projects.every((p) => p.id != item.projectId))
                        DropdownMenuItem<String?>(
                            value: item.projectId,
                            child: Text(context.l10n.pick(
                                he: 'פרויקט שנמחק או אינו זמין',
                                en: 'Deleted or unavailable project'))),
                      for (final project in widget.projects)
                        DropdownMenuItem<String?>(
                            value: project.id, child: Text(project.name)),
                    ],
                    onChanged: (value) =>
                        setState(() => item.projectId = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.notes,
              maxLines: 2,
              decoration: InputDecoration(
                labelText:
                    context.l10n.pick(he: 'פירוט לפריט', en: 'Item details'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(context.l10n.pick(
        he: existing == null ? 'הזמנה חדשה' : 'עריכת הזמנה',
        en: existing == null ? 'New order' : 'Edit order',
      )),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _customer,
                autofocus: existing == null,
                decoration: InputDecoration(
                  labelText: context.l10n
                      .pick(he: 'שם המזמין *', en: 'Customer name *'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: context.l10n.pick(he: 'טלפון', en: 'Phone'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: context.l10n.pick(he: 'אימייל', en: 'Email'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event),
                      label: Text(
                          '${context.l10n.pick(he: 'מסירה', en: 'Due')}: ${_date(_dueDate)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: context.l10n
                            .pick(he: 'מחיר כולל', en: 'Total price'),
                        prefixText: '${_currency.symbol} ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Currency>(
                initialValue: _currency,
                decoration: InputDecoration(
                  labelText: context.l10n.pick(he: 'מטבע', en: 'Currency'),
                ),
                items: [
                  for (final currency in {
                    ...Currency.offered,
                    _currency,
                  })
                    DropdownMenuItem(
                        value: currency,
                        child: Text('${currency.name} (${currency.code})')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _currency = value);
                },
              ),
              const SizedBox(height: 14),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  context.l10n.pick(he: 'פריטי ההזמנה', en: 'Order items'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (widget.existing?.unreadableItems.isNotEmpty ?? false)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      context.l10n.pick(
                        he: 'יש בהזמנה פריטים שלא נתמכים בגרסה זו. הם נשמרים ללא שינוי; הכמויות המוצגות מתייחסות לפריטים המוכרים בלבד.',
                        en: 'Some items are unsupported in this version. They are retained unchanged; displayed quantities cover readable items only.',
                      ),
                    )),
              const SizedBox(height: 6),
              for (var i = 0; i < _items.length; i++) _itemEditor(_items[i], i),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _items.add(_OrderItemDraft())),
                  icon: const Icon(Icons.add),
                  label:
                      Text(context.l10n.pick(he: 'הוסף פריט', en: 'Add item')),
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _requirements,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.l10n.pick(
                      he: 'דרישות מיוחדות והערות',
                      en: 'Special requirements and notes'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(_error!,
                      style: TextStyle(color: SoferTokens.of(context).danger)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        ElevatedButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: Text(context.l10n.pick(he: 'שמור', en: 'Save')),
        ),
      ],
    );
  }
}

class _OrderItemDraft {
  final Map<String, dynamic> extraFields;
  final String id;
  ProjectType type;
  final TextEditingController quantity;
  final TextEditingController supplied;
  final TextEditingController notes;
  String? projectId;

  _OrderItemDraft({
    this.extraFields = const {},
    this.id = '',
    this.type = ProjectType.sefer,
    int quantity = 1,
    int supplied = 0,
    String notes = '',
    this.projectId,
  })  : quantity = TextEditingController(text: quantity.toString()),
        supplied = TextEditingController(
            text: supplied == 0 ? '' : supplied.toString()),
        notes = TextEditingController(text: notes);

  factory _OrderItemDraft.from(OrderItem item) => _OrderItemDraft(
        extraFields: item.extraFields,
        id: item.id,
        type: item.type,
        quantity: item.quantity,
        supplied: item.suppliedQuantity,
        notes: item.notes,
        projectId: item.projectId,
      );

  void dispose() {
    quantity.dispose();
    supplied.dispose();
    notes.dispose();
  }
}
