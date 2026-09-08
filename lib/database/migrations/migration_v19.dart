import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Adds immutable GCash cash-in/cash-out service records.  The ledger is
/// rebuilt only to extend its checked source/type vocabulary; V18 rows are
/// copied unchanged before the old table is removed.
class MigrationV19 implements DatabaseMigration {
  @override
  int get version => 19;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    const nowExpression = "strftime('%Y-%m-%dT%H:%M:%fZ','now')";
    await db.execute('''CREATE TABLE IF NOT EXISTS gcash_service_transactions(
      id INTEGER PRIMARY KEY,
      reference TEXT NOT NULL UNIQUE,
      service_type TEXT NOT NULL CHECK(service_type IN('CASH_IN','CASH_OUT')),
      status TEXT NOT NULL DEFAULT 'POSTED' CHECK(status IN('POSTED','REVERSED','REVERSAL')),
      principal_centavos INTEGER NOT NULL CHECK(principal_centavos>0),
      fee_centavos INTEGER NOT NULL CHECK(fee_centavos>=0),
      customer_total_centavos INTEGER NOT NULL CHECK(customer_total_centavos>0),
      physical_cash_change_centavos INTEGER NOT NULL CHECK(physical_cash_change_centavos<>0),
      gcash_change_centavos INTEGER NOT NULL CHECK(gcash_change_centavos<>0),
      gcash_reference TEXT,
      notes TEXT,
      created_by_staff_id INTEGER REFERENCES staff_accounts(id) ON DELETE RESTRICT,
      created_by_name_snapshot TEXT,
      created_by_role_snapshot TEXT CHECK(created_by_role_snapshot IS NULL OR created_by_role_snapshot IN('OWNER','STAFF')),
      reversal_of_service_id INTEGER UNIQUE REFERENCES gcash_service_transactions(id) ON DELETE RESTRICT,
      correction_of_service_id INTEGER REFERENCES gcash_service_transactions(id) ON DELETE RESTRICT,
      created_at TEXT NOT NULL,
      CHECK(customer_total_centavos=principal_centavos+fee_centavos),
      CHECK(gcash_reference IS NULL OR length(trim(gcash_reference))>0)
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gcash_services_date ON gcash_service_transactions(created_at DESC,id DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_gcash_services_type ON gcash_service_transactions(service_type,status,created_at DESC)',
    );

    final columns = await db.rawQuery(
      'PRAGMA table_info(gcash_ledger_entries)',
    );
    if (!columns.any((row) => row['name'] == 'gcash_service_transaction_id')) {
      await _rebuildLedger(db);
    }
    for (final sql in _guards) {
      await db.execute(sql);
    }
    await db.execute(
      "INSERT OR IGNORE INTO schema_migrations(version,applied_at) VALUES(19,$nowExpression)",
    );
  }

  Future<void> _rebuildLedger(DatabaseExecutor db) async {
    await db.execute('DROP TRIGGER IF EXISTS gcash_ledger_no_update');
    await db.execute('DROP TRIGGER IF EXISTS gcash_ledger_no_delete');
    await db.execute(
      'ALTER TABLE gcash_ledger_entries RENAME TO gcash_ledger_entries_v18',
    );
    await db.execute(_ledgerTable);
    await db.execute('''INSERT INTO gcash_ledger_entries(
      id,reference,entry_type,amount_change_centavos,cash_sale_id,utang_payment_id,
      expense_id,consignor_remittance_id,transaction_reversal_id,expense_reversal_id,
      reversal_of_entry_id,gcash_reference,notes,actor_role,occurred_at,created_at)
      SELECT id,reference,entry_type,amount_change_centavos,cash_sale_id,utang_payment_id,
      expense_id,consignor_remittance_id,transaction_reversal_id,expense_reversal_id,
      reversal_of_entry_id,gcash_reference,notes,actor_role,occurred_at,created_at
      FROM gcash_ledger_entries_v18''');
    await db.execute('DROP TABLE gcash_ledger_entries_v18');
    for (final sql in _indexes) {
      await db.execute(sql);
    }
  }

  static const _ledgerTable = '''CREATE TABLE gcash_ledger_entries(
    id INTEGER PRIMARY KEY,
    reference TEXT NOT NULL UNIQUE,
    entry_type TEXT NOT NULL CHECK(entry_type IN(
      'SALE','UTANG_PAYMENT','EXPENSE','CONSIGNOR_REMITTANCE','OPENING_BALANCE',
      'ADJUSTMENT_IN','ADJUSTMENT_OUT','REVERSAL','CASH_IN_SERVICE','CASH_OUT_SERVICE','SERVICE_REVERSAL')),
    amount_change_centavos INTEGER NOT NULL CHECK(amount_change_centavos<>0),
    cash_sale_id INTEGER REFERENCES cash_sales(id) ON DELETE RESTRICT,
    utang_payment_id INTEGER REFERENCES utang_payments(id) ON DELETE RESTRICT,
    expense_id INTEGER REFERENCES expenses(id) ON DELETE RESTRICT,
    consignor_remittance_id INTEGER REFERENCES consignor_remittances(id) ON DELETE RESTRICT,
    transaction_reversal_id INTEGER REFERENCES transaction_reversals(id) ON DELETE RESTRICT,
    expense_reversal_id INTEGER REFERENCES expense_reversals(id) ON DELETE RESTRICT,
    gcash_service_transaction_id INTEGER REFERENCES gcash_service_transactions(id) ON DELETE RESTRICT,
    reversal_of_entry_id INTEGER REFERENCES gcash_ledger_entries(id) ON DELETE RESTRICT,
    gcash_reference TEXT, notes TEXT,
    actor_role TEXT CHECK(actor_role IS NULL OR actor_role IN('OWNER','STAFF')),
    occurred_at TEXT NOT NULL, created_at TEXT NOT NULL,
    CHECK(gcash_reference IS NULL OR length(trim(gcash_reference))>0),
    CHECK((cash_sale_id IS NOT NULL)+(utang_payment_id IS NOT NULL)+(expense_id IS NOT NULL)+
      (consignor_remittance_id IS NOT NULL)+(transaction_reversal_id IS NOT NULL)+
      (expense_reversal_id IS NOT NULL)+(gcash_service_transaction_id IS NOT NULL)<=1)
  )''';
  static const _indexes = <String>[
    'CREATE INDEX IF NOT EXISTS idx_gcash_ledger_date ON gcash_ledger_entries(occurred_at DESC,id DESC)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_sale_once ON gcash_ledger_entries(cash_sale_id) WHERE cash_sale_id IS NOT NULL',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_utang_payment_once ON gcash_ledger_entries(utang_payment_id) WHERE utang_payment_id IS NOT NULL',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_expense_once ON gcash_ledger_entries(expense_id) WHERE expense_id IS NOT NULL',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_remittance_once ON gcash_ledger_entries(consignor_remittance_id) WHERE consignor_remittance_id IS NOT NULL',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_service_once ON gcash_ledger_entries(gcash_service_transaction_id) WHERE gcash_service_transaction_id IS NOT NULL',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_reversal_once ON gcash_ledger_entries(reversal_of_entry_id) WHERE reversal_of_entry_id IS NOT NULL',
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_gcash_opening_once ON gcash_ledger_entries(entry_type) WHERE entry_type='OPENING_BALANCE'",
  ];
  static const _guards = <String>[
    '''CREATE TRIGGER IF NOT EXISTS gcash_ledger_no_update BEFORE UPDATE ON gcash_ledger_entries
      BEGIN SELECT RAISE(ABORT,'GCASH_LEDGER_IS_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS gcash_ledger_no_delete BEFORE DELETE ON gcash_ledger_entries
      BEGIN SELECT RAISE(ABORT,'GCASH_LEDGER_IS_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS gcash_services_no_update BEFORE UPDATE ON gcash_service_transactions
      BEGIN SELECT RAISE(ABORT,'GCASH_SERVICES_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS gcash_services_no_delete BEFORE DELETE ON gcash_service_transactions
      BEGIN SELECT RAISE(ABORT,'GCASH_SERVICES_ARE_APPEND_ONLY'); END''',
  ];
}
