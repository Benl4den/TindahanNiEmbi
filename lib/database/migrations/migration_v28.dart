import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Keeps lender preferences on the lender profile, independently of loans.
class MigrationV28 implements DatabaseMigration {
  @override
  int get version => 28;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE loan_lenders ADD COLUMN collection_frequency TEXT NOT NULL DEFAULT 'DAILY'",
    );
    await db.execute(
      "ALTER TABLE loan_lenders ADD COLUMN collection_method TEXT NOT NULL DEFAULT 'COLLECTOR_VISITS'",
    );
    await db.execute('ALTER TABLE loan_lenders ADD COLUMN contact_person TEXT');
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
