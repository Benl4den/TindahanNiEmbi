import 'package:sqflite/sqflite.dart';

class SalesPeriodSummary {
  const SalesPeriodSummary(
    this.daily,
    this.weekly,
    this.monthly, {
    required this.dailyCash,
    required this.dailyGCash,
  });
  final int daily, weekly, monthly;
  final int dailyCash, dailyGCash;
}

class ReportsRepository {
  const ReportsRepository(this.db);
  final Database db;
  Future<List<int>> frequentProductIds() async => (await db.rawQuery('''
    SELECT product_id FROM (
      SELECT DISTINCT i.product_id,'C'||s.id transaction_key,s.occurred_at
      FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id WHERE s.status='POSTED'
      UNION ALL
      SELECT DISTINCT i.product_id,'U'||s.id,s.occurred_at
      FROM utang_transaction_items i JOIN utang_transactions s ON s.id=i.utang_transaction_id WHERE s.status='POSTED'
    ) sold JOIN products p ON p.id=sold.product_id
    WHERE p.is_archived=0
    GROUP BY product_id ORDER BY COUNT(*) DESC,MAX(occurred_at) DESC,product_id ASC LIMIT 20
  ''')).map((r) => r['product_id']! as int).toList();
  Future<List<Map<String, Object?>>> inventory() => db.rawQuery(
    '''SELECT p.name,p.current_quantity,p.base_unit_code,p.base_unit_label,
      p.purchase_price_centavos,p.selling_price_centavos,
      COALESCE(k.name,p.base_unit_label) purchase_package,
      COALESCE(k.base_quantity,1) purchase_package_quantity,
      ((p.current_quantity*p.purchase_price_centavos)+COALESCE(k.base_quantity,1)/2)
        /COALESCE(k.base_quantity,1) stock_value
      FROM products p LEFT JOIN product_purchase_packages k
        ON k.product_id=p.id AND k.is_default=1 AND k.is_archived=0
      WHERE p.is_archived=0 AND NOT EXISTS(
        SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g
          ON g.id=m.inventory_group_id
        WHERE m.product_id=p.id AND m.archived_at IS NULL AND g.code='CONSIGNMENT')
      ORDER BY p.name COLLATE NOCASE''',
  );
  Future<List<Map<String, Object?>>> outstanding() => db.rawQuery(
    '''SELECT c.full_name, SUM(l.amount_change_centavos) balance FROM customers c JOIN customer_ledger_entries l ON l.customer_id=c.id GROUP BY c.id HAVING balance>0 ORDER BY balance DESC''',
  );
  Future<List<Map<String, Object?>>> movements({bool? outgoing}) => db.rawQuery(
    '''SELECT p.name,p.base_unit_code,p.base_unit_label,t.type,m.quantity_change,m.unit_cost_centavos,t.notes,t.occurred_at FROM inventory_movements m JOIN inventory_transactions t ON t.id=m.inventory_transaction_id JOIN products p ON p.id=m.product_id ${outgoing == null
        ? ''
        : outgoing
        ? 'WHERE m.quantity_change<0'
        : 'WHERE m.quantity_change>0'} ORDER BY t.occurred_at DESC''',
  );
  Future<SalesPeriodSummary> salesPeriods({DateTime? now}) async {
    final n = (now ?? DateTime.now()).toLocal(),
        day = DateTime(n.year, n.month, n.day),
        week = day.subtract(Duration(days: day.weekday - 1)),
        month = DateTime(n.year, n.month);
    Future<int> total(DateTime start) => db
        .rawQuery(
          "SELECT COALESCE(SUM(total_centavos),0) value FROM cash_sales WHERE status='POSTED' AND occurred_at>=? AND occurred_at<?",
          [
            start.toUtc().toIso8601String(),
            day.add(const Duration(days: 1)).toUtc().toIso8601String(),
          ],
        )
        .then((r) => r.single['value']! as int);
    final today = await db.rawQuery(
      '''SELECT
      COALESCE(SUM(CASE WHEN COALESCE(sp.payment_method,'CASH')='CASH' THEN s.total_centavos ELSE 0 END),0) cash,
      COALESCE(SUM(CASE WHEN sp.payment_method='GCASH' THEN s.total_centavos ELSE 0 END),0) gcash
      FROM cash_sales s LEFT JOIN sale_payments sp ON sp.cash_sale_id=s.id
      WHERE s.status='POSTED' AND s.occurred_at>=? AND s.occurred_at<?''',
      [
        day.toUtc().toIso8601String(),
        day.add(const Duration(days: 1)).toUtc().toIso8601String(),
      ],
    );
    final dailyCash = today.single['cash']! as int;
    final dailyGCash = today.single['gcash']! as int;
    return SalesPeriodSummary(
      dailyCash + dailyGCash,
      await total(week),
      await total(month),
      dailyCash: dailyCash,
      dailyGCash: dailyGCash,
    );
  }

  Future<List<Map<String, Object?>>> frequentProducts() => db.rawQuery(
    "SELECT i.product_name_snapshot name,SUM(COALESCE(i.total_base_quantity,i.quantity)) quantity,p.base_unit_code,p.base_unit_label FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id JOIN products p ON p.id=i.product_id WHERE s.status='POSTED' GROUP BY i.product_id,i.product_name_snapshot ORDER BY quantity DESC",
  );
  Future<int> outstandingTotal() async =>
      (await db.rawQuery(
            'SELECT COALESCE(SUM(amount_change_centavos),0) value FROM customer_ledger_entries',
          )).single['value']!
          as int;
  Future<List<Map<String, Object?>>> utangHistory() => db.rawQuery(
    'SELECT c.full_name,u.total_centavos,u.occurred_at,u.status FROM utang_transactions u JOIN customers c ON c.id=u.customer_id ORDER BY u.occurred_at DESC',
  );
  Future<List<Map<String, Object?>>> paymentHistory() => db.rawQuery(
    'SELECT c.full_name,p.amount_centavos,p.paid_at,p.status,p.payment_method,p.gcash_reference FROM utang_payments p JOIN customers c ON c.id=p.customer_id ORDER BY p.paid_at DESC',
  );
  Future<List<Map<String, Object?>>> customerLedger() => db.rawQuery(
    'SELECT c.full_name,l.entry_type,l.amount_change_centavos,l.occurred_at FROM customer_ledger_entries l JOIN customers c ON c.id=l.customer_id ORDER BY l.occurred_at DESC,l.id DESC',
  );

  Future<Map<String, Object?>> expenseSummary({
    DateTime? from,
    DateTime? to,
    int? categoryId,
  }) async {
    final clauses = ["status='POSTED'"], args = <Object?>[];
    if (from != null) {
      clauses.add('expense_datetime>=?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      clauses.add('expense_datetime<?');
      args.add(to.toUtc().toIso8601String());
    }
    if (categoryId != null) {
      clauses.add('category_id=?');
      args.add(categoryId);
    }
    return (await db.rawQuery('''SELECT COALESCE(SUM(amount_centavos),0) total,
      COUNT(*) count,COALESCE(MAX(amount_centavos),0) largest
      FROM expenses WHERE ${clauses.join(' AND ')}''', args)).single;
  }

  Future<List<Map<String, Object?>>> expensesByCategory({
    DateTime? from,
    DateTime? to,
    int? categoryId,
  }) {
    final clauses = ["status='POSTED'"], args = <Object?>[];
    if (from != null) {
      clauses.add('expense_datetime>=?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      clauses.add('expense_datetime<?');
      args.add(to.toUtc().toIso8601String());
    }
    if (categoryId != null) {
      clauses.add('category_id=?');
      args.add(categoryId);
    }
    return db.rawQuery(
      '''SELECT category_name_snapshot name,SUM(amount_centavos) total,COUNT(*) count
      FROM expenses WHERE ${clauses.join(' AND ')} GROUP BY category_name_snapshot ORDER BY total DESC''',
      args,
    );
  }

  Future<List<Map<String, Object?>>> expenseHistory() => db.rawQuery(
    '''SELECT expense_ref name,category_name_snapshot category,description,
      amount_centavos,expense_datetime,status,COALESCE(ep.payment_method,'CASH') payment_method,
      ep.gcash_reference FROM expenses e LEFT JOIN expense_payments ep ON ep.expense_id=e.id
      ORDER BY expense_datetime DESC''',
  );

  Future<List<Map<String, Object?>>> expenseCategories() => db.rawQuery(
    'SELECT id,name,is_archived FROM expense_categories ORDER BY name COLLATE NOCASE',
  );

  Future<Map<String, Object?>> gcashServiceSummary({
    DateTime? from,
    DateTime? to,
  }) {
    final clauses = <String>[
      'status=\'POSTED\'',
      'NOT EXISTS(SELECT 1 FROM gcash_service_transactions r WHERE r.reversal_of_service_id=gcash_service_transactions.id)',
    ];
    final args = <Object?>[];
    if (from != null) {
      clauses.add('created_at>=?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      clauses.add('created_at<?');
      args.add(to.toUtc().toIso8601String());
    }
    return db
        .rawQuery('''SELECT
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' THEN 1 ELSE 0 END),0) cash_in_count,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' THEN 1 ELSE 0 END),0) cash_out_count,
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' THEN principal_centavos ELSE 0 END),0) cash_in_principal,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' THEN principal_centavos ELSE 0 END),0) cash_out_principal,
      COALESCE(SUM(CASE WHEN service_type='CASH_IN' THEN fee_centavos ELSE 0 END),0) cash_in_fees,
      COALESCE(SUM(CASE WHEN service_type='CASH_OUT' THEN fee_centavos ELSE 0 END),0) cash_out_fees
      FROM gcash_service_transactions WHERE ${clauses.join(' AND ')}''', args)
        .then((rows) => rows.single);
  }
}
