import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Immutable quantity/unit snapshots for converted Cash and Credit sale lines.
class MigrationV11 implements DatabaseMigration {
  @override
  int get version => 11;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    for (final table in ['cash_sale_items', 'utang_transaction_items']) {
      await _addColumn(
        db,
        table,
        'selling_quantity_value',
        'INTEGER CHECK(selling_quantity_value>0)',
      );
      await _addColumn(
        db,
        table,
        'selling_quantity_scale',
        'INTEGER CHECK(selling_quantity_scale>0)',
      );
      await _addColumn(
        db,
        table,
        'base_unit_snapshot',
        "TEXT CHECK(base_unit_snapshot IS NULL OR length(trim(base_unit_snapshot))>0)",
      );
      await _addColumn(
        db,
        table,
        'total_base_quantity',
        'INTEGER CHECK(total_base_quantity>0)',
      );
      await _addColumn(
        db,
        table,
        'selling_unit_price_centavos',
        'INTEGER CHECK(selling_unit_price_centavos>=0)',
      );
    }
    await _addColumn(
      db,
      'consignment_allocations',
      'sale_revenue_centavos',
      'INTEGER CHECK(sale_revenue_centavos>=0)',
    );
    await _addColumn(
      db,
      'consignment_allocations',
      'actual_margin_centavos',
      'INTEGER',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _addColumn(
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
