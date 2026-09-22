import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
import 'product_sales_ranking.dart';

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
    required this.gcashServiceCashReceived,
    required this.gcashServiceCashPaid,
    required this.gcashServiceWalletReceived,
    required this.gcashServiceWalletSent,
    required this.consignmentSales,
    required this.supplierPayable,
    required this.consignmentMargin,
    required this.transactionCount,
    this.expenseCount,
    required this.lowStock,
    required this.outOfStock,
    required this.topProducts,
    this.mayaSales = 0,
    this.mayaSaleCount = 0,
    this.mayaPayments = 0,
    this.mayaExpenses = 0,
    this.mayaRemittances = 0,
    this.loanCashReceived = 0,
    this.loanCashPayments = 0,
    this.loanCashPaymentReversals = 0,
    this.loanMayaReceived = 0,
    this.loanMayaPayments = 0,
    this.loanMayaPaymentReversals = 0,
  });
  final int? expenseCount;
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
      gcashServiceCashReceived,
      gcashServiceCashPaid,
      gcashServiceWalletReceived,
      gcashServiceWalletSent,
      consignmentSales,
      supplierPayable,
      consignmentMargin,
      transactionCount,
      lowStock,
      outOfStock;
  final List<Map<String, Object?>> topProducts;
  final int mayaSales,
      mayaSaleCount,
      mayaPayments,
      mayaExpenses,
      mayaRemittances;
  final int loanCashReceived, loanCashPayments, loanCashPaymentReversals;
  final int loanMayaReceived, loanMayaPayments, loanMayaPaymentReversals;
  int get totalSales => cashSales + gcashSales + mayaSales;
  int get serviceFeeIncome => cashInServiceFees + cashOutServiceFees;
  int get totalEarnings => totalSales + serviceFeeIncome;
  int get cashReceived =>
      cashSales + cashPayments + gcashServiceCashReceived + loanCashReceived;
  int get cashPaid =>
      cashExpenses +
      cashRemittances +
      gcashServiceCashPaid +
      loanCashPayments -
      loanCashPaymentReversals;
  int get cashDifference => cashReceived - cashPaid;
  int get gcashDifference => gcashMoneyIn - gcashMoneyOut;
  // Retained for repository compatibility. Owner-facing UI uses the clearer
  // received, paid out, and difference fields above.
  int get recordedCashIn => cashReceived;
  int get netRecordedCash => cashDifference;
  int get gcashEndingBalance =>
      gcashOpeningBalance + gcashMoneyIn - gcashMoneyOut;

  Map<String, Object?> toJson() => {
    'cashSales': cashSales,
    'gcashSales': gcashSales,
    'mayaSales': mayaSales,
    'mayaSaleCount': mayaSaleCount,
    'mayaPayments': mayaPayments,
    'mayaExpenses': mayaExpenses,
    'mayaRemittances': mayaRemittances,
    'loanCashReceived': loanCashReceived,
    'loanCashPayments': loanCashPayments,
    'loanCashPaymentReversals': loanCashPaymentReversals,
    'loanMayaReceived': loanMayaReceived,
    'loanMayaPayments': loanMayaPayments,
    'loanMayaPaymentReversals': loanMayaPaymentReversals,
    'cashSaleCount': cashSaleCount,
    'gcashSaleCount': gcashSaleCount,
    'newUtang': newUtang,
    'payments': payments,
    'cashPayments': cashPayments,
    'gcashPayments': gcashPayments,
    'operatingExpenses': operatingExpenses,
    'cashExpenses': cashExpenses,
    'gcashExpenses': gcashExpenses,
    'cashRemittances': cashRemittances,
    'gcashRemittances': gcashRemittances,
    'gcashOpeningBalance': gcashOpeningBalance,
    'gcashMoneyIn': gcashMoneyIn,
    'gcashMoneyOut': gcashMoneyOut,
    'cashInServiceCount': cashInServiceCount,
    'cashOutServiceCount': cashOutServiceCount,
    'cashInServicePrincipal': cashInServicePrincipal,
    'cashOutServicePrincipal': cashOutServicePrincipal,
    'cashInServiceFees': cashInServiceFees,
    'cashOutServiceFees': cashOutServiceFees,
    'gcashServicePhysicalCashChange': gcashServicePhysicalCashChange,
    'gcashServiceWalletChange': gcashServiceWalletChange,
    'gcashServiceCashReceived': gcashServiceCashReceived,
    'gcashServiceCashPaid': gcashServiceCashPaid,
    'gcashServiceWalletReceived': gcashServiceWalletReceived,
    'gcashServiceWalletSent': gcashServiceWalletSent,
    'consignmentSales': consignmentSales,
    'supplierPayable': supplierPayable,
    'consignmentMargin': consignmentMargin,
    'transactionCount': transactionCount,
    'expenseCount': expenseCount,
    'lowStock': lowStock,
    'outOfStock': outOfStock,
    'topProducts': topProducts,
  };

  factory DailyClosingSummary.fromJson(Map<String, dynamic> json) {
    int value(String key) => json[key] is num ? (json[key] as num).toInt() : 0;
    final products = (json['topProducts'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => row.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList();
    return DailyClosingSummary(
      cashSales: value('cashSales'),
      gcashSales: value('gcashSales'),
      mayaSales: value('mayaSales'),
      mayaSaleCount: value('mayaSaleCount'),
      mayaPayments: value('mayaPayments'),
      mayaExpenses: value('mayaExpenses'),
      mayaRemittances: value('mayaRemittances'),
      loanCashReceived: value('loanCashReceived'),
      loanCashPayments: value('loanCashPayments'),
      loanCashPaymentReversals: value('loanCashPaymentReversals'),
      loanMayaReceived: value('loanMayaReceived'),
      loanMayaPayments: value('loanMayaPayments'),
      loanMayaPaymentReversals: value('loanMayaPaymentReversals'),
      cashSaleCount: value('cashSaleCount'),
      gcashSaleCount: value('gcashSaleCount'),
      newUtang: value('newUtang'),
      payments: value('payments'),
      cashPayments: value('cashPayments'),
      gcashPayments: value('gcashPayments'),
      operatingExpenses: value('operatingExpenses'),
      cashExpenses: value('cashExpenses'),
      gcashExpenses: value('gcashExpenses'),
      cashRemittances: value('cashRemittances'),
      gcashRemittances: value('gcashRemittances'),
      gcashOpeningBalance: value('gcashOpeningBalance'),
      gcashMoneyIn: value('gcashMoneyIn'),
      gcashMoneyOut: value('gcashMoneyOut'),
      cashInServiceCount: value('cashInServiceCount'),
      cashOutServiceCount: value('cashOutServiceCount'),
      cashInServicePrincipal: value('cashInServicePrincipal'),
      cashOutServicePrincipal: value('cashOutServicePrincipal'),
      cashInServiceFees: value('cashInServiceFees'),
      cashOutServiceFees: value('cashOutServiceFees'),
      gcashServicePhysicalCashChange: value('gcashServicePhysicalCashChange'),
      gcashServiceWalletChange: value('gcashServiceWalletChange'),
      gcashServiceCashReceived: value('gcashServiceCashReceived'),
      gcashServiceCashPaid: value('gcashServiceCashPaid'),
      gcashServiceWalletReceived: value('gcashServiceWalletReceived'),
      gcashServiceWalletSent: value('gcashServiceWalletSent'),
      consignmentSales: value('consignmentSales'),
      supplierPayable: value('supplierPayable'),
      consignmentMargin: value('consignmentMargin'),
      transactionCount: value('transactionCount'),
      expenseCount: json['expenseCount'] as int?,
      lowStock: value('lowStock'),
      outOfStock: value('outOfStock'),
      topProducts: products,
    );
  }
}

class DailyClosingSnapshot {
  const DailyClosingSnapshot({
    required this.day,
    required this.summary,
    required this.closedAt,
  });

  final DateTime day;
  final DailyClosingSummary summary;
  final DateTime closedAt;
}

class OperationsRepository {
  const OperationsRepository(this.db);
  final Database db;

  String _dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  Future<DailyClosingSnapshot?> snapshotFor(DateTime day) async {
    final rows = await db.query(
      'daily_closing_snapshots',
      where: 'closing_date=?',
      whereArgs: [_dayKey(day)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return DailyClosingSnapshot(
      day: DateTime.parse(row['closing_date']! as String),
      summary: DailyClosingSummary.fromJson(
        jsonDecode(row['summary_json']! as String) as Map<String, dynamic>,
      ),
      closedAt: DateTime.parse(row['closed_at']! as String).toLocal(),
    );
  }

  Future<DailyClosingSummary> summaryForDate(DateTime day) async =>
      (await snapshotFor(day))?.summary ?? daily(day);

  Future<DailyClosingSnapshot> closeDay(DateTime day) async {
    final existing = await snapshotFor(day);
    if (existing != null) return existing;
    final summary = await daily(day);
    final closedAt = DateTime.now();
    try {
      await db.insert('daily_closing_snapshots', {
        'closing_date': _dayKey(day),
        'summary_json': jsonEncode(summary.toJson()),
        'closed_at': closedAt.toUtc().toIso8601String(),
      });
    } on DatabaseException {
      final saved = await snapshotFor(day);
      if (saved != null) return saved;
      rethrow;
    }
    return DailyClosingSnapshot(
      day: DateTime(day.year, day.month, day.day),
      summary: summary,
      closedAt: closedAt,
    );
  }

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

  Future<DailyClosingSummary> daily(DateTime date, {DateTime? endDate}) async {
    final local = DateTime(date.year, date.month, date.day),
        start = local.toUtc().toIso8601String(),
        end = (endDate ?? DateTime(local.year, local.month, local.day + 1))
            .toUtc()
            .toIso8601String();
    Future<Map<String, Object?>> one(String sql) =>
        db.rawQuery(sql, [start, end]).then((x) => x.single);
    final cash = await one('''SELECT
      COALESCE(SUM(CASE WHEN COALESCE(sp.payment_method_display,sp.payment_method,'CASH')='CASH' THEN s.total_centavos ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN COALESCE(sp.payment_method_display,sp.payment_method)='GCASH' THEN s.total_centavos ELSE 0 END),0) gcash_total,
      COALESCE(SUM(CASE WHEN COALESCE(sp.payment_method_display,sp.payment_method)='MAYA' THEN s.total_centavos ELSE 0 END),0) maya_total,
      SUM(CASE WHEN COALESCE(sp.payment_method_display,sp.payment_method,'CASH')='CASH' THEN 1 ELSE 0 END) cash_count,
      SUM(CASE WHEN COALESCE(sp.payment_method_display,sp.payment_method)='GCASH' THEN 1 ELSE 0 END) gcash_count,
      SUM(CASE WHEN COALESCE(sp.payment_method_display,sp.payment_method)='MAYA' THEN 1 ELSE 0 END) maya_count
      FROM cash_sales s LEFT JOIN sale_payments sp ON sp.cash_sale_id=s.id
      WHERE s.status='POSTED' AND s.occurred_at>=? AND s.occurred_at<?''');
    final utang = await one(
      "SELECT COALESCE(SUM(total_centavos),0) total,COUNT(*) count FROM utang_transactions WHERE status='POSTED' AND COALESCE(is_existing_balance,0)=0 AND occurred_at>=? AND occurred_at<?",
    );
    final pay = await one(
      '''SELECT COALESCE(SUM(amount_centavos),0) total,COUNT(*) count,
      COALESCE(SUM(CASE WHEN COALESCE(payment_method_display,payment_method)='CASH' THEN amount_centavos ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN COALESCE(payment_method_display,payment_method)='GCASH' THEN amount_centavos ELSE 0 END),0) gcash_total,
      COALESCE(SUM(CASE WHEN COALESCE(payment_method_display,payment_method)='MAYA' THEN amount_centavos ELSE 0 END),0) maya_total
      FROM utang_payments WHERE status='POSTED' AND paid_at>=? AND paid_at<?''',
    );
    final expenses = await one(
      '''SELECT COALESCE(SUM(e.amount_centavos),0) total,COUNT(*) count,
      COALESCE(SUM(CASE WHEN COALESCE(ep.payment_method_display,ep.payment_method,'CASH')='CASH' THEN e.amount_centavos ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN COALESCE(ep.payment_method_display,ep.payment_method)='GCASH' THEN e.amount_centavos ELSE 0 END),0) gcash_total,
      COALESCE(SUM(CASE WHEN COALESCE(ep.payment_method_display,ep.payment_method)='MAYA' THEN e.amount_centavos ELSE 0 END),0) maya_total
      FROM expenses e LEFT JOIN expense_payments ep ON ep.expense_id=e.id
      WHERE e.status='POSTED' AND e.expense_datetime>=? AND e.expense_datetime<?''',
    );
    final remittances = await one('''SELECT
      COALESCE(SUM(CASE WHEN COALESCE(payment_method_display,payment_method,'CASH')='CASH' THEN amount_centavos ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN COALESCE(payment_method_display,payment_method)='GCASH' THEN amount_centavos ELSE 0 END),0) gcash_total,
      COALESCE(SUM(CASE WHEN COALESCE(payment_method_display,payment_method)='MAYA' THEN amount_centavos ELSE 0 END),0) maya_total,
      COUNT(*) count FROM consignor_remittances
      WHERE remitted_at>=? AND remitted_at<?''');
    final loanReceipts = await one(
      '''SELECT COALESCE(SUM(CASE WHEN source_kind='NEW' AND received_payment_method='CASH' THEN borrowed_amount_centavos ELSE 0 END),0) cash_total,COALESCE(SUM(CASE WHEN source_kind='NEW' AND received_payment_method='MAYA' THEN borrowed_amount_centavos ELSE 0 END),0) maya_total,COUNT(*) count FROM loans WHERE created_at>=? AND created_at<?''',
    );
    final loanPayments = await one(
      '''SELECT COALESCE(SUM(CASE WHEN payment_method='CASH' THEN amount_centavos ELSE 0 END),0) cash_total,COALESCE(SUM(CASE WHEN payment_method='MAYA' THEN amount_centavos ELSE 0 END),0) maya_total,COUNT(*) count FROM loan_payments WHERE paid_at>=? AND paid_at<?''',
    );
    final loanReversals = await one(
      '''SELECT COALESCE(SUM(CASE WHEN payment_method='CASH' THEN amount_centavos ELSE 0 END),0) cash_total,COALESCE(SUM(CASE WHEN payment_method='MAYA' THEN amount_centavos ELSE 0 END),0) maya_total,COUNT(*) count FROM loan_payments WHERE status='REVERSED' AND reversed_at>=? AND reversed_at<?''',
    );
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
      COALESCE(SUM(gcash_change_centavos),0) wallet_change,
      COALESCE(SUM(CASE WHEN physical_cash_change_centavos>0 THEN physical_cash_change_centavos ELSE 0 END),0) cash_received,
      COALESCE(SUM(CASE WHEN physical_cash_change_centavos<0 THEN -physical_cash_change_centavos ELSE 0 END),0) cash_paid,
      COALESCE(SUM(CASE WHEN gcash_change_centavos>0 THEN gcash_change_centavos ELSE 0 END),0) wallet_received,
      COALESCE(SUM(CASE WHEN gcash_change_centavos<0 THEN -gcash_change_centavos ELSE 0 END),0) wallet_sent
      FROM gcash_service_transactions WHERE created_at>=? AND created_at<?''');
    final con = await one(
      '''SELECT COALESCE(SUM(COALESCE(a.sale_revenue_centavos,a.selling_price_centavos*a.quantity)),0) sales,COALESCE(SUM(a.payable_centavos),0) payable,COALESCE(SUM(COALESCE(a.actual_margin_centavos,a.margin_centavos)),0) margin,COUNT(DISTINCT COALESCE(a.cash_sale_item_id,-a.utang_item_id)) count FROM consignment_allocations a WHERE a.occurred_at>=? AND a.occurred_at<? AND NOT EXISTS(SELECT 1 FROM consignment_allocation_reversals r WHERE r.allocation_id=a.id)''',
    );
    final stock = (await db.rawQuery(
      '''SELECT SUM(CASE WHEN current_quantity>0 AND current_quantity<=minimum_stock_level THEN 1 ELSE 0 END) low,SUM(CASE WHEN current_quantity=0 THEN 1 ELSE 0 END) out FROM products WHERE is_archived=0''',
    )).single;
    final top = await productSalesRanking(db, start: start, end: end, limit: 5);
    return DailyClosingSummary(
      cashSales: (cash['cash_total'] as int?) ?? 0,
      gcashSales: (cash['gcash_total'] as int?) ?? 0,
      mayaSales: (cash['maya_total'] as int?) ?? 0,
      cashSaleCount: (cash['cash_count'] as int?) ?? 0,
      gcashSaleCount: (cash['gcash_count'] as int?) ?? 0,
      mayaSaleCount: (cash['maya_count'] as int?) ?? 0,
      newUtang: utang['total']! as int,
      payments: pay['total']! as int,
      cashPayments: pay['cash_total']! as int,
      gcashPayments: pay['gcash_total']! as int,
      mayaPayments: pay['maya_total']! as int,
      operatingExpenses: expenses['total']! as int,
      expenseCount: expenses['count']! as int,
      cashExpenses: expenses['cash_total']! as int,
      gcashExpenses: expenses['gcash_total']! as int,
      mayaExpenses: expenses['maya_total']! as int,
      cashRemittances: remittances['cash_total']! as int,
      gcashRemittances: remittances['gcash_total']! as int,
      mayaRemittances: remittances['maya_total']! as int,
      loanCashReceived: loanReceipts['cash_total']! as int,
      loanCashPayments: loanPayments['cash_total']! as int,
      loanCashPaymentReversals: loanReversals['cash_total']! as int,
      loanMayaReceived: loanReceipts['maya_total']! as int,
      loanMayaPayments: loanPayments['maya_total']! as int,
      loanMayaPaymentReversals: loanReversals['maya_total']! as int,
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
      gcashServiceCashReceived: services['cash_received']! as int,
      gcashServiceCashPaid: services['cash_paid']! as int,
      gcashServiceWalletReceived: services['wallet_received']! as int,
      gcashServiceWalletSent: services['wallet_sent']! as int,
      consignmentSales: con['sales']! as int,
      supplierPayable: con['payable']! as int,
      consignmentMargin: con['margin']! as int,
      transactionCount:
          ((cash['cash_count'] as int?) ?? 0) +
          ((cash['gcash_count'] as int?) ?? 0) +
          ((cash['maya_count'] as int?) ?? 0) +
          (utang['count']! as int) +
          (pay['count']! as int) +
          (expenses['count']! as int) +
          (remittances['count']! as int) +
          (services['service_count']! as int) +
          (loanReceipts['count']! as int) +
          (loanPayments['count']! as int) +
          (loanReversals['count']! as int),
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
      UNION ALL SELECT remitted_at FROM consignor_remittances
      UNION ALL SELECT created_at FROM gcash_service_transactions
      UNION ALL SELECT created_at FROM loans
      UNION ALL SELECT paid_at FROM loan_payments
      UNION ALL SELECT reversed_at FROM loan_payments WHERE reversed_at IS NOT NULL
      UNION ALL SELECT closing_date FROM daily_closing_snapshots
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
