import 'package:sqflite/sqflite.dart';

class PaymentRepository {
  const PaymentRepository(this._database, {this.actorRole});
  final Database _database;
  final String? actorRole;

  Future<int> record({
    required int customerId,
    required int amountCentavos,
    String? notes,
    DateTime? paidAt,
  }) async {
    return _database.transaction(
      (txn) => recordWithExecutor(
        txn,
        customerId: customerId,
        amountCentavos: amountCentavos,
        notes: notes,
        paidAt: paidAt,
      ),
    );
  }

  Future<int> recordWithExecutor(
    DatabaseExecutor txn, {
    required int customerId,
    required int amountCentavos,
    String? notes,
    DateTime? paidAt,
  }) async {
    if (amountCentavos <= 0) throw ArgumentError.value(amountCentavos);
    final now = (paidAt ?? DateTime.now()).toUtc().toIso8601String();
    final customer = await txn.query(
      'customers',
      columns: ['full_name'],
      where: 'id=?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (customer.isEmpty) throw StateError('Customer not found.');
    final paymentId = await txn.insert('utang_payments', {
      'customer_id': customerId,
      'amount_centavos': amountCentavos,
      'status': 'POSTED',
      'notes': notes,
      'paid_at': now,
      'created_at': now,
    });
    await txn.insert('customer_ledger_entries', {
      'customer_id': customerId,
      'entry_type': 'PAYMENT',
      'amount_change_centavos': -amountCentavos,
      'payment_id': paymentId,
      'description': 'Payment #$paymentId',
      'occurred_at': now,
      'created_at': now,
    });
    await txn.insert('activity_logs', {
      'event_type': 'UTANG_PAYMENT',
      'description':
          'Payment received from ${customer.single['full_name']} — ₱${(amountCentavos / 100).toStringAsFixed(2)}',
      'actor_role': actorRole,
      'related_entity_type': 'PAYMENT',
      'related_entity_id': paymentId,
      'created_at': now,
    });
    return paymentId;
  }

  Future<int> balanceFor(int customerId) async {
    final rows = await _database.rawQuery(
      'SELECT COALESCE(SUM(amount_change_centavos), 0) AS balance '
      'FROM customer_ledger_entries WHERE customer_id = ?',
      [customerId],
    );
    return rows.single['balance']! as int;
  }
}
