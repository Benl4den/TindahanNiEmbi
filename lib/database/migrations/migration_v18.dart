import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Adds authoritative Cash/GCash payment records and an append-only GCash
/// ledger without rewriting any V1-V17 financial or inventory history.
class MigrationV18 implements DatabaseMigration {
  @override
  int get version => 18;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await _addColumn(
      db,
      'utang_payments',
      'payment_method',
      "TEXT NOT NULL DEFAULT 'CASH' CHECK(payment_method IN('CASH','GCASH'))",
    );
    await _addColumn(db, 'utang_payments', 'gcash_reference', 'TEXT');
    await _addColumn(
      db,
      'consignor_remittances',
      'payment_method',
      "TEXT NOT NULL DEFAULT 'CASH' CHECK(payment_method IN('CASH','GCASH'))",
    );
    await _addColumn(db, 'consignor_remittances', 'gcash_reference', 'TEXT');

    for (final sql in _tablesAndIndexes) {
      await db.execute(sql);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      '''INSERT OR IGNORE INTO sale_payments(
        cash_sale_id,payment_method,amount_centavos,created_at)
      SELECT id,'CASH',total_centavos,? FROM cash_sales''',
      [now],
    );
    await db.rawInsert(
      '''INSERT OR IGNORE INTO expense_payments(
        expense_id,payment_method,amount_centavos,created_at)
      SELECT id,'CASH',amount_centavos,? FROM expenses''',
      [now],
    );
    for (final sql in _guards) {
      await db.execute(sql);
    }
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _addColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  static const _tablesAndIndexes = <String>[
    '''CREATE TABLE IF NOT EXISTS sale_payments(
      id INTEGER PRIMARY KEY,
      cash_sale_id INTEGER NOT NULL UNIQUE REFERENCES cash_sales(id) ON DELETE RESTRICT,
      payment_method TEXT NOT NULL CHECK(payment_method IN('CASH','GCASH')),
      amount_centavos INTEGER NOT NULL CHECK(amount_centavos>0),
      gcash_reference TEXT,
      created_at TEXT NOT NULL,
      CHECK(gcash_reference IS NULL OR length(trim(gcash_reference))>0)
    )''',
    '''CREATE TABLE IF NOT EXISTS expense_payments(
      id INTEGER PRIMARY KEY,
      expense_id INTEGER NOT NULL UNIQUE REFERENCES expenses(id) ON DELETE RESTRICT,
      payment_method TEXT NOT NULL CHECK(payment_method IN('CASH','GCASH')),
      amount_centavos INTEGER NOT NULL CHECK(amount_centavos>0),
      gcash_reference TEXT,
      created_at TEXT NOT NULL,
      CHECK(gcash_reference IS NULL OR length(trim(gcash_reference))>0)
    )''',
    '''CREATE TABLE IF NOT EXISTS gcash_ledger_entries(
      id INTEGER PRIMARY KEY,
      reference TEXT NOT NULL UNIQUE,
      entry_type TEXT NOT NULL CHECK(entry_type IN(
        'SALE','UTANG_PAYMENT','EXPENSE','CONSIGNOR_REMITTANCE',
        'OPENING_BALANCE','ADJUSTMENT_IN','ADJUSTMENT_OUT','REVERSAL')),
      amount_change_centavos INTEGER NOT NULL CHECK(amount_change_centavos<>0),
      cash_sale_id INTEGER REFERENCES cash_sales(id) ON DELETE RESTRICT,
      utang_payment_id INTEGER REFERENCES utang_payments(id) ON DELETE RESTRICT,
      expense_id INTEGER REFERENCES expenses(id) ON DELETE RESTRICT,
      consignor_remittance_id INTEGER REFERENCES consignor_remittances(id) ON DELETE RESTRICT,
      transaction_reversal_id INTEGER REFERENCES transaction_reversals(id) ON DELETE RESTRICT,
      expense_reversal_id INTEGER REFERENCES expense_reversals(id) ON DELETE RESTRICT,
      reversal_of_entry_id INTEGER REFERENCES gcash_ledger_entries(id) ON DELETE RESTRICT,
      gcash_reference TEXT,
      notes TEXT,
      actor_role TEXT CHECK(actor_role IS NULL OR actor_role IN('OWNER','STAFF')),
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK(gcash_reference IS NULL OR length(trim(gcash_reference))>0),
      CHECK(
        (cash_sale_id IS NOT NULL)+(utang_payment_id IS NOT NULL)+
        (expense_id IS NOT NULL)+(consignor_remittance_id IS NOT NULL)+
        (transaction_reversal_id IS NOT NULL)+(expense_reversal_id IS NOT NULL)<=1)
    )''',
    'CREATE INDEX IF NOT EXISTS idx_sale_payments_method ON sale_payments(payment_method,cash_sale_id)',
    'CREATE INDEX IF NOT EXISTS idx_expense_payments_method ON expense_payments(payment_method,expense_id)',
    'CREATE INDEX IF NOT EXISTS idx_gcash_ledger_date ON gcash_ledger_entries(occurred_at DESC,id DESC)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_sale_once ON gcash_ledger_entries(cash_sale_id) WHERE cash_sale_id IS NOT NULL',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_utang_payment_once ON gcash_ledger_entries(utang_payment_id) WHERE utang_payment_id IS NOT NULL',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_expense_once ON gcash_ledger_entries(expense_id) WHERE expense_id IS NOT NULL',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_remittance_once ON gcash_ledger_entries(consignor_remittance_id) WHERE consignor_remittance_id IS NOT NULL',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_reversal_once ON gcash_ledger_entries(reversal_of_entry_id) WHERE reversal_of_entry_id IS NOT NULL',
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_opening_once ON gcash_ledger_entries(entry_type) WHERE entry_type='OPENING_BALANCE'",
  ];

  static const _guards = <String>[
    '''CREATE TRIGGER IF NOT EXISTS sale_payments_no_update BEFORE UPDATE ON sale_payments
      BEGIN SELECT RAISE(ABORT,'SALE_PAYMENTS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS sale_payments_no_delete BEFORE DELETE ON sale_payments
      BEGIN SELECT RAISE(ABORT,'SALE_PAYMENTS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS expense_payments_no_update BEFORE UPDATE ON expense_payments
      BEGIN SELECT RAISE(ABORT,'EXPENSE_PAYMENTS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS expense_payments_no_delete BEFORE DELETE ON expense_payments
      BEGIN SELECT RAISE(ABORT,'EXPENSE_PAYMENTS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS gcash_ledger_no_update BEFORE UPDATE ON gcash_ledger_entries
      BEGIN SELECT RAISE(ABORT,'GCASH_LEDGER_IS_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS gcash_ledger_no_delete BEFORE DELETE ON gcash_ledger_entries
      BEGIN SELECT RAISE(ABORT,'GCASH_LEDGER_IS_APPEND_ONLY'); END''',
  ];
}
