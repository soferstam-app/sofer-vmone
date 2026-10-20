import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/merge_service.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';

Order sampleOrder({DateTime? updated}) => Order(
      id: 'order-1',
      customerName: 'ישראל ישראלי',
      phone: '050-1234567',
      orderedAt: DateTime(2026, 8, 1),
      dueDate: DateTime(2026, 9, 15),
      requirements: 'כתב מהודר',
      price: 3200,
      items: const [
        OrderItem(
          id: 'item-1',
          type: ProjectType.mezuza,
          quantity: 4,
          suppliedQuantity: 2,
        ),
        OrderItem(
          id: 'item-2',
          type: ProjectType.megillah,
          quantity: 1,
        ),
      ],
      status: OrderStatus.partial,
      lastUpdated: updated ?? DateTime(2026, 8, 2),
    );

void main() {
  tearDown(() => StorageService.demoStore = null);

  test('mixed order survives JSON round trip with partial supply', () {
    final original = sampleOrder();
    final restored = Order.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );

    expect(restored.customerName, original.customerName);
    expect(restored.items.map((item) => item.type),
        [ProjectType.mezuza, ProjectType.megillah]);
    expect(restored.totalQuantity, 5);
    expect(restored.suppliedQuantity, 2);
    expect(restored.isFullySupplied, isFalse);
    expect(restored.status, OrderStatus.partial);
  });

  test('order item quantities are bounded when edited', () {
    const item = OrderItem(
      id: 'item',
      type: ProjectType.sefer,
      quantity: 2,
      suppliedQuantity: 1,
    );
    expect(
        item.copyWith(quantity: 4, suppliedQuantity: 20).suppliedQuantity, 4);
    expect(
        item.copyWith(quantity: 1, suppliedQuantity: -5).suppliedQuantity, 0);
  });

  test('orders merge with the same tombstone rules as other records', () {
    final local = sampleOrder();
    final incoming = local.copyWith(
      requirements: 'עודכן',
      isDeleted: true,
    );
    final outcome = MergeService.mergeBackup(
      localProjects: const [],
      localHistory: const [],
      localExpenses: const [],
      incomingProjects: const [],
      incomingHistory: const [],
      incomingExpenses: const [],
      localOrders: [local],
      incomingOrders: [incoming],
    );

    expect(outcome.orders.single.requirements, 'עודכן');
    expect(outcome.orders.single.isDeleted, isTrue);
    expect(outcome.orderStats.updated, 1);
  });

  test('orders are stored independently of projects', () async {
    StorageService.demoStore = MemoryStore({});
    final storage = StorageService();
    final order = sampleOrder();

    await storage.saveOrders([order]);

    expect((await storage.loadOrders()).single.id, order.id);
    expect((await storage.loadProjects()), isEmpty);
    expect((await storage.exportAll())['orders'], hasLength(1));
  });
}
