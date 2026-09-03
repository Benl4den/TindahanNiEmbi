import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Adds integer base-unit inventory and configurable purchase/sale packaging.
/// Existing products remain 1:1 pieces and existing history is not rewritten.
class MigrationV10 implements DatabaseMigration {
  @override
  int get version => 10;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    for (final sql in _sql) {
      await db.execute(sql);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      '''
      INSERT INTO product_selling_options(
        product_id,name,base_quantity,price_centavos,is_default,is_archived,created_at,updated_at)
      SELECT id,'Piece',1,selling_price_centavos,1,0,?,?
      FROM products
      WHERE NOT EXISTS(SELECT 1 FROM product_selling_options o WHERE o.product_id=products.id)
    ''',
      [now, now],
    );
    await db.rawInsert(
      '''
      INSERT INTO product_purchase_packages(
        product_id,name,base_quantity,is_default,is_archived,created_at,updated_at)
      SELECT id,'Piece',1,1,0,?,?
      FROM products
      WHERE NOT EXISTS(SELECT 1 FROM product_purchase_packages p WHERE p.product_id=products.id)
    ''',
      [now, now],
    );
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static const _sql = <String>[
    "ALTER TABLE products ADD COLUMN base_unit_code TEXT NOT NULL DEFAULT 'PIECE' CHECK(base_unit_code IN('PIECE','STICK','BOTTLE','SACHET','GRAM','MILLILITER'))",
    "ALTER TABLE products ADD COLUMN base_unit_label TEXT NOT NULL DEFAULT 'piece' CHECK(length(trim(base_unit_label))>0)",
    '''CREATE TABLE product_purchase_packages(
      id INTEGER PRIMARY KEY,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
      name TEXT NOT NULL CHECK(length(trim(name))>0),
      base_quantity INTEGER NOT NULL CHECK(base_quantity>0),
      is_default INTEGER NOT NULL DEFAULT 0 CHECK(is_default IN(0,1)),
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN(0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE product_selling_options(
      id INTEGER PRIMARY KEY,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
      name TEXT NOT NULL CHECK(length(trim(name))>0),
      base_quantity INTEGER NOT NULL CHECK(base_quantity>0),
      price_centavos INTEGER NOT NULL CHECK(price_centavos>=0),
      is_default INTEGER NOT NULL DEFAULT 0 CHECK(is_default IN(0,1)),
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN(0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    'CREATE INDEX idx_purchase_packages_product ON product_purchase_packages(product_id,is_archived)',
    'CREATE INDEX idx_selling_options_product ON product_selling_options(product_id,is_archived)',
    "CREATE UNIQUE INDEX idx_purchase_package_name_active ON product_purchase_packages(product_id,name COLLATE NOCASE) WHERE is_archived=0",
    "CREATE UNIQUE INDEX idx_selling_option_name_active ON product_selling_options(product_id,name COLLATE NOCASE) WHERE is_archived=0",
    'CREATE UNIQUE INDEX idx_purchase_package_default ON product_purchase_packages(product_id) WHERE is_default=1 AND is_archived=0',
    'CREATE UNIQUE INDEX idx_selling_option_default ON product_selling_options(product_id) WHERE is_default=1 AND is_archived=0',
    'ALTER TABLE inventory_movements ADD COLUMN entered_quantity INTEGER CHECK(entered_quantity>0)',
    'ALTER TABLE inventory_movements ADD COLUMN entered_unit_snapshot TEXT CHECK(entered_unit_snapshot IS NULL OR length(trim(entered_unit_snapshot))>0)',
    'ALTER TABLE inventory_movements ADD COLUMN base_quantity_per_entered_unit INTEGER CHECK(base_quantity_per_entered_unit>0)',
    'ALTER TABLE cash_sale_items ADD COLUMN selling_option_id INTEGER REFERENCES product_selling_options(id) ON DELETE RESTRICT',
    'ALTER TABLE cash_sale_items ADD COLUMN selling_option_name_snapshot TEXT',
    'ALTER TABLE cash_sale_items ADD COLUMN base_quantity_per_unit INTEGER NOT NULL DEFAULT 1 CHECK(base_quantity_per_unit>0)',
    'ALTER TABLE utang_transaction_items ADD COLUMN selling_option_id INTEGER REFERENCES product_selling_options(id) ON DELETE RESTRICT',
    'ALTER TABLE utang_transaction_items ADD COLUMN selling_option_name_snapshot TEXT',
    'ALTER TABLE utang_transaction_items ADD COLUMN base_quantity_per_unit INTEGER NOT NULL DEFAULT 1 CHECK(base_quantity_per_unit>0)',
  ];
}
