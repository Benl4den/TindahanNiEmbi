import 'package:sqflite/sqflite.dart';

import '../models/utang_draft.dart';
import 'consignment_allocation.dart';
import '../services/app_refresh_controller.dart';

class CashSaleRepository {
  const CashSaleRepository(this.db, {this.actorRole});
  final Database db;
  final String? actorRole;
  Future<int> save(List<UtangItemDraft> items) async =>
      (await saveWithResult(items)).id;

  Future<CashSaleResult> saveWithResult(List<UtangItemDraft> items) async {
    return AppRefreshController.instance.after(
      db.transaction((tx) => saveWithExecutor(tx, items)),
    );
  }

  Future<CashSaleResult> saveWithExecutor(
    DatabaseExecutor tx,
    List<UtangItemDraft> items,
  ) async {
    if (items.isEmpty || items.any((i) => i.effectiveQuantityValue <= 0)) {
      throw ArgumentError('Items required');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final loaded =
        <
          ({
            UtangItemDraft item,
            Map<String, Object?> row,
            int price,
            int baseQuantity,
            int line,
          })
        >[];
    final requiredByProduct = <int, int>{};
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
      if (i.quantityScale <= 0 || i.baseQuantityPerUnit <= 0) {
        throw ArgumentError('Invalid selling quantity.');
      }
      if (i.sellingOptionId != null) {
        final option = await tx.query(
          'product_selling_options',
          where: 'id=? AND product_id=? AND is_archived=0',
          whereArgs: [i.sellingOptionId, i.productId],
          limit: 1,
        );
        if (option.isEmpty) {
          throw StateError(
            'The selected selling option is no longer available.',
          );
        }
      }
      final base = i.totalBaseQuantity;
      final needed = (requiredByProduct[i.productId] ?? 0) + base;
      requiredByProduct[i.productId] = needed;
      if (stock < needed) {
        throw StateError(
          'Not enough ${i.baseUnitLabel}. Required: $needed; available: $stock.',
        );
      }
      final price =
          i.unitPriceCentavos ?? row['selling_price_centavos']! as int;
      final line = i.lineTotalCentavos(price);
      total += line;
      loaded.add((
        item: i,
        row: row,
        price: price,
        baseQuantity: base,
        line: line,
      ));
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
    final runningStock = <int, int>{};
    for (final x in loaded) {
      final price = x.price,
          before =
              runningStock[x.item.productId] ??
              x.row['current_quantity']! as int,
          line = x.line;
      verified += line;
      count += x.item.quantityScale == 1 ? x.item.effectiveQuantityValue : 1;
      final saleItemId = await tx.insert('cash_sale_items', {
        'cash_sale_id': sale,
        'product_id': x.item.productId,
        'product_name_snapshot': x.row['name'],
        'unit_price_centavos': x.item.quantityScale == 1 ? price : line,
        'quantity': x.item.quantityScale == 1
            ? x.item.effectiveQuantityValue
            : 1,
        'line_total_centavos': line,
        'selling_option_id': x.item.sellingOptionId,
        'selling_option_name_snapshot': x.item.sellingOptionName ?? 'Piece',
        'base_quantity_per_unit': x.item.baseQuantityPerUnit,
        'selling_quantity_value': x.item.effectiveQuantityValue,
        'selling_quantity_scale': x.item.quantityScale,
        'base_unit_snapshot': x.item.baseUnitLabel,
        'total_base_quantity': x.baseQuantity,
        'selling_unit_price_centavos': price,
        'created_at': now,
      });
      await ConsignmentAllocation.postSale(
        tx,
        productId: x.item.productId,
        quantity: x.baseQuantity,
        sellingPriceCentavos: x.baseQuantity == 0
            ? 0
            : (line + x.baseQuantity ~/ 2) ~/ x.baseQuantity,
        totalSaleCentavos: line,
        cashSaleItemId: saleItemId,
        occurredAt: now,
      );
      await tx.insert('inventory_movements', {
        'inventory_transaction_id': inv,
        'product_id': x.item.productId,
        'quantity_change': -x.baseQuantity,
        'quantity_before': before,
        'quantity_after': before - x.baseQuantity,
        'created_at': now,
      });
      runningStock[x.item.productId] = before - x.baseQuantity;
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
      status: 'POSTED',
    );
  }

  Future<CashSaleResult?> latest() async {
    final rows = await db.rawQuery(
      "SELECT s.*,COALESCE(SUM(i.quantity),0) item_count FROM cash_sales s LEFT JOIN cash_sale_items i ON i.cash_sale_id=s.id WHERE s.status='POSTED' GROUP BY s.id ORDER BY s.occurred_at DESC,s.id DESC LIMIT 1",
    );
    return rows.isEmpty ? null : CashSaleResult.fromMap(rows.single);
  }

  Future<SalesHistoryEntry?> latestTransaction() async {
    final rows = await history();
    final posted = rows.where((x) => x.status == 'POSTED');
    return posted.isEmpty ? null : posted.first;
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

  Future<List<SalesHistoryEntry>> history({String type = 'ALL'}) async {
    final rows = await db.rawQuery(
      '''
      SELECT * FROM (SELECT s.id,s.reference,'CASH' sale_type,NULL customer_name,s.occurred_at,
        s.total_centavos,COALESCE(SUM(i.quantity),0) item_count,s.status,
        (SELECT replacement_entity_id FROM transaction_corrections c WHERE c.entity_type='CASH_SALE' AND c.original_entity_id=s.id) corrected_by_id,
        (SELECT original_entity_id FROM transaction_corrections c WHERE c.entity_type='CASH_SALE' AND c.replacement_entity_id=s.id) correction_of_id
      FROM cash_sales s LEFT JOIN cash_sale_items i ON i.cash_sale_id=s.id
      WHERE ? IN ('ALL','CASH') GROUP BY s.id
      UNION ALL
      SELECT u.id,u.reference,'UTANG',c.full_name,u.occurred_at,
        u.total_centavos,COALESCE(SUM(i.quantity),0),u.status,
        (SELECT replacement_entity_id FROM transaction_corrections tc WHERE tc.entity_type='UTANG' AND tc.original_entity_id=u.id),
        (SELECT original_entity_id FROM transaction_corrections tc WHERE tc.entity_type='UTANG' AND tc.replacement_entity_id=u.id)
      FROM utang_transactions u JOIN customers c ON c.id=u.customer_id
      LEFT JOIN utang_transaction_items i ON i.utang_transaction_id=u.id
      WHERE ? IN ('ALL','UTANG') GROUP BY u.id)
      ORDER BY occurred_at DESC,id DESC LIMIT 100
    ''',
      [type, type],
    );
    return rows.map(SalesHistoryEntry.fromMap).toList();
  }

  Future<List<Map<String, Object?>>> utangItems(int id) => db.query(
    'utang_transaction_items',
    where: 'utang_transaction_id=?',
    whereArgs: [id],
    orderBy: 'id',
  );
}

class SalesHistoryEntry {
  const SalesHistoryEntry({
    required this.id,
    required this.reference,
    required this.type,
    required this.occurredAt,
    required this.totalCentavos,
    required this.itemCount,
    required this.status,
    this.customerName,
    this.correctedById,
    this.correctionOfId,
  });
  final int id, totalCentavos, itemCount;
  final String reference, type, status;
  final String? customerName;
  final int? correctedById, correctionOfId;
  final DateTime occurredAt;
  bool get isUtang => type == 'UTANG';
  factory SalesHistoryEntry.fromMap(Map<String, Object?> x) =>
      SalesHistoryEntry(
        id: x['id']! as int,
        reference: x['reference']! as String,
        type: x['sale_type']! as String,
        customerName: x['customer_name'] as String?,
        occurredAt: DateTime.parse(x['occurred_at']! as String),
        totalCentavos: x['total_centavos']! as int,
        itemCount: x['item_count']! as int,
        status: x['status']! as String,
        correctedById: x['corrected_by_id'] as int?,
        correctionOfId: x['correction_of_id'] as int?,
      );
}

class CashSaleResult {
  const CashSaleResult({
    required this.id,
    required this.reference,
    required this.totalCentavos,
    required this.occurredAt,
    required this.itemCount,
    required this.status,
  });
  final int id, totalCentavos, itemCount;
  final String reference;
  final String status;
  final DateTime occurredAt;
  factory CashSaleResult.fromMap(Map<String, Object?> x) => CashSaleResult(
    id: x['id']! as int,
    reference: x['reference']! as String,
    totalCentavos: x['total_centavos']! as int,
    occurredAt: DateTime.parse(x['occurred_at']! as String),
    itemCount: x['item_count']! as int,
    status: x['status']! as String,
  );
}

class CashSaleDetails {
  const CashSaleDetails({required this.sale, required this.items});
  final CashSaleResult sale;
  final List<Map<String, Object?>> items;
}
