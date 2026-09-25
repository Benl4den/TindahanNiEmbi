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
    this.mayaOpeningBalance = 0,
    this.mayaMoneyIn = 0,
    this.mayaMoneyOut = 0,
    this.mayaServiceCashReceived = 0,
    this.mayaServiceCashPaid = 0,
    this.mayaCashInServiceFees = 0,
    this.mayaCashOutServiceFees = 0,
    this.mayaServiceCount = 0,
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
  final int mayaOpeningBalance,
      mayaMoneyIn,
      mayaMoneyOut,
      mayaServiceCashReceived,
      mayaServiceCashPaid,
      mayaCashInServiceFees,
      mayaCashOutServiceFees,
      mayaServiceCount;
  final int loanCashReceived, loanCashPayments, loanCashPaymentReversals;
  final int loanMayaReceived, loanMayaPayments, loanMayaPaymentReversals;
  int get totalSales => cashSales + gcashSales + mayaSales;
  int get serviceFeeIncome => cashInServiceFees + cashOutServiceFees;
  int get mayaServiceFeeIncome =>
      mayaCashInServiceFees + mayaCashOutServiceFees;
  int get totalEarnings => totalSales + serviceFeeIncome + mayaServiceFeeIncome;
  int get cashReceived =>
      cashSales +
      cashPayments +
      gcashServiceCashReceived +
      mayaServiceCashReceived +
      loanCashReceived;
  int get cashPaid =>
      cashExpenses +
      cashRemittances +
      gcashServiceCashPaid +
      mayaServiceCashPaid +
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
  int get mayaEndingBalance => mayaOpeningBalance + mayaMoneyIn - mayaMoneyOut;

  Map<String, Object?> toJson() => {
    'cashSales': cashSales,
    'gcashSales': gcashSales,
    'mayaSales': mayaSales,
    'mayaSaleCount': mayaSaleCount,
    'mayaPayments': mayaPayments,
    'mayaExpenses': mayaExpenses,
    'mayaRemittances': mayaRemittances,
    'mayaOpeningBalance': mayaOpeningBalance,
    'mayaMoneyIn': mayaMoneyIn,
    'mayaMoneyOut': mayaMoneyOut,
    'mayaServiceCashReceived': mayaServiceCashReceived,
    'mayaServiceCashPaid': mayaServiceCashPaid,
    'mayaCashInServiceFees': mayaCashInServiceFees,
    'mayaCashOutServiceFees': mayaCashOutServiceFees,
    'mayaServiceCount': mayaServiceCount,
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
      mayaOpeningBalance: value('mayaOpeningBalance'),
      mayaMoneyIn: value('mayaMoneyIn'),
      mayaMoneyOut: value('mayaMoneyOut'),
      mayaServiceCashReceived: value('mayaServiceCashReceived'),
      mayaServiceCashPaid: value('mayaServiceCashPaid'),
      mayaCashInServiceFees: value('mayaCashInServiceFees'),
      mayaCashOutServiceFees: value('mayaCashOutServiceFees'),
      mayaServiceCount: value('mayaServiceCount'),
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

  Future<DailyClosingSnapshot> closeDay(
    DateTime day, {
    DailyClosingSummary? expectedSummary,
  }) => db.transaction((tx) async {
    final rows = await tx.query(
      'daily_closing_snapshots',
      where: 'closing_date=?',
      whereArgs: [_dayKey(day)],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final row = rows.single;
      return DailyClosingSnapshot(
        day: DateTime(day.year, day.month, day.day),
        summary: DailyClosingSummary.fromJson(
          jsonDecode(row['summary_json']! as String) as Map<String, dynamic>,
        ),
        closedAt: DateTime.parse(row['closed_at']! as String).toLocal(),
      );
    }
    final summary = await _daily(tx, day);
    if (expectedSummary != null &&
        jsonEncode(summary.toJson()) != jsonEncode(expectedSummary.toJson())) {
      throw StateError(
        'Daily Closing changed. Review the updated summary before saving.',
      );
    }
    final closedAt = DateTime.now();
    await tx.insert('daily_closing_snapshots', {
      'closing_date': _dayKey(day),
      'summary_json': jsonEncode(summary.toJson()),
      'closed_at': closedAt.toUtc().toIso8601String(),
    });
    return DailyClosingSnapshot(
      day: DateTime(day.year, day.month, day.day),
      summary: summary,
      closedAt: closedAt,
    );
  });

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

  Future<DailyClosingSummary> daily(DateTime date, {DateTime? endDate}) =>
      db.transaction((tx) => _daily(tx, date, endDate: endDate));

  Future<DailyClosingSummary> _daily(
    DatabaseExecutor source,
    DateTime date, {
    DateTime? endDate,
  }) async {
    final local = DateTime(date.year, date.month, date.day),
        start = local.toUtc().toIso8601String(),
        end = (endDate ?? DateTime(local.year, local.month, local.day + 1))
            .toUtc()
            .toIso8601String();
    Future<Map<String, Object?>> one(String sql) =>
        source.rawQuery(sql, [start, end]).then((x) => x.single);
    final cash = await one('''WITH movements AS (
      SELECT s.total_centavos amount,COALESCE(sp.payment_method_display,sp.payment_method,'CASH') method,s.occurred_at stamp
      FROM cash_sales s LEFT JOIN sale_payments sp ON sp.cash_sale_id=s.id
      WHERE s.status IN ('POSTED','REVERSED')
      UNION ALL
      SELECT -s.total_centavos,COALESCE(sp.payment_method_display,sp.payment_method,'CASH'),r.occurred_at
      FROM transaction_reversals r JOIN cash_sales s ON s.id=r.cash_sale_id
      LEFT JOIN sale_payments sp ON sp.cash_sale_id=s.id
    ) SELECT
      COALESCE(SUM(CASE WHEN method='CASH' THEN amount ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN method='GCASH' THEN amount ELSE 0 END),0) gcash_total,
      COALESCE(SUM(CASE WHEN method='MAYA' THEN amount ELSE 0 END),0) maya_total,
      COALESCE(SUM(CASE WHEN method='CASH' THEN 1 ELSE 0 END),0) cash_count,
      COALESCE(SUM(CASE WHEN method='GCASH' THEN 1 ELSE 0 END),0) gcash_count,
      COALESCE(SUM(CASE WHEN method='MAYA' THEN 1 ELSE 0 END),0) maya_count
      FROM movements WHERE stamp>=? AND stamp<?''');
    final utang = await one('''WITH movements AS (
      SELECT total_centavos amount,occurred_at stamp FROM utang_transactions
      WHERE status IN ('POSTED','REVERSED') AND COALESCE(is_existing_balance,0)=0
      UNION ALL
      SELECT -u.total_centavos,r.occurred_at FROM transaction_reversals r
      JOIN utang_transactions u ON u.id=r.utang_transaction_id
      WHERE COALESCE(u.is_existing_balance,0)=0
    ) SELECT COALESCE(SUM(amount),0) total,COUNT(*) count FROM movements
    WHERE stamp>=? AND stamp<?''');
    final pay = await one('''WITH movements AS (
      SELECT amount_centavos amount,COALESCE(payment_method_display,payment_method,'CASH') method,paid_at stamp
      FROM utang_payments WHERE status IN ('POSTED','REVERSED')
      UNION ALL
      SELECT -p.amount_centavos,COALESCE(p.payment_method_display,p.payment_method,'CASH'),r.occurred_at
      FROM transaction_reversals r JOIN utang_payments p ON p.id=r.payment_id
      ) SELECT COALESCE(SUM(amount),0) total,COUNT(*) count,
      COALESCE(SUM(CASE WHEN method='CASH' THEN amount ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN method='GCASH' THEN amount ELSE 0 END),0) gcash_total,
      COALESCE(SUM(CASE WHEN method='MAYA' THEN amount ELSE 0 END),0) maya_total
      FROM movements WHERE stamp>=? AND stamp<?''');
    final expenses = await one('''WITH movements AS (
      SELECT e.amount_centavos amount,COALESCE(ep.payment_method_display,ep.payment_method,'CASH') method,e.expense_datetime stamp
      FROM expenses e LEFT JOIN expense_payments ep ON ep.expense_id=e.id
      UNION ALL
      SELECT -e.amount_centavos,COALESCE(ep.payment_method_display,ep.payment_method,'CASH'),r.occurred_at
      FROM expense_reversals r JOIN expenses e ON e.id=r.expense_id
      LEFT JOIN expense_payments ep ON ep.expense_id=e.id
      ) SELECT COALESCE(SUM(amount),0) total,COUNT(*) count,
      COALESCE(SUM(CASE WHEN method='CASH' THEN amount ELSE 0 END),0) cash_total,
      COALESCE(SUM(CASE WHEN method='GCASH' THEN amount ELSE 0 END),0) gcash_total,
      COALESCE(SUM(CASE WHEN method='MAYA' THEN amount ELSE 0 END),0) maya_total
      FROM movements WHERE stamp>=? AND stamp<?''');
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
    final gcash = (await source.rawQuery(
      '''SELECT
      COALESCE(SUM(CASE WHEN occurred_at<? THEN amount_change_centavos ELSE 0 END),0) opening,
      COALESCE(SUM(CASE WHEN occurred_at>=? AND occurred_at<? AND amount_change_centavos>0 THEN amount_change_centavos ELSE 0 END),0) money_in,
      COALESCE(SUM(CASE WHEN occurred_at>=? AND occurred_at<? AND amount_change_centavos<0 THEN -amount_change_centavos ELSE 0 END),0) money_out
      FROM gcash_ledger_entries''',
      [start, start, end, start, end],
    )).single;
    final maya = (await source.rawQuery(
      '''SELECT
      COALESCE(SUM(CASE WHEN occurred_at<? THEN amount_change_centavos ELSE 0 END),0) opening,
      COALESCE(SUM(CASE WHEN occurred_at>=? AND occurred_at<? AND amount_change_centavos>0 THEN amount_change_centavos ELSE 0 END),0) money_in,
      COALESCE(SUM(CASE WHEN occurred_at>=? AND occurred_at<? AND amount_change_centavos<0 THEN -amount_change_centavos ELSE 0 END),0) money_out
      FROM maya_ledger_entries''',
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
    final mayaServices = await one('''SELECT COUNT(*) service_count,
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' THEN CASE WHEN status='REVERSAL' THEN -fee_centavos ELSE fee_centavos END ELSE 0 END),0) ci_fees,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' THEN CASE WHEN status='REVERSAL' THEN -fee_centavos ELSE fee_centavos END ELSE 0 END),0) co_fees,
      COALESCE(SUM(CASE WHEN physical_cash_change_centavos>0 THEN physical_cash_change_centavos ELSE 0 END),0) cash_received,
      COALESCE(SUM(CASE WHEN physical_cash_change_centavos<0 THEN -physical_cash_change_centavos ELSE 0 END),0) cash_paid
      FROM maya_service_transactions WHERE created_at>=? AND created_at<?''');
    final con = await one(
      '''WITH movements AS (
      SELECT COALESCE(a.sale_revenue_centavos,a.selling_price_centavos*a.quantity) sales,
      a.payable_centavos payable,COALESCE(a.actual_margin_centavos,a.margin_centavos) margin,a.occurred_at stamp
      FROM consignment_allocations a
      UNION ALL
      SELECT -COALESCE(a.sale_revenue_centavos,a.selling_price_centavos*a.quantity),
      r.payable_change_centavos,r.margin_change_centavos,r.occurred_at
      FROM consignment_allocation_reversals r JOIN consignment_allocations a ON a.id=r.allocation_id
      ) SELECT COALESCE(SUM(sales),0) sales,COALESCE(SUM(payable),0) payable,
      COALESCE(SUM(margin),0) margin FROM movements WHERE stamp>=? AND stamp<?''',
    );
    final stock = (await source.rawQuery(
      '''SELECT SUM(CASE WHEN current_quantity>0 AND current_quantity<=minimum_stock_level THEN 1 ELSE 0 END) low,SUM(CASE WHEN current_quantity=0 THEN 1 ELSE 0 END) out FROM products WHERE is_archived=0''',
    )).single;
    final top = await productSalesRanking(
      source,
      start: start,
      end: end,
      limit: 5,
      includeReversed: true,
      useSaleSnapshots: true,
    );
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
      mayaOpeningBalance: maya['opening']! as int,
      mayaMoneyIn: maya['money_in']! as int,
      mayaMoneyOut: maya['money_out']! as int,
      mayaServiceCashReceived: mayaServices['cash_received']! as int,
      mayaServiceCashPaid: mayaServices['cash_paid']! as int,
      mayaCashInServiceFees: mayaServices['ci_fees']! as int,
      mayaCashOutServiceFees: mayaServices['co_fees']! as int,
      mayaServiceCount: mayaServices['service_count']! as int,
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
          (mayaServices['service_count']! as int) +
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
      SELECT occurred_at stamp FROM cash_sales WHERE status IN ('POSTED','REVERSED')
      UNION ALL SELECT occurred_at FROM utang_transactions WHERE status IN ('POSTED','REVERSED') AND COALESCE(is_existing_balance,0)=0
      UNION ALL SELECT paid_at FROM utang_payments WHERE status IN ('POSTED','REVERSED')
      UNION ALL SELECT expense_datetime FROM expenses
      UNION ALL SELECT occurred_at FROM transaction_reversals
      UNION ALL SELECT occurred_at FROM expense_reversals
      UNION ALL SELECT remitted_at FROM consignor_remittances
      UNION ALL SELECT created_at FROM gcash_service_transactions
      UNION ALL SELECT created_at FROM maya_service_transactions
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
