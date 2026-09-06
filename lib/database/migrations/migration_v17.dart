import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Repairs installations whose database version advanced while one or more
/// additive consignment accounting columns were absent.
class MigrationV17 implements DatabaseMigration {
  @override
  int get version => 17;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await _ensureColumn(
      db,
      'consignment_allocations',
      'sale_revenue_centavos',
      'INTEGER CHECK(sale_revenue_centavos>=0)',
    );
    await _ensureColumn(
      db,
      'consignment_allocations',
      'actual_margin_centavos',
      'INTEGER',
    );
    await _ensureColumn(
      db,
      'consignment_allocations',
      'actual_payable_centavos',
      'INTEGER',
    );
    // Historical allocations are append-only during normal app use. Disable
    // the guard only for this controlled backfill, then restore it immediately.
    await db.execute(
      'DROP TRIGGER IF EXISTS consignment_allocations_no_update',
    );
    await db.execute('''UPDATE consignment_allocations SET
      sale_revenue_centavos=COALESCE(
        sale_revenue_centavos,
        selling_price_centavos*quantity
      ),
      actual_margin_centavos=COALESCE(actual_margin_centavos,margin_centavos),
      actual_payable_centavos=COALESCE(actual_payable_centavos,payable_centavos)
    ''');
    await db.execute(
      '''CREATE TRIGGER IF NOT EXISTS consignment_allocations_no_update
      BEFORE UPDATE ON consignment_allocations BEGIN
      SELECT RAISE(ABORT,'CONSIGNMENT_ALLOCATIONS_ARE_APPEND_ONLY'); END''',
    );
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _ensureColumn(
    DatabaseExecutor db,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }
}
