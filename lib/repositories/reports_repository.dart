import 'package:sqflite/sqflite.dart';

class SalesPeriodSummary {
  const SalesPeriodSummary(this.daily, this.weekly, this.monthly);
  final int daily, weekly, monthly;
}

class ReportsRepository {
  const ReportsRepository(this.db);
  final Database db;
  Future<List<Map<String, Object?>>> inventory() => db.rawQuery(
    'SELECT name,current_quantity,purchase_price_centavos,selling_price_centavos,current_quantity*purchase_price_centavos stock_value FROM products WHERE is_archived=0 ORDER BY name COLLATE NOCASE',
  );
  Future<List<Map<String, Object?>>> outstanding() => db.rawQuery(
    '''SELECT c.full_name, SUM(l.amount_change_centavos) balance FROM customers c JOIN customer_ledger_entries l ON l.customer_id=c.id GROUP BY c.id HAVING balance>0 ORDER BY balance DESC''',
  );
  Future<List<Map<String, Object?>>> movements({bool? outgoing}) => db.rawQuery(
    '''SELECT p.name,t.type,m.quantity_change,m.unit_cost_centavos,t.notes,t.occurred_at FROM inventory_movements m JOIN inventory_transactions t ON t.id=m.inventory_transaction_id JOIN products p ON p.id=m.product_id ${outgoing == null
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
    return SalesPeriodSummary(
      await total(day),
      await total(week),
      await total(month),
    );
  }

  Future<List<Map<String, Object?>>> frequentProducts() => db.rawQuery(
    "SELECT product_name_snapshot name,SUM(quantity) quantity FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id WHERE s.status='POSTED' GROUP BY product_name_snapshot ORDER BY quantity DESC",
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
    'SELECT c.full_name,p.amount_centavos,p.paid_at,p.status FROM utang_payments p JOIN customers c ON c.id=p.customer_id ORDER BY p.paid_at DESC',
  );
  Future<List<Map<String, Object?>>> customerLedger() => db.rawQuery(
    'SELECT c.full_name,l.entry_type,l.amount_change_centavos,l.occurred_at FROM customer_ledger_entries l JOIN customers c ON c.id=l.customer_id ORDER BY l.occurred_at DESC,l.id DESC',
  );
}
