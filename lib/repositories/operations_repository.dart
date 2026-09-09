import 'package:sqflite/sqflite.dart';

import '../models/product.dart';

class RestockItem {
  const RestockItem(
    this.product,
    this.isConsignment,
    this.isSelecta, {
    this.consignorId,
    this.consignorName,
  });
  final Product product;
  final bool isConsignment, isSelecta;
  final int? consignorId;
  final String? consignorName;
  int get suggested =>
      (product.minimumStockLevel - product.currentQuantity).clamp(0, 1 << 31);
}

class DailyClosingSummary {
  const DailyClosingSummary({
    required this.cashSales,
    required this.gcashSales,
    required this.cashSaleCount,
    required this.gcashSaleCount,
    required this.newUtang,
    required this.payments,
    required this.cashPayments,
    required this.gcashPayments,
    required this.operatingExpenses,
    required this.cashExpenses,
    required this.gcashExpenses,
    required this.cashRemittances,
    required this.gcashRemittances,
    required this.gcashOpeningBalance,
    required this.gcashMoneyIn,
    required this.gcashMoneyOut,
    required this.cashInServiceCount,
    required this.cashOutServiceCount,
    required this.cashInServicePrincipal,
    required this.cashOutServicePrincipal,
    required this.cashInServiceFees,
    required this.cashOutServiceFees,
    required this.gcashServicePhysicalCashChange,
    required this.gcashServiceWalletChange,
    required this.consignmentSales,
    required this.supplierPayable,
    required this.consignmentMargin,
    required this.transactionCount,
    required this.lowStock,
    required this.outOfStock,
    required this.topProducts,
  });
  final int cashSales,
      gcashSales,
      cashSaleCount,
      gcashSaleCount,
      newUtang,
      payments,
      cashPayments,
      gcashPayments,
      operatingExpenses,
      cashExpenses,
      gcashExpenses,
      cashRemittances,
      gcashRemittances,
      gcashOpeningBalance,
      gcashMoneyIn,
      gcashMoneyOut,
      cashInServiceCount,
      cashOutServiceCount,
      cashInServicePrincipal,
      cashOutServicePrincipal,
      cashInServiceFees,
      cashOutServiceFees,
      gcashServicePhysicalCashChange,
      gcashServiceWalletChange,
      consignmentSales,
      supplierPayable,
      consignmentMargin,
      transactionCount,
      lowStock,
      outOfStock;
  final List<Map<String, Object?>> topProducts;
  int get totalSales => cashSales + gcashSales;
  int get serviceFeeIncome => cashInServiceFees + cashOutServiceFees;
  int get recordedCashIn =>
      cashSales + cashPayments + gcashServicePhysicalCashChange;
  int get netRecordedCash => recordedCashIn - cashExpenses - cashRemittances;
  int get gcashEndingBalance =>
      gcashOpeningBalance + gcashMoneyIn - gcashMoneyOut;
}

class OperationsRepository {
  const OperationsRepository(this.db);
  final Database db;
  Future<List<RestockItem>> restock({String filter = 'NEEDS'}) async {
    final rows = await db.rawQuery('''SELECT p.*,
      EXISTS(SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id WHERE m.product_id=p.id AND m.archived_at IS NULL AND g.code='CONSIGNMENT') consigned,
      EXISTS(SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id WHERE m.product_id=p.id AND m.archived_at IS NULL AND g.code='SELECTA') selecta,
      (SELECT b.consignor_id FROM consignment_batches b JOIN consignors c ON c.id=b.consignor_id WHERE b.product_id=p.id AND c.is_archived=0 ORDER BY b.received_at DESC,b.id DESC LIMIT 1) consignor_id,
      (SELECT c.name FROM consignment_batches b JOIN consignors c ON c.id=b.consignor_id WHERE b.product_id=p.id AND c.is_archived=0 ORDER BY b.received_at DESC,b.id DESC LIMIT 1) consignor_name
      FROM products p WHERE p.is_archived=0 ORDER BY p.name COLLATE NOCASE''');
    final result = rows
        .map(
          (x) => RestockItem(
            Product.fromMap(x),
            x['consigned'] == 1,
            x['selecta'] == 1,
            consignorId: x['consignor_id'] as int?,
            consignorName: x['consignor_name'] as String?,
          ),
        )
        .where(
          (x) => switch (filter) {
            'LOW' =>
              x.product.currentQuantity > 0 &&
                  x.product.currentQuantity <= x.product.minimumStockLevel,
            'OUT' => x.product.currentQuantity == 0,
            'NEEDS' =>
              x.product.currentQuantity <= 0 ||
                  (x.product.currentQuantity > 0 &&
                      x.product.currentQuantity <= x.product.minimumStockLevel),
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
    final cash = await one('''SELECT
      COALESCE(SUM(CASE WHEN COALESCE(sp.payment_method,'CASH')='CASH' THEN s.total_centavos ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN sp.payment_method='GCASH' THEN s.total_centavos ELSE 0 END),0) gcash_total,
      SUM(CASE WHEN COALESCE(sp.payment_method,'CASH')='CASH' THEN 1 ELSE 0 END) cash_count,
      SUM(CASE WHEN sp.payment_method='GCASH' THEN 1 ELSE 0 END) gcash_count
      FROM cash_sales s LEFT JOIN sale_payments sp ON sp.cash_sale_id=s.id
      WHERE s.status='POSTED' AND s.occurred_at>=? AND s.occurred_at<?''');
    final utang = await one(
      "SELECT COALESCE(SUM(total_centavos),0) total,COUNT(*) count FROM utang_transactions WHERE status='POSTED' AND occurred_at>=? AND occurred_at<?",
    );
    final pay = await one(
      '''SELECT COALESCE(SUM(amount_centavos),0) total,COUNT(*) count,
      COALESCE(SUM(CASE WHEN payment_method='CASH' THEN amount_centavos ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN payment_method='GCASH' THEN amount_centavos ELSE 0 END),0) gcash_total
      FROM utang_payments WHERE status='POSTED' AND paid_at>=? AND paid_at<?''',
    );
    final expenses = await one(
      '''SELECT COALESCE(SUM(e.amount_centavos),0) total,COUNT(*) count,
      COALESCE(SUM(CASE WHEN COALESCE(ep.payment_method,'CASH')='CASH' THEN e.amount_centavos ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN ep.payment_method='GCASH' THEN e.amount_centavos ELSE 0 END),0) gcash_total
      FROM expenses e LEFT JOIN expense_payments ep ON ep.expense_id=e.id
      WHERE e.status='POSTED' AND e.expense_datetime>=? AND e.expense_datetime<?''',
    );
    final remittances = await one('''SELECT
      COALESCE(SUM(CASE WHEN payment_method='CASH' THEN amount_centavos ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN payment_method='GCASH' THEN amount_centavos ELSE 0 END),0) gcash_total,
      COUNT(*) count FROM consignor_remittances
      WHERE remitted_at>=? AND remitted_at<?''');
    final gcash = (await db.rawQuery(
      '''SELECT
      COALESCE(SUM(CASE WHEN occurred_at<? THEN amount_change_centavos ELSE 0 END),0) opening,
      COALESCE(SUM(CASE WHEN occurred_at>=? AND occurred_at<? AND amount_change_centavos>0 THEN amount_change_centavos ELSE 0 END),0) money_in,
      COALESCE(SUM(CASE WHEN occurred_at>=? AND occurred_at<? AND amount_change_centavos<0 THEN -amount_change_centavos ELSE 0 END),0) money_out
      FROM gcash_ledger_entries''',
      [start, start, end, start, end],
    )).single;
    final services = await one('''SELECT COUNT(*) service_count,
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' AND status='POSTED' THEN 1 ELSE 0 END),0) ci_count,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' AND status='POSTED' THEN 1 ELSE 0 END),0) co_count,
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' THEN CASE WHEN status='REVERSAL' THEN -principal_centavos ELSE principal_centavos END ELSE 0 END),0) ci_principal,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' THEN CASE WHEN status='REVERSAL' THEN -principal_centavos ELSE principal_centavos END ELSE 0 END),0) co_principal,
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' THEN CASE WHEN status='REVERSAL' THEN -fee_centavos ELSE fee_centavos END ELSE 0 END),0) ci_fees,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' THEN CASE WHEN status='REVERSAL' THEN -fee_centavos ELSE fee_centavos END ELSE 0 END),0) co_fees,
      COALESCE(SUM(physical_cash_change_centavos),0) cash_change,
      COALESCE(SUM(gcash_change_centavos),0) wallet_change
      FROM gcash_service_transactions WHERE created_at>=? AND created_at<?''');
    final con = await one(
      '''SELECT COALESCE(SUM(COALESCE(a.sale_revenue_centavos,a.selling_price_centavos*a.quantity)),0) sales,COALESCE(SUM(a.payable_centavos),0) payable,COALESCE(SUM(COALESCE(a.actual_margin_centavos,a.margin_centavos)),0) margin,COUNT(DISTINCT COALESCE(a.cash_sale_item_id,-a.utang_item_id)) count FROM consignment_allocations a WHERE a.occurred_at>=? AND a.occurred_at<? AND NOT EXISTS(SELECT 1 FROM consignment_allocation_reversals r WHERE r.allocation_id=a.id)''',
    );
    final stock = (await db.rawQuery(
      '''SELECT SUM(CASE WHEN current_quantity>0 AND current_quantity<=minimum_stock_level THEN 1 ELSE 0 END) low,SUM(CASE WHEN current_quantity=0 THEN 1 ELSE 0 END) out FROM products WHERE is_archived=0''',
    )).single;
    final top = await db.rawQuery(
      '''SELECT sold.name,SUM(sold.quantity) quantity,p.base_unit_code,p.base_unit_label
      FROM(SELECT i.product_id,i.product_name_snapshot name,COALESCE(i.total_base_quantity,i.quantity) quantity
      FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id
      WHERE s.status='POSTED' AND s.occurred_at>=? AND s.occurred_at<?
      UNION ALL SELECT i.product_id,i.product_name_snapshot,COALESCE(i.total_base_quantity,i.quantity)
      FROM utang_transaction_items i JOIN utang_transactions u ON u.id=i.utang_transaction_id
      WHERE u.status='POSTED' AND u.occurred_at>=? AND u.occurred_at<?) sold
      JOIN products p ON p.id=sold.product_id GROUP BY sold.product_id,sold.name
      ORDER BY quantity DESC LIMIT 5''',
      [start, end, start, end],
    );
    return DailyClosingSummary(
      cashSales: (cash['cash_total'] as int?) ?? 0,
      gcashSales: (cash['gcash_total'] as int?) ?? 0,
      cashSaleCount: (cash['cash_count'] as int?) ?? 0,
      gcashSaleCount: (cash['gcash_count'] as int?) ?? 0,
      newUtang: utang['total']! as int,
      payments: pay['total']! as int,
      cashPayments: pay['cash_total']! as int,
      gcashPayments: pay['gcash_total']! as int,
      operatingExpenses: expenses['total']! as int,
      cashExpenses: expenses['cash_total']! as int,
      gcashExpenses: expenses['gcash_total']! as int,
      cashRemittances: remittances['cash_total']! as int,
      gcashRemittances: remittances['gcash_total']! as int,
      gcashOpeningBalance: gcash['opening']! as int,
      gcashMoneyIn: gcash['money_in']! as int,
      gcashMoneyOut: gcash['money_out']! as int,
      cashInServiceCount: services['ci_count']! as int,
      cashOutServiceCount: services['co_count']! as int,
      cashInServicePrincipal: services['ci_principal']! as int,
      cashOutServicePrincipal: services['co_principal']! as int,
      cashInServiceFees: services['ci_fees']! as int,
      cashOutServiceFees: services['co_fees']! as int,
      gcashServicePhysicalCashChange: services['cash_change']! as int,
      gcashServiceWalletChange: services['wallet_change']! as int,
      consignmentSales: con['sales']! as int,
      supplierPayable: con['payable']! as int,
      consignmentMargin: con['margin']! as int,
      transactionCount:
          ((cash['cash_count'] as int?) ?? 0) +
          ((cash['gcash_count'] as int?) ?? 0) +
          (utang['count']! as int) +
          (pay['count']! as int) +
          (expenses['count']! as int) +
          (remittances['count']! as int) +
          (services['service_count']! as int),
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
      UNION ALL SELECT expense_datetime FROM expenses WHERE status='POSTED'
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
