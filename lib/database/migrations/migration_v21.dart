import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Records whether a GCash service fee was collected on top of, or deducted
/// from, the amount entered by the cashier. Existing service records used the
/// former behaviour and are therefore safely backfilled as ADDED.
class MigrationV21 implements DatabaseMigration {
  @override
  int get version => 21;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    final columns = await db.rawQuery(
      'PRAGMA table_info(gcash_service_transactions)',
    );
    if (!columns.any((x) => x['name'] == 'fee_option')) {
      await db.execute(
        "ALTER TABLE gcash_service_transactions ADD COLUMN fee_option TEXT NOT NULL DEFAULT 'ADDED' CHECK(fee_option IN('ADDED','DEDUCTED'))",
      );
    }
    await db.execute(
      "INSERT OR IGNORE INTO schema_migrations(version,applied_at) VALUES(21,strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
    );
  }
}
