import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV4 implements DatabaseMigration {
  @override
  int get version => 4;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE activity_logs (
      id INTEGER PRIMARY KEY,
      event_type TEXT NOT NULL,
      description TEXT NOT NULL,
      actor_role TEXT CHECK(actor_role IN ('OWNER','STAFF') OR actor_role IS NULL),
      related_entity_type TEXT,
      related_entity_id INTEGER,
      created_at TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX idx_activity_logs_created_at ON activity_logs(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_activity_logs_event_type ON activity_logs(event_type)',
    );
    await db.execute(
      "CREATE TRIGGER activity_logs_no_update BEFORE UPDATE ON activity_logs BEGIN SELECT RAISE(ABORT, 'Activity logs are append-only'); END",
    );
    await db.execute(
      "CREATE TRIGGER activity_logs_no_delete BEFORE DELETE ON activity_logs BEGIN SELECT RAISE(ABORT, 'Activity logs are append-only'); END",
    );
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
