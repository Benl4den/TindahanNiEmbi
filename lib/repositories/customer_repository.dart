import 'package:sqflite/sqflite.dart';

import '../models/customer.dart';

class InvalidCustomerException implements Exception {
  const InvalidCustomerException(this.message);
  final String message;
}

abstract interface class CustomerRepository {
  Future<List<Customer>> searchActive([String query = '']);
  Future<Customer> create(CustomerDraft draft);
  Future<Customer> update(int id, CustomerDraft draft);
  Future<void> archive(int id);
  Future<CustomerDetails> details(int id);
  Future<Map<String, Object?>> utangDetails(int id);
}

class SqliteCustomerRepository implements CustomerRepository {
  const SqliteCustomerRepository(this._database);
  final Database _database;

  @override
  Future<List<Customer>> searchActive([String query = '']) async {
    final q = query.trim();
    final args = q.isEmpty
        ? <Object?>[]
        : ['%${_escape(q)}%', '%${_escape(q)}%'];
    final rows = await _database.rawQuery('''
      SELECT c.*, COALESCE(SUM(l.amount_change_centavos), 0) balance_centavos
      FROM customers c LEFT JOIN customer_ledger_entries l ON l.customer_id = c.id
      WHERE c.is_archived = 0 ${q.isEmpty ? '' : "AND (c.full_name LIKE ? ESCAPE '\\' COLLATE NOCASE OR c.nickname LIKE ? ESCAPE '\\' COLLATE NOCASE)"}
      GROUP BY c.id ORDER BY CASE WHEN COALESCE(SUM(l.amount_change_centavos),0)>0 THEN 0 ELSE 1 END, c.full_name COLLATE NOCASE
    ''', args);
    return rows.map(Customer.fromMap).toList(growable: false);
  }

  @override
  Future<Customer> create(CustomerDraft draft) async {
    final values = _values(draft);
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await _database.insert('customers', {
      ...values,
      'is_archived': 0,
      'created_at': now,
      'updated_at': now,
    });
    return (await details(id)).customer;
  }

  @override
  Future<Customer> update(int id, CustomerDraft draft) async {
    final changed = await _database.update(
      'customers',
      {
        ..._values(draft),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND is_archived = 0',
      whereArgs: [id],
    );
    if (changed == 0) {
      throw const InvalidCustomerException('Customer not found.');
    }
    return (await details(id)).customer;
  }

  @override
  Future<void> archive(int id) async {
    final changed = await _database.update(
      'customers',
      {
        'is_archived': 1,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND is_archived = 0',
      whereArgs: [id],
    );
    if (changed == 0) {
      throw const InvalidCustomerException('Customer not found.');
    }
  }

  @override
  Future<CustomerDetails> details(int id) async {
    final customers = await _database.rawQuery(
      '''SELECT c.*, COALESCE(SUM(l.amount_change_centavos), 0) balance_centavos FROM customers c LEFT JOIN customer_ledger_entries l ON l.customer_id=c.id WHERE c.id=? GROUP BY c.id''',
      [id],
    );
    if (customers.isEmpty) {
      throw const InvalidCustomerException('Customer not found.');
    }
    final ledger = await _database.rawQuery(
      '''SELECT l.*, CASE WHEN l.utang_transaction_id IS NULL THEN NULL ELSE (SELECT COUNT(*) FROM utang_transaction_items i WHERE i.utang_transaction_id=l.utang_transaction_id) END item_count FROM customer_ledger_entries l WHERE l.customer_id=? ORDER BY l.occurred_at DESC, l.id DESC''',
      [id],
    );
    return CustomerDetails(
      customer: Customer.fromMap(customers.single),
      ledger: ledger.map(CustomerLedgerEntry.fromMap).toList(growable: false),
    );
  }

  @override
  Future<Map<String, Object?>> utangDetails(int id) async {
    final header = await _database.rawQuery(
      '''SELECT u.*, c.full_name FROM utang_transactions u JOIN customers c ON c.id=u.customer_id WHERE u.id=?''',
      [id],
    );
    if (header.isEmpty) throw StateError('UTANG transaction not found.');
    final items = await _database.query(
      'utang_transaction_items',
      where: 'utang_transaction_id=?',
      whereArgs: [id],
      orderBy: 'id',
    );
    return {...header.single, 'items': items};
  }

  Map<String, Object?> _values(CustomerDraft draft) {
    final name = draft.fullName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw const InvalidCustomerException('Name is required.');
    String? optional(String? value) {
      final v = value?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    return {
      'full_name': name,
      'nickname': optional(draft.nickname),
      'mobile_number': optional(draft.mobileNumber),
      'address': optional(draft.address),
      'notes': optional(draft.notes),
    };
  }

  String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
