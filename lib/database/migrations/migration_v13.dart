import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV13 implements DatabaseMigration {
  @override
  int get version => 13;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS staff_accounts(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name))>0),
      pin_hash TEXT NOT NULL,
      salt TEXT NOT NULL,
      iterations INTEGER NOT NULL CHECK(iterations>=10000),
      is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN(0,1)),
      last_login_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_staff_accounts_active_name ON staff_accounts(is_active,name COLLATE NOCASE)',
    );
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
