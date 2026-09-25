import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Adds Maya's independent append-only wallet history without rewriting the
/// established GCash ledger or the legacy payment-method constraints.
class MigrationV27 implements DatabaseMigration {
  @override
  int get version => 27;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS maya_service_transactions(
      id INTEGER PRIMARY KEY,
      reference TEXT NOT NULL UNIQUE,
      service_type TEXT NOT NULL CHECK(service_type IN('CASH_IN','CASH_OUT')),
      status TEXT NOT NULL CHECK(status IN('POSTED','REVERSAL')),
      principal_centavos INTEGER NOT NULL CHECK(principal_centavos>0),
      fee_centavos INTEGER NOT NULL CHECK(fee_centavos>=0),
      fee_option TEXT NOT NULL CHECK(fee_option IN('ADDED','DEDUCTED')),
      customer_total_centavos INTEGER NOT NULL CHECK(customer_total_centavos>0),
      physical_cash_change_centavos INTEGER NOT NULL CHECK(physical_cash_change_centavos<>0),
      wallet_change_centavos INTEGER NOT NULL CHECK(wallet_change_centavos<>0),
      wallet_reference TEXT,
      notes TEXT,
      created_by_name_snapshot TEXT,
      created_by_role_snapshot TEXT CHECK(created_by_role_snapshot IS NULL OR created_by_role_snapshot IN('OWNER','STAFF')),
      reversal_of_service_id INTEGER UNIQUE REFERENCES maya_service_transactions(id) ON DELETE RESTRICT,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS maya_ledger_entries(
      id INTEGER PRIMARY KEY,
      reference TEXT NOT NULL UNIQUE,
      entry_type TEXT NOT NULL CHECK(entry_type IN(
        'SALE','UTANG_PAYMENT','EXPENSE','CONSIGNOR_REMITTANCE',
        'OPENING_BALANCE','ADJUSTMENT_IN','ADJUSTMENT_OUT','REVERSAL',
        'CASH_IN_SERVICE','CASH_OUT_SERVICE','SERVICE_REVERSAL')),
      amount_change_centavos INTEGER NOT NULL CHECK(amount_change_centavos<>0),
      cash_sale_id INTEGER REFERENCES cash_sales(id) ON DELETE RESTRICT,
      utang_payment_id INTEGER REFERENCES utang_payments(id) ON DELETE RESTRICT,
      expense_id INTEGER REFERENCES expenses(id) ON DELETE RESTRICT,
      consignor_remittance_id INTEGER REFERENCES consignor_remittances(id) ON DELETE RESTRICT,
      transaction_reversal_id INTEGER REFERENCES transaction_reversals(id) ON DELETE RESTRICT,
      expense_reversal_id INTEGER REFERENCES expense_reversals(id) ON DELETE RESTRICT,
      wallet_service_transaction_id INTEGER REFERENCES maya_service_transactions(id) ON DELETE RESTRICT,
      loan_id INTEGER REFERENCES loans(id) ON DELETE RESTRICT,
      loan_payment_id INTEGER REFERENCES loan_payments(id) ON DELETE RESTRICT,
      reversal_of_entry_id INTEGER REFERENCES maya_ledger_entries(id) ON DELETE RESTRICT,
      wallet_reference TEXT,
      notes TEXT,
      actor_role TEXT CHECK(actor_role IS NULL OR actor_role IN('OWNER','STAFF')),
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''');
    for (final sql in [
      'CREATE INDEX IF NOT EXISTS idx_maya_ledger_date ON maya_ledger_entries(occurred_at DESC,id DESC)',
      'CREATE INDEX IF NOT EXISTS idx_maya_services_date ON maya_service_transactions(created_at DESC,id DESC)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_maya_sale_once ON maya_ledger_entries(cash_sale_id) WHERE cash_sale_id IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_maya_utang_once ON maya_ledger_entries(utang_payment_id) WHERE utang_payment_id IS NOT NULL AND reversal_of_entry_id IS NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_maya_expense_once ON maya_ledger_entries(expense_id) WHERE expense_id IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_maya_remittance_once ON maya_ledger_entries(consignor_remittance_id) WHERE consignor_remittance_id IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_maya_service_once ON maya_ledger_entries(wallet_service_transaction_id) WHERE wallet_service_transaction_id IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_maya_loan_once ON maya_ledger_entries(loan_id) WHERE loan_id IS NOT NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_maya_loan_payment_once ON maya_ledger_entries(loan_payment_id) WHERE loan_payment_id IS NOT NULL AND reversal_of_entry_id IS NULL',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_maya_reversal_once ON maya_ledger_entries(reversal_of_entry_id) WHERE reversal_of_entry_id IS NOT NULL',
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_maya_opening_once ON maya_ledger_entries(entry_type) WHERE entry_type='OPENING_BALANCE'",
    ]) {
      await db.execute(sql);
    }

    // Backfill only effective posted transactions. Legacy Maya rows stored
    // CASH in the constrained column and MAYA in payment_method_display.
    await db.execute('''INSERT OR IGNORE INTO maya_ledger_entries
      (reference,entry_type,amount_change_centavos,cash_sale_id,wallet_reference,occurred_at,created_at)
      SELECT 'MY-OLD-S-'||s.id,'SALE',sp.amount_centavos,s.id,sp.payment_reference,s.occurred_at,s.occurred_at
      FROM sale_payments sp JOIN cash_sales s ON s.id=sp.cash_sale_id
      WHERE sp.payment_method_display='MAYA' AND s.status='POSTED' ''');
    await db.execute(
      '''INSERT OR IGNORE INTO maya_ledger_entries
      (reference,entry_type,amount_change_centavos,utang_payment_id,wallet_reference,occurred_at,created_at)
      SELECT 'MY-OLD-U-'||p.id,'UTANG_PAYMENT',p.amount_centavos,p.id,p.payment_reference,p.paid_at,p.paid_at
      FROM utang_payments p WHERE p.payment_method_display='MAYA' AND p.status='POSTED' ''',
    );
    await db.execute('''INSERT OR IGNORE INTO maya_ledger_entries
      (reference,entry_type,amount_change_centavos,expense_id,wallet_reference,occurred_at,created_at)
      SELECT 'MY-OLD-E-'||e.id,'EXPENSE',-ep.amount_centavos,e.id,ep.payment_reference,e.expense_datetime,e.expense_datetime
      FROM expense_payments ep JOIN expenses e ON e.id=ep.expense_id
      WHERE ep.payment_method_display='MAYA' AND e.status='POSTED' ''');
    await db.execute('''INSERT OR IGNORE INTO maya_ledger_entries
      (reference,entry_type,amount_change_centavos,consignor_remittance_id,wallet_reference,occurred_at,created_at)
      SELECT 'MY-OLD-R-'||r.id,'CONSIGNOR_REMITTANCE',-r.amount_centavos,r.id,r.payment_reference,r.remitted_at,r.remitted_at
      FROM consignor_remittances r WHERE r.payment_method_display='MAYA' ''');
    await db.execute(
      '''INSERT OR IGNORE INTO maya_ledger_entries
      (reference,entry_type,amount_change_centavos,loan_id,occurred_at,created_at)
      SELECT 'MY-OLD-L-'||l.id,'ADJUSTMENT_IN',l.borrowed_amount_centavos,l.id,l.created_at,l.created_at
      FROM loans l WHERE l.source_kind='NEW' AND l.received_payment_method='MAYA' ''',
    );
    await db.execute(
      '''INSERT OR IGNORE INTO maya_ledger_entries
      (reference,entry_type,amount_change_centavos,loan_payment_id,wallet_reference,occurred_at,created_at)
      SELECT 'MY-OLD-LP-'||p.id,'ADJUSTMENT_OUT',-p.amount_centavos,p.id,p.payment_reference,p.paid_at,p.paid_at
      FROM loan_payments p WHERE p.payment_method='MAYA' AND p.status='POSTED' ''',
    );
    for (final sql in [
      "CREATE TRIGGER IF NOT EXISTS maya_ledger_no_update BEFORE UPDATE ON maya_ledger_entries BEGIN SELECT RAISE(ABORT,'MAYA_LEDGER_IS_APPEND_ONLY'); END",
      "CREATE TRIGGER IF NOT EXISTS maya_ledger_no_delete BEFORE DELETE ON maya_ledger_entries BEGIN SELECT RAISE(ABORT,'MAYA_LEDGER_IS_APPEND_ONLY'); END",
      "CREATE TRIGGER IF NOT EXISTS maya_services_no_update BEFORE UPDATE ON maya_service_transactions BEGIN SELECT RAISE(ABORT,'MAYA_SERVICES_ARE_APPEND_ONLY'); END",
      "CREATE TRIGGER IF NOT EXISTS maya_services_no_delete BEFORE DELETE ON maya_service_transactions BEGIN SELECT RAISE(ABORT,'MAYA_SERVICES_ARE_APPEND_ONLY'); END",
    ]) {
      await db.execute(sql);
    }
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
