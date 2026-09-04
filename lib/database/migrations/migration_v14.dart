import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV14 implements DatabaseMigration {
  @override
  int get version => 14;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS active_sale_draft(
      id INTEGER PRIMARY KEY CHECK(id=1),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS active_sale_draft_items(
      id INTEGER PRIMARY KEY,
      draft_id INTEGER NOT NULL DEFAULT 1 REFERENCES active_sale_draft(id) ON DELETE CASCADE,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
      selling_option_id INTEGER,
      selling_option_name TEXT NOT NULL,
      quantity_value INTEGER NOT NULL CHECK(quantity_value>0),
      quantity_scale INTEGER NOT NULL CHECK(quantity_scale>0),
      base_quantity_per_unit INTEGER NOT NULL CHECK(base_quantity_per_unit>0),
      unit_price_centavos INTEGER NOT NULL CHECK(unit_price_centavos>0),
      created_at TEXT NOT NULL,
      UNIQUE(draft_id, product_id, selling_option_id)
    )''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_active_sale_draft_product ON active_sale_draft_items(product_id)',
    );
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }
}
