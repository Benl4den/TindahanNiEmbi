import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV20 implements DatabaseMigration {
  @override
  int get version => 20;
  @override
  Future<void> migrate(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(activity_logs)');
    if (!columns.any((x) => x['name'] == 'actor_name')) {
      await db.execute('ALTER TABLE activity_logs ADD COLUMN actor_name TEXT');
    }
    await db.execute(
      "INSERT OR IGNORE INTO schema_migrations(version,applied_at) VALUES(20,strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
    );
  }
}
