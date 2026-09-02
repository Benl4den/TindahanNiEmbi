import 'package:sqflite/sqflite.dart';

class DashboardSummary {
  const DashboardSummary({
    required this.products,
    required this.lowStock,
    required this.outOfStock,
    required this.outstandingCentavos,
    required this.stockOutToday,
    required this.inventoryValueCentavos,
    this.supplierPayableCentavos = 0,
    this.selectaLowStock = 0,
  });
  final int products,
      lowStock,
      outOfStock,
      outstandingCentavos,
      stockOutToday,
      inventoryValueCentavos;
  final int supplierPayableCentavos, selectaLowStock;
}

class DashboardRepository {
  const DashboardRepository(this.db);
  final Database db;
  Future<DashboardSummary> summary({DateTime? now}) async {
    final date = (now ?? DateTime.now()).toLocal(),
        start = DateTime(
          date.year,
          date.month,
          date.day,
        ).toUtc().toIso8601String(),
        end = DateTime(
          date.year,
          date.month,
          date.day + 1,
        ).toUtc().toIso8601String();
    final p = (await db.rawQuery(
      '''SELECT COUNT(*) products,SUM(CASE WHEN current_quantity>0 AND current_quantity<=minimum_stock_level THEN 1 ELSE 0 END) low_stock,SUM(CASE WHEN current_quantity=0 THEN 1 ELSE 0 END) out_stock,COALESCE(SUM(current_quantity*purchase_price_centavos),0) value FROM products WHERE is_archived=0''',
    )).single;
    final debt =
        (await db.rawQuery(
              'SELECT COALESCE(SUM(amount_change_centavos),0) value FROM customer_ledger_entries',
            )).single['value']!
            as int;
    final out =
        (await db.rawQuery(
              "SELECT COALESCE(SUM(-m.quantity_change),0) value FROM inventory_movements m JOIN inventory_transactions t ON t.id=m.inventory_transaction_id WHERE m.quantity_change<0 AND t.type IN('UTANG','CASH_SALE') AND t.occurred_at>=? AND t.occurred_at<?",
              [start, end],
            )).single['value']!
            as int;
    final supplier =
        (await db.rawQuery(
              '''SELECT COALESCE((SELECT SUM(amount_change_centavos) FROM consignor_ledger_entries),0)+COALESCE((SELECT SUM(payable_change_centavos) FROM consignment_allocation_reversals),0) value''',
            )).single['value']!
            as int;
    final selectaLow =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COUNT(*) FROM products p JOIN product_inventory_groups m ON m.product_id=p.id JOIN inventory_groups g ON g.id=m.inventory_group_id WHERE g.code='SELECTA' AND m.archived_at IS NULL AND p.is_archived=0 AND p.current_quantity<=p.minimum_stock_level''',
          ),
        ) ??
        0;
    return DashboardSummary(
      products: p['products']! as int,
      lowStock: (p['low_stock'] as int?) ?? 0,
      outOfStock: (p['out_stock'] as int?) ?? 0,
      outstandingCentavos: debt,
      stockOutToday: out,
      inventoryValueCentavos: p['value']! as int,
      supplierPayableCentavos: supplier,
      selectaLowStock: selectaLow,
    );
  }
}
