import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV5 implements DatabaseMigration {
  @override
  int get version => 5;
  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE cash_sales ADD COLUMN reference TEXT');
    await db.execute("UPDATE cash_sales SET reference=printf('SALE-%06d', id)");
    await db.execute(
      'CREATE UNIQUE INDEX idx_cash_sales_reference ON cash_sales(reference)',
    );
    await db.execute(
      "CREATE TRIGGER cash_sales_assign_reference AFTER INSERT ON cash_sales WHEN NEW.reference IS NULL BEGIN UPDATE cash_sales SET reference=printf('SALE-%06d',NEW.id) WHERE id=NEW.id; END",
    );
    await db.execute(
      "CREATE TRIGGER cash_sales_reference_immutable BEFORE UPDATE OF reference ON cash_sales WHEN OLD.reference IS NOT NULL AND NEW.reference IS NOT OLD.reference BEGIN SELECT RAISE(ABORT,'Sale reference is immutable'); END",
    );
    await db.execute(
      'ALTER TABLE utang_transactions ADD COLUMN reference TEXT',
    );
    await db.execute(
      "UPDATE utang_transactions SET reference=printf('UTG-%06d', id)",
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_utang_transactions_reference ON utang_transactions(reference)',
    );
    await db.execute(
      "CREATE TRIGGER utang_assign_reference AFTER INSERT ON utang_transactions WHEN NEW.reference IS NULL BEGIN UPDATE utang_transactions SET reference=printf('UTG-%06d',NEW.id) WHERE id=NEW.id; END",
    );
    await db.execute(
      "CREATE TRIGGER utang_reference_immutable BEFORE UPDATE OF reference ON utang_transactions WHEN OLD.reference IS NOT NULL AND NEW.reference IS NOT OLD.reference BEGIN SELECT RAISE(ABORT,'UTANG reference is immutable'); END",
    );
    await db.execute('''CREATE TABLE app_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    ) WITHOUT ROWID''');
    await db.insert('app_settings', {
      'key': 'auto_lock_minutes',
      'value': '0',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
