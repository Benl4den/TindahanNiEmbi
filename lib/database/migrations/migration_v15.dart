import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Adds immutable receipt labels and a rational supplier-cost snapshot.
/// Existing batches remain financially identical: cost / 1 base unit.
class MigrationV15 implements DatabaseMigration {
  @override
  int get version => 15;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    for (final statement in [
      'ALTER TABLE consignment_allocations ADD COLUMN actual_payable_centavos INTEGER',
      'ALTER TABLE consignment_batches ADD COLUMN supplier_cost_centavos INTEGER',
      'ALTER TABLE consignment_batches ADD COLUMN supplier_cost_basis_quantity INTEGER',
      'ALTER TABLE consignment_batches ADD COLUMN package_name TEXT',
      'ALTER TABLE consignment_batches ADD COLUMN package_count INTEGER',
      'ALTER TABLE consignment_batches ADD COLUMN base_quantity_per_package INTEGER',
      'ALTER TABLE consignment_batches ADD COLUMN base_unit_label TEXT',
      'ALTER TABLE consignment_batches ADD COLUMN price_unit_name TEXT',
      'ALTER TABLE consignment_batches ADD COLUMN price_unit_base_quantity INTEGER',
    ]) {
      try {
        await db.execute(statement);
      } on DatabaseException catch (error) {
        if (!error.toString().toLowerCase().contains('duplicate column')) {
          rethrow;
        }
      }
    }
    await db.execute('''UPDATE consignment_batches SET
      supplier_cost_centavos=COALESCE(supplier_cost_centavos,unit_cost_centavos),
      supplier_cost_basis_quantity=COALESCE(supplier_cost_basis_quantity,1),
      package_count=COALESCE(package_count,boxes_received),
      base_quantity_per_package=COALESCE(base_quantity_per_package,units_per_box),
      price_unit_base_quantity=COALESCE(price_unit_base_quantity,1)''');
    await db.execute(
      'DROP TRIGGER IF EXISTS consignment_allocations_no_update',
    );
    await db.execute(
      '''UPDATE consignment_allocations SET
      actual_payable_centavos=COALESCE(actual_payable_centavos,payable_centavos)''',
    );
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
}
