import 'package:sqflite/sqflite.dart';

class TransactionHistoryEntry {
  const TransactionHistoryEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.amountCentavos,
    required this.occurredAt,
    required this.status,
    required this.actor,
  });
  final int id, amountCentavos;
  final String type, title, status, actor;
  final DateTime occurredAt;
}

class TransactionHistoryRepository {
  const TransactionHistoryRepository(this.db);
  final Database db;

  Future<List<TransactionHistoryEntry>> recent({
    String type = 'ALL',
    int limit = 500,
    String search = '',
  }) async {
    final rows = await db.rawQuery(
      '''SELECT * FROM (
      SELECT s.id,'CASH' type,'Sale • '||COALESCE(sp.payment_method,'CASH') title,s.total_centavos amount,s.occurred_at occurred,s.status,COALESCE(a.actor_name,CASE a.actor_role WHEN 'OWNER' THEN 'Owner' WHEN 'STAFF' THEN 'Staff' ELSE 'Not recorded' END) actor FROM cash_sales s LEFT JOIN sale_payments sp ON sp.cash_sale_id=s.id LEFT JOIN activity_logs a ON a.related_entity_type='CASH_SALE' AND a.related_entity_id=s.id
      UNION ALL SELECT u.id,'UTANG','UTANG • '||c.full_name,u.total_centavos,u.occurred_at,u.status,COALESCE(a.actor_name,CASE a.actor_role WHEN 'OWNER' THEN 'Owner' WHEN 'STAFF' THEN 'Staff' ELSE 'Not recorded' END) FROM utang_transactions u JOIN customers c ON c.id=u.customer_id LEFT JOIN activity_logs a ON a.related_entity_type='UTANG' AND a.related_entity_id=u.id
      UNION ALL SELECT p.id,'PAYMENT','UTANG Payment • '||p.payment_method||' • '||c.full_name,p.amount_centavos,p.paid_at,p.status,COALESCE(a.actor_name,CASE a.actor_role WHEN 'OWNER' THEN 'Owner' WHEN 'STAFF' THEN 'Staff' ELSE 'Not recorded' END) FROM utang_payments p JOIN customers c ON c.id=p.customer_id LEFT JOIN activity_logs a ON a.related_entity_type='PAYMENT' AND a.related_entity_id=p.id
      UNION ALL SELECT e.id,'EXPENSE',e.description||' • '||COALESCE(ep.payment_method,'CASH'),e.amount_centavos,e.expense_datetime,e.status,COALESCE(a.actor_name,CASE a.actor_role WHEN 'OWNER' THEN 'Owner' WHEN 'STAFF' THEN 'Staff' ELSE 'Not recorded' END) FROM expenses e LEFT JOIN expense_payments ep ON ep.expense_id=e.id LEFT JOIN activity_logs a ON a.related_entity_type='EXPENSE' AND a.related_entity_id=e.id
      UNION ALL SELECT g.id,'GCASH_SERVICE','GCash '||CASE WHEN g.service_type='CASH_IN' THEN 'Cash-In' ELSE 'Cash-Out' END||CASE WHEN g.status='REVERSAL' THEN ' Reversal' ELSE '' END,g.customer_total_centavos,g.created_at,g.status,COALESCE(g.created_by_name_snapshot,a.actor_name,CASE COALESCE(g.created_by_role_snapshot,a.actor_role) WHEN 'OWNER' THEN 'Owner' WHEN 'STAFF' THEN 'Staff' ELSE 'Not recorded' END) FROM gcash_service_transactions g LEFT JOIN activity_logs a ON a.related_entity_type='GCASH_SERVICE' AND a.related_entity_id=g.id
      UNION ALL SELECT b.id,'CONSIGNMENT','Received • '||p.name,b.units_received*b.unit_cost_centavos,b.received_at,'POSTED',COALESCE(a.actor_name,CASE a.actor_role WHEN 'OWNER' THEN 'Owner' WHEN 'STAFF' THEN 'Staff' ELSE 'Not recorded' END) FROM consignment_batches b JOIN products p ON p.id=b.product_id LEFT JOIN activity_logs a ON a.related_entity_type='CONSIGNMENT' AND a.related_entity_id=b.id
    ) WHERE (?='ALL' OR type=?) AND instr(lower(title),lower(?))>0 ORDER BY occurred DESC,type,id DESC LIMIT ?''',
      [type, type, search, limit],
    );
    return rows
        .map(
          (x) => TransactionHistoryEntry(
            id: x['id']! as int,
            type: x['type']! as String,
            title: x['title']! as String,
            amountCentavos: x['amount']! as int,
            occurredAt: DateTime.parse(x['occurred']! as String),
            status: x['status']! as String,
            actor: x['actor']! as String,
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, Object?>> details(TransactionHistoryEntry entry) async {
    switch (entry.type) {
      case 'CASH':
        final header = (await db.rawQuery(
          '''SELECT s.*,COALESCE(sp.payment_method,'CASH') payment_method,sp.gcash_reference
          FROM cash_sales s LEFT JOIN sale_payments sp ON sp.cash_sale_id=s.id WHERE s.id=?''',
          [entry.id],
        )).single;
        final items = await db.query(
          'cash_sale_items',
          where: 'cash_sale_id=?',
          whereArgs: [entry.id],
          orderBy: 'id',
        );
        return {...header, 'items': items};
      case 'UTANG':
        final header = (await db.rawQuery(
          'SELECT u.*,c.full_name FROM utang_transactions u JOIN customers c ON c.id=u.customer_id WHERE u.id=?',
          [entry.id],
        )).single;
        final items = await db.query(
          'utang_transaction_items',
          where: 'utang_transaction_id=?',
          whereArgs: [entry.id],
          orderBy: 'id',
        );
        return {...header, 'items': items};
      case 'PAYMENT':
        return (await db.rawQuery(
          'SELECT p.*,c.full_name FROM utang_payments p JOIN customers c ON c.id=p.customer_id WHERE p.id=?',
          [entry.id],
        )).single;
      case 'EXPENSE':
        return (await db.rawQuery(
          '''SELECT e.*,COALESCE(ep.payment_method,'CASH') payment_method,ep.gcash_reference
          FROM expenses e LEFT JOIN expense_payments ep ON ep.expense_id=e.id WHERE e.id=?''',
          [entry.id],
        )).single;
      case 'CONSIGNMENT':
        return (await db.rawQuery(
          '''SELECT b.*,p.name product_name,c.name consignor_name
          FROM consignment_batches b JOIN products p ON p.id=b.product_id JOIN consignors c ON c.id=b.consignor_id WHERE b.id=?''',
          [entry.id],
        )).single;
      case 'GCASH_SERVICE':
        return (await db.query(
          'gcash_service_transactions',
          where: 'id=?',
          whereArgs: [entry.id],
        )).single;
      default:
        throw StateError('Transaction type is unavailable.');
    }
  }
}
