import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

class MigrationV6 implements DatabaseMigration {
  @override
  int get version => 6;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    for (final sql in _statements) {
      await db.execute(sql);
    }
    await db.insert('inventory_groups', {
      'code': 'SELECTA',
      'name': 'Selecta Products',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('inventory_groups', {
      'code': 'CONSIGNMENT',
      'name': 'Consignment',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('schema_migrations', {
      'version': version,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static const _statements = <String>[
    '''CREATE TABLE IF NOT EXISTS inventory_groups(
      id INTEGER PRIMARY KEY,
      code TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(code))>0),
      name TEXT NOT NULL CHECK(length(trim(name))>0),
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN(0,1)),
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS product_inventory_groups(
      id INTEGER PRIMARY KEY,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
      inventory_group_id INTEGER NOT NULL REFERENCES inventory_groups(id) ON DELETE RESTRICT,
      assigned_at TEXT NOT NULL,
      archived_at TEXT,
      UNIQUE(product_id, inventory_group_id)
    )''',
    '''CREATE TABLE IF NOT EXISTS consignors(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name))>0),
      contact_details TEXT,
      is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN(0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS consignment_batches(
      id INTEGER PRIMARY KEY,
      consignor_id INTEGER NOT NULL REFERENCES consignors(id) ON DELETE RESTRICT,
      product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
      inventory_movement_id INTEGER NOT NULL UNIQUE REFERENCES inventory_movements(id) ON DELETE RESTRICT,
      boxes_received INTEGER NOT NULL CHECK(boxes_received>0),
      units_per_box INTEGER NOT NULL CHECK(units_per_box>0),
      units_received INTEGER NOT NULL CHECK(units_received=boxes_received*units_per_box),
      units_allocated INTEGER NOT NULL DEFAULT 0 CHECK(units_allocated>=0 AND units_allocated<=units_received),
      units_returned INTEGER NOT NULL DEFAULT 0 CHECK(units_returned>=0 AND units_returned<=units_received-units_allocated),
      unit_cost_centavos INTEGER NOT NULL CHECK(unit_cost_centavos>=0),
      selling_price_centavos INTEGER NOT NULL CHECK(selling_price_centavos>=0),
      notes TEXT,
      received_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS consignment_allocations(
      id INTEGER PRIMARY KEY,
      batch_id INTEGER NOT NULL REFERENCES consignment_batches(id) ON DELETE RESTRICT,
      cash_sale_item_id INTEGER REFERENCES cash_sale_items(id) ON DELETE RESTRICT,
      utang_item_id INTEGER REFERENCES utang_transaction_items(id) ON DELETE RESTRICT,
      quantity INTEGER NOT NULL CHECK(quantity>0),
      unit_cost_centavos INTEGER NOT NULL CHECK(unit_cost_centavos>=0),
      selling_price_centavos INTEGER NOT NULL CHECK(selling_price_centavos>=0),
      payable_centavos INTEGER NOT NULL CHECK(payable_centavos=quantity*unit_cost_centavos),
      margin_centavos INTEGER NOT NULL CHECK(margin_centavos=quantity*(selling_price_centavos-unit_cost_centavos)),
      occurred_at TEXT NOT NULL,
      CHECK((cash_sale_item_id IS NOT NULL)+(utang_item_id IS NOT NULL)=1)
    )''',
    '''CREATE TABLE IF NOT EXISTS consignment_returns(
      id INTEGER PRIMARY KEY,
      batch_id INTEGER NOT NULL REFERENCES consignment_batches(id) ON DELETE RESTRICT,
      inventory_movement_id INTEGER NOT NULL UNIQUE REFERENCES inventory_movements(id) ON DELETE RESTRICT,
      quantity INTEGER NOT NULL CHECK(quantity>0),
      unit_cost_centavos INTEGER NOT NULL CHECK(unit_cost_centavos>=0),
      notes TEXT,
      returned_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS consignor_remittances(
      id INTEGER PRIMARY KEY,
      consignor_id INTEGER NOT NULL REFERENCES consignors(id) ON DELETE RESTRICT,
      amount_centavos INTEGER NOT NULL CHECK(amount_centavos>0),
      notes TEXT,
      remitted_at TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''',
    '''CREATE TABLE IF NOT EXISTS consignor_ledger_entries(
      id INTEGER PRIMARY KEY,
      consignor_id INTEGER NOT NULL REFERENCES consignors(id) ON DELETE RESTRICT,
      entry_type TEXT NOT NULL CHECK(entry_type IN('SALE','REMITTANCE')),
      amount_change_centavos INTEGER NOT NULL CHECK(amount_change_centavos<>0),
      allocation_id INTEGER UNIQUE REFERENCES consignment_allocations(id) ON DELETE RESTRICT,
      remittance_id INTEGER UNIQUE REFERENCES consignor_remittances(id) ON DELETE RESTRICT,
      description TEXT,
      occurred_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      CHECK((entry_type='SALE' AND amount_change_centavos>0 AND allocation_id IS NOT NULL AND remittance_id IS NULL) OR
            (entry_type='REMITTANCE' AND amount_change_centavos<0 AND remittance_id IS NOT NULL AND allocation_id IS NULL))
    )''',
    'CREATE INDEX IF NOT EXISTS idx_group_members_group ON product_inventory_groups(inventory_group_id, archived_at)',
    'CREATE INDEX IF NOT EXISTS idx_batches_product_fifo ON consignment_batches(product_id, received_at, id)',
    'CREATE INDEX IF NOT EXISTS idx_batches_consignor ON consignment_batches(consignor_id)',
    'CREATE INDEX IF NOT EXISTS idx_allocations_batch ON consignment_allocations(batch_id)',
    'CREATE INDEX IF NOT EXISTS idx_consignor_ledger ON consignor_ledger_entries(consignor_id, occurred_at, id)',
    '''CREATE TRIGGER IF NOT EXISTS consignment_allocations_no_update BEFORE UPDATE ON consignment_allocations BEGIN
      SELECT RAISE(ABORT,'CONSIGNMENT_ALLOCATIONS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS consignment_allocations_no_delete BEFORE DELETE ON consignment_allocations BEGIN
      SELECT RAISE(ABORT,'CONSIGNMENT_ALLOCATIONS_ARE_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS consignor_ledger_no_update BEFORE UPDATE ON consignor_ledger_entries BEGIN
      SELECT RAISE(ABORT,'CONSIGNOR_LEDGER_IS_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS consignor_ledger_no_delete BEFORE DELETE ON consignor_ledger_entries BEGIN
      SELECT RAISE(ABORT,'CONSIGNOR_LEDGER_IS_APPEND_ONLY'); END''',
    '''CREATE TRIGGER IF NOT EXISTS consignor_ledger_prevent_negative BEFORE INSERT ON consignor_ledger_entries
      WHEN COALESCE((SELECT SUM(amount_change_centavos) FROM consignor_ledger_entries WHERE consignor_id=NEW.consignor_id),0)+NEW.amount_change_centavos<0
      BEGIN SELECT RAISE(ABORT,'REMITTANCE_EXCEEDS_PAYABLE'); END''',
  ];
}
