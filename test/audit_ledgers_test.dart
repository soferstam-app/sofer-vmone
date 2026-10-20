import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/expenses_screen.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/orders_screen.dart';
import 'package:sofer_vmone/project/payment_sheet.dart';
import 'package:sofer_vmone/proofread/proofread_screen.dart';
import 'package:sofer_vmone/recycle_bin_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';
import 'package:sofer_vmone/widgets/sofer_widgets.dart';

import 'support/fault_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final p = Project(
      id: 'p',
      name: 'ספר בדיקה',
      type: ProjectType.sefer,
      price: 420,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0,
      totalPages: 245,
      linesPerPage: 42);
  final order = Order(
      id: 'o',
      customerName: 'לקוח בדיקה',
      orderedAt: DateTime(2026, 1, 1),
      dueDate: DateTime.now().subtract(const Duration(days: 1)),
      price: 100,
      status: OrderStatus.cancelled,
      lastUpdated: DateTime(2026, 10, 1),
      items: const [
        OrderItem(
            id: 'item',
            type: ProjectType.mezuza,
            quantity: 4,
            suppliedQuantity: 2,
            projectId: 'missing')
      ]);
  Widget host(Widget child, {AppTheme theme = AppTheme.modern}) => MaterialApp(
      theme: AppThemeBuilder.build(theme),
      home: Scaffold(
          body:
              Directionality(textDirection: TextDirection.rtl, child: child)));
  Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label);
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  setUp(() {
    StorageService.demoStore = MemoryStore({});
    StorageService.onChanged = null;
  });
  tearDown(() {
    StorageService.demoStore = null;
    StorageService.onChanged = null;
  });

  testWidgets(
      'C5 all deleted ledgers can be restored without reviving expired rows',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final proofread = Proofread(
            id: 'r',
            projectId: p.id,
            scope: 'הגהה בדיקה',
            currency: Currency.ils)
        .copyWith(isDeleted: true);
    final expense =
        Expense(id: 'e', product: 'דיו בדיקה', date: DateTime.now(), amount: 50)
            .copyWith(isDeleted: true);
    final payment = Payment(
            id: 'pay',
            projectId: p.id,
            amount: 70,
            currency: Currency.ils,
            receivedAt: DateTime.now())
        .copyWith(isDeleted: true);
    final deletedOrder = order.copyWith(isDeleted: true);
    final expired = Order.fromJson({
      ...deletedOrder.toJson(),
      'id': 'expired',
      'customerName': 'מחיקה ישנה',
      'deletedAt':
          DateTime.now().subtract(const Duration(days: 31)).toIso8601String()
    });
    StorageService.demoStore = MemoryStore({
      'orders': jsonEncode([deletedOrder.toJson(), expired.toJson()]),
      'proofreads': jsonEncode([proofread.toJson()]),
      'expenses': jsonEncode([expense.toJson()]),
      'payments': jsonEncode([payment.toJson()]),
    });
    await tester.pumpWidget(host(const RecycleBinScreen()));
    await tester.pumpAndSettle();
    expect(find.text('מחיקה ישנה'), findsNothing);
    expect(find.byIcon(Icons.restore_from_trash), findsNWidgets(4));
    for (var i = 0; i < 4; i++) {
      await tap(tester, find.byIcon(Icons.restore_from_trash).first);
    }
    final storage = StorageService();
    expect(
        (await storage.loadOrders()).singleWhere((r) => r.id == 'o').isDeleted,
        isFalse);
    expect(
        (await storage.loadOrders())
            .singleWhere((r) => r.id == 'expired')
            .isDeleted,
        isTrue);
    expect((await storage.loadProofreads()).single.isDeleted, isFalse);
    expect((await storage.loadExpenses()).single.isDeleted, isFalse);
    expect((await storage.loadPayments()).single.isDeleted, isFalse);
    expect(find.text('סל המחזור ריק'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C5 a failed order restore keeps the row and retries',
      (tester) async {
    final deleted = order.copyWith(isDeleted: true);
    final store = FaultStore({
      'orders': jsonEncode([deleted.toJson()])
    });
    StorageService.demoStore = store;
    await tester.pumpWidget(host(const RecycleBinScreen()));
    await tester.pumpAndSettle();
    store.arm('orders');
    await tap(tester, find.byIcon(Icons.restore_from_trash));
    expect((await StorageService().loadOrders()).single.isDeleted, isTrue);
    expect(find.text('לקוח בדיקה'), findsOneWidget);
    await tap(tester, find.byIcon(Icons.restore_from_trash));
    expect((await StorageService().loadOrders()).single.isDeleted, isFalse);
  });

  testWidgets(
      'C6-C11 cancelled order edits a missing project without losing cancellation',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    StorageService.demoStore = MemoryStore({
      'orders': jsonEncode([order.toJson()])
    });
    await tester.pumpWidget(host(const OrdersScreen()));
    await tester.pumpAndSettle();
    expect(find.text('בוטלה'), findsOneWidget);
    expect(
        tester
            .widget<SoferStatRow>(find.byWidgetPredicate(
                (w) => w is SoferStatRow && w.label == 'פתוחות'))
            .value,
        '0');
    await tap(tester, find.text('לקוח בדיקה'));
    expect(find.text('פרויקט שנמחק או אינו זמין'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tap(tester, find.text('שמור'));
    final stored = (await StorageService().loadOrders()).single;
    expect(stored.status, OrderStatus.cancelled);
    expect(stored.items.single.projectId, 'missing');
    expect(stored.suppliedQuantity, 2);
    await tap(tester, find.byType(PopupMenuButton<String>));
    await tap(tester, find.text('החזר לפעילות'));
    expect((await StorageService().loadOrders()).single.status,
        OrderStatus.partial);
    await tap(tester, find.byType(PopupMenuButton<String>));
    await tap(tester, find.text('בטל הזמנה'));
    expect((await StorageService().loadOrders()).single.status,
        OrderStatus.cancelled);
    expect((await StorageService().loadOrders()).single.isDeleted, isFalse);
  });

  testWidgets('C9 expense editor retains draft after add failure and retries',
      (tester) async {
    final store = FaultStore({});
    StorageService.demoStore = store;
    await tester.pumpWidget(host(ExpensesScreen(projects: [p])));
    await tester.pumpAndSettle();
    await tap(tester, find.byIcon(Icons.add).first);
    await tester.enterText(field('מוצר (או הזן ידנית)'), 'דיו חדש');
    await tester.enterText(field('סכום (₪)'), '120');
    store.arm('expenses');
    await tap(tester, find.text('הוסף').last);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect((await StorageService().loadExpenses()), isEmpty);
    expect(
        tester.widget<TextField>(field('מוצר (או הזן ידנית)')).controller!.text,
        'דיו חדש');
    await tap(tester, find.text('הוסף').last);
    expect(find.byType(AlertDialog), findsNothing);
    expect((await StorageService().loadExpenses()).single.amount, 120);
  });

  testWidgets(
      'C9 proofreading editor retains draft after add failure and retries',
      (tester) async {
    final store = FaultStore({});
    StorageService.demoStore = store;
    await tester.pumpWidget(host(ProofreadScreen(projects: [p])));
    await tester.pumpAndSettle();
    await tap(tester, find.byIcon(Icons.add));
    await tester.enterText(field('מה נשלח'), 'עמודים 1–5');
    store.arm('proofreads');
    await tap(tester, find.text('שמור'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect((await StorageService().loadProofreads()), isEmpty);
    expect(tester.widget<TextField>(field('מה נשלח')).controller!.text,
        'עמודים 1–5');
    await tap(tester, find.text('שמור'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        (await StorageService().loadProofreads()).single.scope, 'עמודים 1–5');
  });

  testWidgets('C9 payment editor retains draft after add failure and retries',
      (tester) async {
    final store = FaultStore({});
    StorageService.demoStore = store;
    await tester.pumpWidget(host(Builder(
        builder: (ctx) => TextButton(
            onPressed: () => showPaymentSheet(
                context: ctx, project: p, history: [], useGregorianDates: true),
            child: const Text('תשלומים')))));
    await tap(tester, find.text('תשלומים'));
    await tap(tester, find.text('רישום תשלום'));
    await tester.enterText(field('סכום (₪)'), '200');
    store.arm('payments');
    await tap(tester, find.text('שמור'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect((await StorageService().loadPayments()), isEmpty);
    expect(tester.widget<TextField>(field('סכום (₪)')).controller!.text, '200');
    await tap(tester, find.text('שמור'));
    expect(find.byType(AlertDialog), findsNothing);
    expect((await StorageService().loadPayments()).single.amount, 200);
  });
  for (final kind in ['expenses', 'proofreads', 'payments']) {
    testWidgets(
        'C9 $kind edit and delete failures preserve the durable record and retry',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final expense = Expense(
          id: 'e', product: 'דיו בדיקה', date: DateTime.now(), amount: 50);
      final proofread = Proofread(
          id: 'r',
          projectId: p.id,
          scope: 'הגהה בדיקה',
          currency: Currency.ils,
          cost: 50);
      final payment = Payment(
          id: 'pay',
          projectId: p.id,
          amount: 50,
          currency: Currency.ils,
          receivedAt: DateTime.now());
      final store = FaultStore({
        kind: jsonEncode([
          if (kind == 'expenses')
            expense.toJson()
          else if (kind == 'proofreads')
            proofread.toJson()
          else
            payment.toJson(),
        ])
      });
      StorageService.demoStore = store;
      final storage = StorageService();
      Future<double> amount() async => switch (kind) {
            'expenses' => (await storage.loadExpenses()).single.amount,
            'proofreads' => (await storage.loadProofreads()).single.cost,
            _ => (await storage.loadPayments()).single.amount,
          };
      Future<bool> deleted() async => switch (kind) {
            'expenses' => (await storage.loadExpenses()).single.isDeleted,
            'proofreads' => (await storage.loadProofreads()).single.isDeleted,
            _ => (await storage.loadPayments()).single.isDeleted,
          };
      Future<void> open() async {
        if (kind == 'expenses') {
          await tap(tester, find.byIcon(Icons.edit));
        } else if (kind == 'proofreads') {
          await tap(tester, find.byIcon(Icons.edit_outlined));
        } else {
          await tap(
              tester,
              find
                  .ancestor(
                      of: find.text(p.currency.format(await amount())),
                      matching: find.byType(ListTile))
                  .first);
        }
      }

      if (kind == 'expenses') {
        await tester.pumpWidget(host(ExpensesScreen(projects: [p])));
      } else if (kind == 'proofreads') {
        await tester.pumpWidget(host(ProofreadScreen(projects: [p])));
      } else {
        await tester.pumpWidget(host(Builder(
            builder: (ctx) => TextButton(
                onPressed: () => showPaymentSheet(
                    context: ctx,
                    project: p,
                    history: [],
                    useGregorianDates: true),
                child: const Text('פתח תשלומים')))));
        await tap(tester, find.text('פתח תשלומים'));
      }
      await tester.pumpAndSettle();
      await open();
      final priceField =
          kind == 'proofreads' ? field('עלות (₪)') : field('סכום (₪)');
      await tester.enterText(priceField, '130');
      store.arm(kind);
      await tap(tester, find.text('שמור'));
      expect(await amount(), 50);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.widget<TextField>(priceField).controller!.text, '130');
      await tap(tester, find.text('שמור'));
      expect(await amount(), 130);
      expect(find.byType(AlertDialog), findsNothing);
      await open();
      store.arm(kind);
      await tap(tester, find.text('מחק'));
      if (kind != 'expenses') await tap(tester, find.text('מחק').last);
      expect(await deleted(), isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tap(tester, find.text('מחק'));
      if (kind != 'expenses') await tap(tester, find.text('מחק').last);
      expect(await deleted(), isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
