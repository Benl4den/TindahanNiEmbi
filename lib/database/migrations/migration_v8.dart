import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV8 implements DatabaseMigration {
  @override
  int get version => 8;

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

  static const _sql = [
    '''CREATE TABLE IF NOT EXISTS transaction_corrections(
      id INTEGER PRIMARY KEY,
      reference TEXT NOT NULL UNIQUE,
      transaction_reversal_id INTEGER NOT NULL UNIQUE REFERENCES transaction_reversals(id) ON DELETE RESTRICT,
      entity_type TEXT NOT NULL CHECK(entity_type IN('CASH_SALE','UTANG','PAYMENT')),
      original_entity_id INTEGER NOT NULL,
      replacement_entity_id INTEGER NOT NULL,
      reason TEXT NOT NULL CHECK(length(trim(reason))>0),
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(entity_type,original_entity_id),
      UNIQUE(entity_type,replacement_entity_id),
      CHECK(original_entity_id<>replacement_entity_id)
    )''',
    'CREATE INDEX IF NOT EXISTS idx_transaction_corrections_date ON transaction_corrections(occurred_at)',
    '''CREATE TRIGGER IF NOT EXISTS transaction_corrections_no_update BEFORE UPDATE ON transaction_corrections
      BEGIN SELECT RAISE(ABORT,'CORRECTIONS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS transaction_corrections_no_delete BEFORE DELETE ON transaction_corrections
      BEGIN SELECT RAISE(ABORT,'CORRECTIONS_ARE_APPEND_ONLY'); END''',
  ];
}
