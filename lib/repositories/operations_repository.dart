import 'package:sqflite/sqflite.dart';

import '../models/product.dart';

class RestockItem {
  const RestockItem(this.product, this.isConsignment, this.isSelecta);
  final Product product;
  final bool isConsignment, isSelecta;
  int get suggested =>
      (product.minimumStockLevel - product.currentQuantity).clamp(0, 1 << 31);
}

class DailyClosingSummary {
  const DailyClosingSummary({
    required this.cashSales,
    required this.cashSaleCount,
    required this.newUtang,
    required this.payments,
    required this.consignmentSales,
    required this.supplierPayable,
    required this.consignmentMargin,
    required this.transactionCount,
    required this.lowStock,
    required this.outOfStock,
    required this.topProducts,
  });
  final int cashSales,
      cashSaleCount,
      newUtang,
      payments,
      consignmentSales,
      supplierPayable,
      consignmentMargin,
      transactionCount,
      lowStock,
      outOfStock;
  final List<Map<String, Object?>> topProducts;
  int get recordedCashIn => cashSales + payments;
}

class OperationsRepository {
  const OperationsRepository(this.db);
  final Database db;
  Future<List<RestockItem>> restock({String filter = 'ALL'}) async {
    final rows = await db.rawQuery(
      '''SELECT p.*,EXISTS(SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id WHERE m.product_id=p.id AND m.archived_at IS NULL AND g.code='CONSIGNMENT') consigned,EXISTS(SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id WHERE m.product_id=p.id AND m.archived_at IS NULL AND g.code='SELECTA') selecta FROM products p WHERE p.is_archived=0 ORDER BY p.name COLLATE NOCASE''',
    );
    final result = rows
        .map(
          (x) => RestockItem(
            Product.fromMap(x),
            x['consigned'] == 1,
            x['selecta'] == 1,
          ),
        )
        .where(
          (x) => switch (filter) {
            'LOW' =>
              x.product.currentQuantity > 0 &&
                  x.product.currentQuantity <= x.product.minimumStockLevel,
            'OUT' => x.product.currentQuantity == 0,
            'SELECTA' => x.isSelecta,
            _ => true,
          },
        )
        .toList();
    result.sort((a, b) {
      final urgency = b.suggested.compareTo(a.suggested);
      return urgency != 0
          ? urgency
          : a.product.name.toLowerCase().compareTo(
              b.product.name.toLowerCase(),
            );
    });
    return result;
  }

  Future<DailyClosingSummary> daily(DateTime date) async {
    final local = DateTime(date.year, date.month, date.day),
        start = local.toUtc().toIso8601String(),
        end = local.add(const Duration(days: 1)).toUtc().toIso8601String();
    Future<Map<String, Object?>> one(String sql) =>
        db.rawQuery(sql, [start, end]).then((x) => x.single);
    final cash = await one(
      "SELECT COALESCE(SUM(total_centavos),0) total,COUNT(*) count FROM cash_sales WHERE status='POSTED' AND occurred_at>=? AND occurred_at<?",
    );
    final utang = await one(
      "SELECT COALESCE(SUM(total_centavos),0) total,COUNT(*) count FROM utang_transactions WHERE status='POSTED' AND occurred_at>=? AND occurred_at<?",
    );
    final pay = await one(
      "SELECT COALESCE(SUM(amount_centavos),0) total,COUNT(*) count FROM utang_payments WHERE status='POSTED' AND paid_at>=? AND paid_at<?",
    );
    final con = await one(
      '''SELECT COALESCE(SUM(a.selling_price_centavos*a.quantity),0) sales,COALESCE(SUM(a.payable_centavos),0) payable,COALESCE(SUM(a.margin_centavos),0) margin,COUNT(DISTINCT COALESCE(a.cash_sale_item_id,-a.utang_item_id)) count FROM consignment_allocations a WHERE a.occurred_at>=? AND a.occurred_at<? AND NOT EXISTS(SELECT 1 FROM consignment_allocation_reversals r WHERE r.allocation_id=a.id)''',
    );
    final stock = (await db.rawQuery(
      '''SELECT SUM(CASE WHEN current_quantity>0 AND current_quantity<=minimum_stock_level THEN 1 ELSE 0 END) low,SUM(CASE WHEN current_quantity=0 THEN 1 ELSE 0 END) out FROM products WHERE is_archived=0''',
    )).single;
    final top = await db.rawQuery(
      '''SELECT name,SUM(quantity) quantity FROM(SELECT i.product_name_snapshot name,i.quantity FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id WHERE s.status='POSTED' AND s.occurred_at>=? AND s.occurred_at<? UNION ALL SELECT i.product_name_snapshot,i.quantity FROM utang_transaction_items i JOIN utang_transactions u ON u.id=i.utang_transaction_id WHERE u.status='POSTED' AND u.occurred_at>=? AND u.occurred_at<?) GROUP BY name ORDER BY quantity DESC LIMIT 5''',
      [start, end, start, end],
    );
    return DailyClosingSummary(
      cashSales: cash['total']! as int,
      cashSaleCount: cash['count']! as int,
      newUtang: utang['total']! as int,
      payments: pay['total']! as int,
      consignmentSales: con['sales']! as int,
      supplierPayable: con['payable']! as int,
      consignmentMargin: con['margin']! as int,
      transactionCount:
          (cash['count']! as int) +
          (utang['count']! as int) +
          (pay['count']! as int),
      lowStock: (stock['low'] as int?) ?? 0,
      outOfStock: (stock['out'] as int?) ?? 0,
      topProducts: top,
    );
  }

  Future<List<DateTime>> closingDates() async {
    final rows = await db.rawQuery('''
      SELECT occurred_at stamp FROM cash_sales WHERE status='POSTED'
      UNION ALL SELECT occurred_at FROM utang_transactions WHERE status='POSTED'
      UNION ALL SELECT paid_at FROM utang_payments WHERE status='POSTED'
      ORDER BY stamp DESC''');
    final days = <String, DateTime>{};
    for (final row in rows) {
      final local = DateTime.parse(row['stamp']! as String).toLocal();
      final day = DateTime(local.year, local.month, local.day);
      days.putIfAbsent('${day.year}-${day.month}-${day.day}', () => day);
      if (days.length == 90) break;
    }
    return days.values.toList();
  }
}
