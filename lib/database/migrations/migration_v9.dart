import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV9 implements DatabaseMigration {
  @override
  int get version => 9;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    for (final sql in _sql) {
      await db.execute(sql);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    for (final name in _defaultCategories) {
      await db.insert('expense_categories', {
        'name': name,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static const _defaultCategories = [
    'Electricity',
    'Water',
    'Rent',
    'Store Supplies',
    'Transportation',
    'Delivery',
    'Maintenance',
    'Repairs',
    'Packaging',
    'Staff Meal',
    'Miscellaneous',
    'Other',
  ];

  static const _sql = [
    '''CREATE TABLE IF NOT EXISTS expense_categories(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name))>0),
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN(0,1)),
      created_at TEXT NOT NULL,
      archived_at TEXT
    )''',
    '''CREATE TABLE IF NOT EXISTS expenses(
      id INTEGER PRIMARY KEY,
      expense_ref TEXT NOT NULL UNIQUE,
      category_id INTEGER NOT NULL REFERENCES expense_categories(id) ON DELETE RESTRICT,
      category_name_snapshot TEXT NOT NULL CHECK(length(trim(category_name_snapshot))>0),
      amount_centavos INTEGER NOT NULL CHECK(amount_centavos>0),
      description TEXT NOT NULL CHECK(length(trim(description))>0),
      notes TEXT,
      reference_no TEXT,
      payment_source TEXT NOT NULL DEFAULT 'CASH' CHECK(payment_source IN('CASH')),
      expense_datetime TEXT NOT NULL,
      created_at TEXT NOT NULL,
      created_by_role TEXT NOT NULL CHECK(created_by_role IN('OWNER','STAFF')),
      status TEXT NOT NULL DEFAULT 'POSTED' CHECK(status IN('POSTED','CORRECTED','REVERSED'))
    )''',
    '''CREATE TABLE IF NOT EXISTS expense_reversals(
      id INTEGER PRIMARY KEY,
      expense_id INTEGER NOT NULL UNIQUE REFERENCES expenses(id) ON DELETE RESTRICT,
      reason TEXT NOT NULL CHECK(length(trim(reason))>0),
      occurred_at TEXT NOT NULL,
      actor_role TEXT NOT NULL CHECK(actor_role='OWNER')
    )''',
    '''CREATE TABLE IF NOT EXISTS expense_corrections(
      id INTEGER PRIMARY KEY,
      original_expense_id INTEGER NOT NULL UNIQUE REFERENCES expenses(id) ON DELETE RESTRICT,
      replacement_expense_id INTEGER NOT NULL UNIQUE REFERENCES expenses(id) ON DELETE RESTRICT,
      expense_reversal_id INTEGER NOT NULL UNIQUE REFERENCES expense_reversals(id) ON DELETE RESTRICT,
      reason TEXT NOT NULL CHECK(length(trim(reason))>0),
      occurred_at TEXT NOT NULL,
      CHECK(original_expense_id<>replacement_expense_id)
    )''',
    'CREATE INDEX IF NOT EXISTS idx_expenses_datetime ON expenses(expense_datetime)',
    'CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category_id,expense_datetime)',
    '''CREATE TRIGGER IF NOT EXISTS expenses_guard_update BEFORE UPDATE ON expenses
      WHEN NOT(OLD.status='POSTED' AND NEW.status IN('CORRECTED','REVERSED')
        AND OLD.id=NEW.id AND OLD.expense_ref=NEW.expense_ref AND OLD.category_id=NEW.category_id
        AND OLD.category_name_snapshot=NEW.category_name_snapshot AND OLD.amount_centavos=NEW.amount_centavos
        AND OLD.description=NEW.description AND OLD.notes IS NEW.notes AND OLD.reference_no IS NEW.reference_no
        AND OLD.payment_source=NEW.payment_source AND OLD.expense_datetime=NEW.expense_datetime
        AND OLD.created_at=NEW.created_at AND OLD.created_by_role=NEW.created_by_role)
      BEGIN SELECT RAISE(ABORT,'POSTED_EXPENSES_ARE_IMMUTABLE'); END''',
    '''CREATE TRIGGER IF NOT EXISTS expenses_no_delete BEFORE DELETE ON expenses
      BEGIN SELECT RAISE(ABORT,'EXPENSES_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS expense_reversals_no_update BEFORE UPDATE ON expense_reversals
      BEGIN SELECT RAISE(ABORT,'EXPENSE_REVERSALS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS expense_reversals_no_delete BEFORE DELETE ON expense_reversals
      BEGIN SELECT RAISE(ABORT,'EXPENSE_REVERSALS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS expense_corrections_no_update BEFORE UPDATE ON expense_corrections
      BEGIN SELECT RAISE(ABORT,'EXPENSE_CORRECTIONS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS expense_corrections_no_delete BEFORE DELETE ON expense_corrections
      BEGIN SELECT RAISE(ABORT,'EXPENSE_CORRECTIONS_ARE_APPEND_ONLY'); END''',
  ];
}
