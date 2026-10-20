import 'package:flutter/material.dart';
import 'models.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/feedback.dart';
import 'widgets/confirm.dart';
import 'l10n/app_localizations.dart';

class RecycleBinScreen extends StatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  State<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

/// How long a deleted project stays listed here.
const Duration _binWindow = Duration(days: 30);

class _RecycleBinScreenState extends State<RecycleBinScreen> {
  List<Project> _deletedProjects = [];
  List<WorkSession> _deletedSessions = [];
  List<Order> _deletedOrders = [];
  List<Proofread> _deletedProofreads = [];
  List<Expense> _deletedExpenses = [];
  List<Payment> _deletedPayments = [];
  bool _restoring = false;
  Map<String, String> _projectNames = const {};
  bool _isLoading = true;
  final StorageService _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _loadDeletedItems();
  }

  Future<void> _loadDeletedItems() async {
    setState(() => _isLoading = true);
    final allProjects = await _storage.loadProjects();
    final allHistory = await _storage.loadHistory();
    final orders = await _storage.loadOrders();
    final proofreads = await _storage.loadProofreads();
    final expenses = await _storage.loadExpenses();
    final payments = await _storage.loadPayments();
    // Deleted records are kept for ever — dropping a tombstone is how a
    // deletion gets undone by a device that was away. The bin shows the recent
    // ones; the rest stop being listed, which is all "the bin empties itself"
    // ever meant.
    final cutoff = DateTime.now().subtract(_binWindow);
    final deleted = allProjects
        .where((p) =>
            p.isDeleted &&
            (p.deletedAt == null || p.deletedAt!.isAfter(cutoff)))
        .toList();
    deleted.sort((a, b) =>
        (b.deletedAt ?? b.lastUpdated).compareTo(a.deletedAt ?? a.lastUpdated));
    final deletedSessions = allHistory
        .where((session) =>
            session.isDeleted &&
            session.extraFields['appCorrectionSourceId'] == null &&
            (session.deletedAt == null || session.deletedAt!.isAfter(cutoff)))
        .toList()
      ..sort((a, b) => (b.deletedAt ?? b.lastUpdated)
          .compareTo(a.deletedAt ?? a.lastUpdated));

    if (mounted) {
      setState(() {
        _deletedOrders = orders
            .where((r) =>
                r.isDeleted &&
                (r.deletedAt == null || r.deletedAt!.isAfter(cutoff)))
            .toList();
        _deletedProofreads = proofreads
            .where((r) =>
                r.isDeleted &&
                (r.deletedAt == null || r.deletedAt!.isAfter(cutoff)))
            .toList();
        _deletedExpenses = expenses
            .where((r) =>
                r.isDeleted &&
                (r.deletedAt == null || r.deletedAt!.isAfter(cutoff)))
            .toList();
        _deletedPayments = payments
            .where((r) =>
                r.isDeleted &&
                (r.deletedAt == null || r.deletedAt!.isAfter(cutoff)))
            .toList();
        _deletedProjects = deleted;
        _deletedSessions = deletedSessions;
        _projectNames = {
          for (final project in allProjects) project.id: project.name,
        };
        _isLoading = false;
      });
    }
  }

  Future<void> _restoreSession(WorkSession session) async {
    final history = await _storage.loadHistory();
    final at = history.indexWhere((item) => item.id == session.id);
    if (at == -1) return;
    final createdIds = switch (session.extraFields['appCorrectionCreatedIds']) {
      final List<dynamic> values => values.whereType<String>().toSet(),
      _ => <String>{},
    };
    for (var i = 0; i < history.length; i++) {
      if (createdIds.contains(history[i].id) && !history[i].isDeleted) {
        history[i] = history[i].copyWith(isDeleted: true);
      }
    }
    final cleanExtra = {...session.extraFields}
      ..remove('appCorrectionKind')
      ..remove('appCorrectionCreatedIds');
    history[at] = session.copyWith(
      isDeleted: false,
      extraFields: cleanExtra,
    );
    await _storage.saveHistory(history);
    await _loadDeletedItems();
    if (!mounted) return;
    showAppSuccess(
      context,
      context.l10n.pick(
        he: 'רשומת הכתיבה שוחזרה',
        en: 'Writing record restored',
      ),
    );
  }

  Future<void> _restoreProject(Project project) async {
    final allProjects = await _storage.loadProjects();
    final index = allProjects.indexWhere((p) => p.id == project.id);
    if (index != -1) {
      allProjects[index] = project.copyWith(isDeleted: false);
      await _storage.saveProjects(allProjects);
      await _loadDeletedItems();

      if (mounted) {
        showAppSuccess(
            context,
            context.l10n.pick(
                he: "הפרויקט '${project.name}' שוחזר בהצלחה",
                en: "Project '${project.name}' was restored"));
      }
    }
  }

  /// Deletes the work recorded against a project that is already in the bin.
  ///
  /// It used to re-stamp the project as deleted as well, which reset the
  /// countdown beside it — so a button offering to get rid of something sooner
  /// made it stay thirty days longer. The stamp was there to win a merge
  /// against a device still holding a live copy; that is what the tombstone
  /// registers do now, and they cannot be beaten by an edit at all.
  Future<void> _deleteRecords(Project project) async {
    final confirm = await confirmAction(
      context,
      title: context.l10n.pick(he: "מחיקת הרשומות", en: "Delete records"),
      message: context.l10n.pick(
          he: "רשומות העבודה של הפרויקט יימחקו גם הן. הפרויקט עצמו כבר בסל, ויוסתר ממנו מעצמו.",
          en: "The project's work records will also be deleted. The project is already in the Recycle Bin and will be hidden from it automatically."),
      confirmLabel: context.l10n.pick(he: "מחק", en: "Delete"),
      danger: true,
    );

    if (!confirm) return;

    // Sessions belonging to the project were previously left behind,
    // referencing a project that no longer exists.
    final history = await _storage.loadHistory();
    await _storage.saveHistory(history
        .map((s) => s.projectId == project.id && !s.isDeleted
            ? s.copyWith(isDeleted: true)
            : s)
        .toList());
    await _loadDeletedItems();
  }

  Future<void> _restoreSafely(Future<void> Function() restore) async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      await restore();
      await _loadDeletedItems();
    } catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        showAppError(
            context,
            context.l10n
                .pick(he: 'השחזור נכשל: $error', en: 'Restore failed: $error'));
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  List<Widget> _ledgerItems() => [
        for (final order in _deletedOrders)
          _restoreTile(
              order.customerName, context.l10n.pick(he: 'הזמנה', en: 'Order'),
              () async {
            final all = await _storage.loadOrders();
            await _storage.saveOrders([
              for (final r in all)
                r.id == order.id ? r.copyWith(isDeleted: false) : r
            ]);
          }),
        for (final proofread in _deletedProofreads)
          _restoreTile(proofread.scope,
              context.l10n.pick(he: 'הגהה', en: 'Proofreading'), () async {
            final all = await _storage.loadProofreads();
            await _storage.saveProofreads([
              for (final r in all)
                r.id == proofread.id ? r.copyWith(isDeleted: false) : r
            ]);
          }),
        for (final expense in _deletedExpenses)
          _restoreTile(
              expense.product, context.l10n.pick(he: 'הוצאה', en: 'Expense'),
              () async {
            final all = await _storage.loadExpenses();
            await _storage.saveExpenses([
              for (final r in all)
                r.id == expense.id ? r.copyWith(isDeleted: false) : r
            ]);
          }),
        for (final payment in _deletedPayments)
          _restoreTile(payment.currency.format(payment.amount),
              context.l10n.pick(he: 'תשלום', en: 'Payment'), () async {
            final all = await _storage.loadPayments();
            await _storage.savePayments([
              for (final r in all)
                r.id == payment.id ? r.copyWith(isDeleted: false) : r
            ]);
          }),
      ];

  Widget _restoreTile(
          String title, String kind, Future<void> Function() restore) =>
      Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListTile(
            title: Text(title),
            subtitle: Text(kind),
            trailing: IconButton(
                icon: const Icon(Icons.restore_from_trash),
                tooltip: context.l10n.pick(he: 'שחזר', en: 'Restore'),
                onPressed: _restoring ? null : () => _restoreSafely(restore))),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(context.l10n.pick(he: "סל מחזור", en: "Recycle Bin"))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _deletedProjects.isEmpty &&
                  _deletedSessions.isEmpty &&
                  _ledgerItems().isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline,
                          size: 64, color: SoferTokens.of(context).inkMuted),
                      SizedBox(height: 16),
                      Text(
                          context.l10n.pick(
                              he: "סל המחזור ריק", en: "Recycle Bin is empty"),
                          style: TextStyle(
                              fontSize: 18,
                              color: SoferTokens.of(context).inkMuted)),
                      Text(
                          context.l10n.pick(
                              he:
                                  "פרויקטים, כתיבה, הזמנות, הגהות, הוצאות ותשלומים שנמחקו ב-30 הימים האחרונים יופיעו כאן",
                              en:
                                  "Projects, writing, orders, proofreading, expenses and payments deleted in the last 30 days will appear here"),
                          style: TextStyle(
                              fontSize: 12,
                              color: SoferTokens.of(context).inkMuted)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _deletedProjects.length +
                      _deletedSessions.length +
                      _ledgerItems().length,
                  itemBuilder: (context, index) {
                    final ledgerIndex = index -
                        _deletedProjects.length -
                        _deletedSessions.length;
                    if (ledgerIndex >= 0) return _ledgerItems()[ledgerIndex];
                    if (index >= _deletedProjects.length) {
                      final session =
                          _deletedSessions[index - _deletedProjects.length];
                      final projectName = _projectNames[session.projectId] ??
                          context.l10n.pick(
                              he: 'פרויקט לא ידוע', en: 'Unknown project');
                      final deletedAt =
                          session.deletedAt ?? session.lastUpdated;
                      final since = DateTime.now().difference(deletedAt).inDays;
                      final daysLeft = _binWindow.inDays - since;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: Icon(Icons.edit_note,
                              color: SoferTokens.of(context).caution),
                          title: Text(session.description),
                          subtitle: Text(context.l10n.pick(
                            he: '$projectName · רשומת כתיבה · תוסתר בעוד $daysLeft ימים',
                            en: '$projectName · writing record · hidden in $daysLeft days',
                          )),
                          trailing: IconButton(
                            icon: Icon(Icons.restore_from_trash,
                                color: SoferTokens.of(context).positive),
                            tooltip:
                                context.l10n.pick(he: 'שחזר', en: 'Restore'),
                            onPressed: _restoring
                                ? null
                                : () => _restoreSafely(
                                    () => _restoreSession(session)),
                          ),
                        ),
                      );
                    }
                    final p = _deletedProjects[index];
                    final since = DateTime.now()
                        .difference(p.deletedAt ?? p.lastUpdated)
                        .inDays;
                    final daysLeft = _binWindow.inDays - since;

                    final t = SoferTokens.of(context);

                    // The countdown is the point of this screen, so in the
                    // ruled themes it is the figure and the name is the label.
                    if (t.isRules) {
                      return Container(
                        decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: t.rule))),
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: TextStyle(
                                          fontFamily: t.numeralFamily,
                                          fontSize: 17,
                                          color: t.ink)),
                                  const SizedBox(height: 2),
                                  Text(
                                    daysLeft <= 0
                                        ? context.l10n.pick(
                                            he: "יוסתר מהסל בקרוב",
                                            en:
                                                "Will be hidden from the bin soon")
                                        : context.l10n.pick(
                                            he: "יוסתר מהסל בעוד $daysLeft ימים",
                                            en: "Will be hidden from the bin in $daysLeft days"),
                                    style: TextStyle(
                                        fontFamily: t.labelFamily,
                                        fontSize: 12,
                                        color: daysLeft <= 3
                                            ? t.danger
                                            : t.inkMuted),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                                onPressed: _restoring
                                    ? null
                                    : () => _restoreSafely(
                                        () => _restoreProject(p)),
                                child: Text(context.l10n
                                    .pick(he: "שחזר", en: "Restore"))),
                            TextButton(
                              onPressed: _restoring
                                  ? null
                                  : () =>
                                      _restoreSafely(() => _deleteRecords(p)),
                              style: TextButton.styleFrom(
                                  foregroundColor: t.danger),
                              child: Text(context.l10n.pick(
                                  he: "מחק רשומות", en: "Delete records")),
                            ),
                          ],
                        ),
                      );
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: Icon(Icons.history,
                            color: SoferTokens.of(context).caution),
                        title: Text(p.name),
                        subtitle: Text(context.l10n.pick(
                            he: "יוסתר מהסל בעוד $daysLeft ימים",
                            en: "Will be hidden from the bin in $daysLeft days")),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.restore_from_trash,
                                  color: SoferTokens.of(context).positive),
                              tooltip:
                                  context.l10n.pick(he: "שחזר", en: "Restore"),
                              onPressed: _restoring
                                  ? null
                                  : () =>
                                      _restoreSafely(() => _restoreProject(p)),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_forever,
                                  color: SoferTokens.of(context).danger),
                              tooltip: context.l10n.pick(
                                  he: "מחק גם את רשומות העבודה",
                                  en: "Also delete work records"),
                              onPressed: _restoring
                                  ? null
                                  : () =>
                                      _restoreSafely(() => _deleteRecords(p)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
