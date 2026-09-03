import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Repairs current default prices only. Immutable transaction snapshots are untouched.
class MigrationV12 implements DatabaseMigration {
  @override
  int get version => 12;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.rawUpdate(
      '''
      UPDATE product_selling_options
      SET price_centavos=(SELECT p.selling_price_centavos FROM products p
                          WHERE p.id=product_selling_options.product_id),
          updated_at=?
      WHERE is_default=1 AND is_archived=0 AND price_centavos=0
        AND (SELECT p.selling_price_centavos FROM products p
             WHERE p.id=product_selling_options.product_id)>0
    ''',
      [DateTime.now().toUtc().toIso8601String()],
    );
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
