import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV7 implements DatabaseMigration {
  @override
  int get version => 7;
  @override
  Future<void> migrate(DatabaseExecutor db) async {
    for (final sql in _sql) {
      await db.execute(sql);
    }
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static const _sql = <String>[
    '''CREATE TABLE IF NOT EXISTS transaction_reversals(
      id INTEGER PRIMARY KEY, reference TEXT NOT NULL UNIQUE,
      cash_sale_id INTEGER UNIQUE REFERENCES cash_sales(id) ON DELETE RESTRICT,
      utang_transaction_id INTEGER UNIQUE REFERENCES utang_transactions(id) ON DELETE RESTRICT,
      payment_id INTEGER UNIQUE REFERENCES utang_payments(id) ON DELETE RESTRICT,
      reason TEXT NOT NULL CHECK(length(trim(reason))>0), occurred_at TEXT NOT NULL, created_at TEXT NOT NULL,
      CHECK((cash_sale_id IS NOT NULL)+(utang_transaction_id IS NOT NULL)+(payment_id IS NOT NULL)=1)
    )''',
    '''CREATE TABLE IF NOT EXISTS consignment_allocation_reversals(
      id INTEGER PRIMARY KEY, transaction_reversal_id INTEGER NOT NULL REFERENCES transaction_reversals(id) ON DELETE RESTRICT,
      allocation_id INTEGER NOT NULL UNIQUE REFERENCES consignment_allocations(id) ON DELETE RESTRICT,
      consignor_id INTEGER NOT NULL REFERENCES consignors(id) ON DELETE RESTRICT,
      quantity INTEGER NOT NULL CHECK(quantity>0), payable_change_centavos INTEGER NOT NULL CHECK(payable_change_centavos<0),
      margin_change_centavos INTEGER NOT NULL, occurred_at TEXT NOT NULL, created_at TEXT NOT NULL
    )''',
    'CREATE INDEX IF NOT EXISTS idx_reversals_date ON transaction_reversals(occurred_at)',
    'CREATE INDEX IF NOT EXISTS idx_allocation_reversals_consignor ON consignment_allocation_reversals(consignor_id,occurred_at)',
    '''CREATE TRIGGER IF NOT EXISTS transaction_reversals_no_update BEFORE UPDATE ON transaction_reversals BEGIN SELECT RAISE(ABORT,'REVERSALS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS transaction_reversals_no_delete BEFORE DELETE ON transaction_reversals BEGIN SELECT RAISE(ABORT,'REVERSALS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS allocation_reversals_no_update BEFORE UPDATE ON consignment_allocation_reversals BEGIN SELECT RAISE(ABORT,'REVERSALS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS allocation_reversals_no_delete BEFORE DELETE ON consignment_allocation_reversals BEGIN SELECT RAISE(ABORT,'REVERSALS_ARE_APPEND_ONLY'); END''',
  ];
}
