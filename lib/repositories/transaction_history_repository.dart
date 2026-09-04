import 'package:sqflite/sqflite.dart';

class TransactionHistoryEntry {
  const TransactionHistoryEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.amountCentavos,
    required this.occurredAt,
    required this.status,
  });
  final int id, amountCentavos;
  final String type, title, status;
  final DateTime occurredAt;
}

class TransactionHistoryRepository {
  const TransactionHistoryRepository(this.db);
  final Database db;

  Future<List<TransactionHistoryEntry>> recent({
    String type = 'ALL',
    int limit = 500,
  }) async {
    final rows = await db.rawQuery(
      '''SELECT * FROM (
      SELECT id,'CASH' type,'Cash Sale' title,total_centavos amount,occurred_at occurred,status FROM cash_sales
      UNION ALL SELECT u.id,'UTANG','UTANG • '||c.full_name,u.total_centavos,u.occurred_at,u.status FROM utang_transactions u JOIN customers c ON c.id=u.customer_id
      UNION ALL SELECT p.id,'PAYMENT','Payment • '||c.full_name,p.amount_centavos,p.paid_at,p.status FROM utang_payments p JOIN customers c ON c.id=p.customer_id
      UNION ALL SELECT id,'EXPENSE',description,amount_centavos,expense_datetime,status FROM expenses
      UNION ALL SELECT b.id,'CONSIGNMENT','Received • '||p.name,b.units_received*b.unit_cost_centavos,b.received_at,'POSTED' FROM consignment_batches b JOIN products p ON p.id=b.product_id
    ) WHERE (?='ALL' OR type=?) ORDER BY occurred DESC LIMIT ?''',
      [type, type, limit],
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
          ),
        )
        .toList(growable: false);
  }

  Future<Map<String, Object?>> details(TransactionHistoryEntry entry) async {
    switch (entry.type) {
      case 'CASH':
        final header = (await db.query(
          'cash_sales',
          where: 'id=?',
          whereArgs: [entry.id],
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
        return (await db.query(
          'expenses',
          where: 'id=?',
          whereArgs: [entry.id],
        )).single;
      case 'CONSIGNMENT':
        return (await db.rawQuery(
          '''SELECT b.*,p.name product_name,c.name consignor_name
          FROM consignment_batches b JOIN products p ON p.id=b.product_id JOIN consignors c ON c.id=b.consignor_id WHERE b.id=?''',
          [entry.id],
        )).single;
      default:
        throw StateError('Transaction type is unavailable.');
    }
  }
}
