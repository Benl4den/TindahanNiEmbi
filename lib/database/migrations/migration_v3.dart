import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV3 implements DatabaseMigration {
  @override
  int get version => 3;
  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute(
      """CREATE TABLE security_profiles(id INTEGER PRIMARY KEY,role TEXT NOT NULL UNIQUE CHECK(role IN('OWNER','STAFF')),pin_hash TEXT NOT NULL,salt TEXT NOT NULL,iterations INTEGER NOT NULL CHECK(iterations>=10000),created_at TEXT NOT NULL,updated_at TEXT NOT NULL)""",
    );
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
