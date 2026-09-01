import 'package:sqflite/sqflite.dart';

import '../models/utang_draft.dart';

class CashSaleRepository {
  const CashSaleRepository(this.db, {this.actorRole});
  final Database db;
  final String? actorRole;
  Future<int> save(List<UtangItemDraft> items) async =>
      (await saveWithResult(items)).id;

  Future<CashSaleResult> saveWithResult(List<UtangItemDraft> items) async {
    if (items.isEmpty || items.any((i) => i.quantity <= 0)) {
      throw ArgumentError('Items required');
    }
    return db.transaction((tx) async {
      final now = DateTime.now().toUtc().toIso8601String();
      final loaded = <({UtangItemDraft item, Map<String, Object?> row})>[];
      var total = 0;
      for (final i in items) {
        final rows = await tx.query(
          'products',
          where: 'id=? AND is_archived=0',
          whereArgs: [i.productId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Product unavailable');
        final row = rows.single, stock = row['current_quantity']! as int;
        if (stock < i.quantity) throw StateError('Insufficient stock');
        total += (row['selling_price_centavos']! as int) * i.quantity;
        loaded.add((item: i, row: row));
      }
      final sale = await tx.insert('cash_sales', {
        'total_centavos': total,
        'status': 'POSTED',
        'occurred_at': now,
        'created_at': now,
      });
      final reference = 'SALE-${sale.toString().padLeft(6, '0')}';
      await tx.update(
        'cash_sales',
        {'reference': reference},
        where: 'id=?',
        whereArgs: [sale],
      );
      final inv = await tx.insert('inventory_transactions', {
        'type': 'CASH_SALE',
        'reference_number': reference,
        'occurred_at': now,
        'created_at': now,
      });
      var verified = 0, count = 0;
      for (final x in loaded) {
        final price = x.row['selling_price_centavos']! as int,
            before = x.row['current_quantity']! as int,
            line = price * x.item.quantity;
        verified += line;
        count += x.item.quantity;
        await tx.insert('cash_sale_items', {
          'cash_sale_id': sale,
          'product_id': x.item.productId,
          'product_name_snapshot': x.row['name'],
          'unit_price_centavos': price,
          'quantity': x.item.quantity,
          'line_total_centavos': line,
          'created_at': now,
        });
        await tx.insert('inventory_movements', {
          'inventory_transaction_id': inv,
          'product_id': x.item.productId,
          'quantity_change': -x.item.quantity,
          'quantity_before': before,
          'quantity_after': before - x.item.quantity,
          'created_at': now,
        });
      }
      if (verified != total) throw StateError('Total mismatch');
      await tx.insert('activity_logs', {
        'event_type': 'SALES_CASH_SALE',
        'description':
            'Cash sale $reference completed — ₱${(total / 100).toStringAsFixed(2)}',
        'actor_role': actorRole,
        'related_entity_type': 'CASH_SALE',
        'related_entity_id': sale,
        'created_at': now,
      });
      return CashSaleResult(
        id: sale,
        reference: reference,
        totalCentavos: total,
        occurredAt: DateTime.parse(now),
        itemCount: count,
      );
    });
  }

  Future<CashSaleResult?> latest() async {
    final rows = await db.rawQuery(
      "SELECT s.*,COALESCE(SUM(i.quantity),0) item_count FROM cash_sales s LEFT JOIN cash_sale_items i ON i.cash_sale_id=s.id WHERE s.status='POSTED' GROUP BY s.id ORDER BY s.occurred_at DESC,s.id DESC LIMIT 1",
    );
    return rows.isEmpty ? null : CashSaleResult.fromMap(rows.single);
  }

  Future<int> todayTotal() async {
    final now = DateTime.now(),
        start = DateTime(
          now.year,
          now.month,
          now.day,
        ).toUtc().toIso8601String(),
        end = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 1)).toUtc().toIso8601String();
    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(total_centavos),0) total FROM cash_sales WHERE status='POSTED' AND occurred_at>=? AND occurred_at<?",
      [start, end],
    );
    return rows.single['total']! as int;
  }

  Future<CashSaleDetails> details(int id) async {
    final rows = await db.query(
      'cash_sales',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Sale not found.');
    final items = await db.query(
      'cash_sale_items',
      where: 'cash_sale_id=?',
      whereArgs: [id],
      orderBy: 'id',
    );
    final count = items.fold<int>(0, (n, x) => n + (x['quantity']! as int));
    return CashSaleDetails(
      sale: CashSaleResult.fromMap({...rows.single, 'item_count': count}),
      items: items,
    );
  }
}

class CashSaleResult {
  const CashSaleResult({
    required this.id,
    required this.reference,
    required this.totalCentavos,
    required this.occurredAt,
    required this.itemCount,
  });
  final int id, totalCentavos, itemCount;
  final String reference;
  final DateTime occurredAt;
  factory CashSaleResult.fromMap(Map<String, Object?> x) => CashSaleResult(
    id: x['id']! as int,
    reference: x['reference']! as String,
    totalCentavos: x['total_centavos']! as int,
    occurredAt: DateTime.parse(x['occurred_at']! as String),
    itemCount: x['item_count']! as int,
  );
}

class CashSaleDetails {
  const CashSaleDetails({required this.sale, required this.items});
  final CashSaleResult sale;
  final List<Map<String, Object?>> items;
}
