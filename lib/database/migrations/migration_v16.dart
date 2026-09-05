import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV16 implements DatabaseMigration {
  @override
  int get version => 16;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE consignors ADD COLUMN default_category_id INTEGER REFERENCES categories(id) ON DELETE RESTRICT',
    );
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
