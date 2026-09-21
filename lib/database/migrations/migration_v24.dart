import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Adds the first offline-friendly business-management extensions.  The
/// payment display columns deliberately preserve the old CASH/GCASH CHECK
/// constraints, so an upgraded backup stays readable by the existing ledger.
class MigrationV24 implements DatabaseMigration {
  @override
  int get version => 24;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    Future<void> add(String table, String column, String definition) async {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      if (!info.any((row) => row['name'] == column)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $definition');
      }
    }

    await add(
      'utang_transactions',
      'is_existing_balance',
      'is_existing_balance INTEGER NOT NULL DEFAULT 0 CHECK(is_existing_balance IN(0,1))',
    );
    for (final table in const [
      'sale_payments',
      'utang_payments',
      'expense_payments',
      'consignor_remittances',
    ]) {
      await add(table, 'payment_method_display', 'payment_method_display TEXT');
      await add(table, 'payment_reference', 'payment_reference TEXT');
    }
    await add(
      'gcash_ledger_entries',
      'loan_id',
      'loan_id INTEGER REFERENCES loans(id) ON DELETE RESTRICT',
    );
    await add(
      'gcash_ledger_entries',
      'loan_payment_id',
      'loan_payment_id INTEGER REFERENCES loan_payments(id) ON DELETE RESTRICT',
    );

    await db.execute('''CREATE TABLE IF NOT EXISTS supplier_contacts(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL CHECK(length(trim(name))>0),
      contact_number TEXT,
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN(0,1)),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, archived_at TEXT
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_supplier_contacts_name ON supplier_contacts(name COLLATE NOCASE)',
    );

    await db.execute('''CREATE TABLE IF NOT EXISTS loan_lenders(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL CHECK(length(trim(name))>0),
      contact_number TEXT, notes TEXT,
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN(0,1)),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS loans(
      id INTEGER PRIMARY KEY,
      lender_id INTEGER NOT NULL REFERENCES loan_lenders(id) ON DELETE RESTRICT,
      reference TEXT UNIQUE,
      source_kind TEXT NOT NULL CHECK(source_kind IN('NEW','EXISTING')),
      borrowed_amount_centavos INTEGER NOT NULL CHECK(borrowed_amount_centavos>0),
      agreed_repayment_centavos INTEGER NOT NULL CHECK(agreed_repayment_centavos>0),
      start_date TEXT NOT NULL, first_collection_date TEXT,
      collection_frequency TEXT NOT NULL CHECK(collection_frequency IN('DAILY','WEEKLY')),
      scheduled_amount_centavos INTEGER CHECK(scheduled_amount_centavos>0),
      received_payment_method TEXT, received_payment_reference TEXT,
      notes TEXT, status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK(status IN('ACTIVE','COMPLETED')),
      created_at TEXT NOT NULL, created_by TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS loan_payments(
      id INTEGER PRIMARY KEY,
      loan_id INTEGER NOT NULL REFERENCES loans(id) ON DELETE RESTRICT,
      reference TEXT UNIQUE,
      amount_centavos INTEGER NOT NULL CHECK(amount_centavos>0),
      payment_method TEXT NOT NULL CHECK(payment_method IN('CASH','GCASH','MAYA')),
      payment_reference TEXT, notes TEXT,
      paid_at TEXT NOT NULL, created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'POSTED' CHECK(status IN('POSTED','REVERSED')),
      reversed_at TEXT, reversal_reason TEXT, reversed_by TEXT
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loans_lender_status ON loans(lender_id,status,start_date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_loan_payments_loan_date ON loan_payments(loan_id,paid_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_utang_existing_balance ON utang_transactions(customer_id,is_existing_balance,status)',
    );
    await db.execute(
      "INSERT OR IGNORE INTO schema_migrations(version,applied_at) VALUES(24,strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
    );
  }
}
