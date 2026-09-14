import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV23 implements DatabaseMigration {
  @override
  int get version => 23;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    for (final table in const ['transaction_reversals', 'expense_reversals']) {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((column) => column['name'] == 'actor_name')) {
        await db.execute('ALTER TABLE $table ADD COLUMN actor_name TEXT');
      }
    }
    await db.execute(
      "INSERT OR IGNORE INTO schema_migrations(version,applied_at) VALUES(23,strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
    );
  }
}
