import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV2 implements DatabaseMigration {
  @override
  int get version => 2;
  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute(
      '''CREATE TABLE cash_sales(id INTEGER PRIMARY KEY,total_centavos INTEGER NOT NULL CHECK(total_centavos>0),status TEXT NOT NULL DEFAULT 'POSTED' CHECK(status IN('POSTED','VOIDED','REVERSED')),notes TEXT,occurred_at TEXT NOT NULL,created_at TEXT NOT NULL)''',
    );
    await db.execute(
      '''CREATE TABLE cash_sale_items(id INTEGER PRIMARY KEY,cash_sale_id INTEGER NOT NULL REFERENCES cash_sales(id) ON DELETE RESTRICT,product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,product_name_snapshot TEXT NOT NULL CHECK(length(trim(product_name_snapshot))>0),unit_price_centavos INTEGER NOT NULL CHECK(unit_price_centavos>=0),quantity INTEGER NOT NULL CHECK(quantity>0),line_total_centavos INTEGER NOT NULL CHECK(line_total_centavos=unit_price_centavos*quantity),created_at TEXT NOT NULL)''',
    );
    await db.execute(
      'CREATE INDEX idx_cash_sales_date ON cash_sales(occurred_at)',
    );
    await db.execute(
      'CREATE INDEX idx_cash_items_sale ON cash_sale_items(cash_sale_id)',
    );
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
