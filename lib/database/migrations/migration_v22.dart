import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Stores owner-confirmed Daily Closing summaries. The JSON payload keeps the
/// numbers shown at closing time immutable even if a later correction is made.
class MigrationV22 implements DatabaseMigration {
  @override
  int get version => 22;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_closing_snapshots(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        closing_date TEXT NOT NULL UNIQUE,
        summary_json TEXT NOT NULL,
        closed_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      "INSERT OR IGNORE INTO schema_migrations(version,applied_at) VALUES(22,strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
    );
  }
}
