import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Freezes brand attribution and estimated cost when an item is sold.
/// Older items can only be attributed from the membership records still
/// available at upgrade time; their cost is explicitly marked as estimated.
class MigrationV25 implements DatabaseMigration {
  @override
  int get version => 25;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    // V5 assigned UTG references before V24 introduced opening balances.
    // Assign EXU at insert time; an immutable reference cannot be renamed later.
    await db.execute('DROP TRIGGER IF EXISTS utang_assign_reference');
    await db.execute('''CREATE TRIGGER utang_assign_reference
      AFTER INSERT ON utang_transactions WHEN NEW.reference IS NULL
      BEGIN UPDATE utang_transactions SET reference=printf(
        CASE WHEN NEW.is_existing_balance=1 THEN 'EXU-%06d' ELSE 'UTG-%06d' END,
        NEW.id) WHERE id=NEW.id; END''');
    await db.execute('''CREATE TABLE IF NOT EXISTS brand_sale_attributions(
      id INTEGER PRIMARY KEY,
      inventory_group_id INTEGER NOT NULL REFERENCES inventory_groups(id) ON DELETE RESTRICT,
      cash_sale_item_id INTEGER REFERENCES cash_sale_items(id) ON DELETE RESTRICT,
      utang_item_id INTEGER REFERENCES utang_transaction_items(id) ON DELETE RESTRICT,
      cost_centavos INTEGER NOT NULL CHECK(cost_centavos>=0),
      is_estimate INTEGER NOT NULL DEFAULT 1 CHECK(is_estimate IN(0,1)),
      CHECK((cash_sale_item_id IS NOT NULL)+(utang_item_id IS NOT NULL)=1)
    )''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_brand_cash_attribution ON brand_sale_attributions(inventory_group_id,cash_sale_item_id) WHERE cash_sale_item_id IS NOT NULL',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_brand_utang_attribution ON brand_sale_attributions(inventory_group_id,utang_item_id) WHERE utang_item_id IS NOT NULL',
    );

    await db.execute('''INSERT OR IGNORE INTO brand_sale_attributions(
      inventory_group_id,cash_sale_item_id,cost_centavos,is_estimate)
      SELECT m.inventory_group_id,i.id,
        COALESCE((SELECT SUM(COALESCE(a.actual_payable_centavos,a.payable_centavos))
          FROM consignment_allocations a WHERE a.cash_sale_item_id=i.id),
          COALESCE(i.total_base_quantity,i.quantity)*p.purchase_price_centavos),1
      FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id
      JOIN products p ON p.id=i.product_id
      JOIN product_inventory_groups m ON m.product_id=p.id
      JOIN inventory_groups g ON g.id=m.inventory_group_id
      WHERE g.code<>'CONSIGNMENT' AND m.assigned_at<=s.occurred_at
        AND (m.archived_at IS NULL OR m.archived_at>s.occurred_at)''');
    await db.execute('''INSERT OR IGNORE INTO brand_sale_attributions(
      inventory_group_id,utang_item_id,cost_centavos,is_estimate)
      SELECT m.inventory_group_id,i.id,
        COALESCE((SELECT SUM(COALESCE(a.actual_payable_centavos,a.payable_centavos))
          FROM consignment_allocations a WHERE a.utang_item_id=i.id),
          COALESCE(i.total_base_quantity,i.quantity)*p.purchase_price_centavos),1
      FROM utang_transaction_items i JOIN utang_transactions u ON u.id=i.utang_transaction_id
      JOIN products p ON p.id=i.product_id
      JOIN product_inventory_groups m ON m.product_id=p.id
      JOIN inventory_groups g ON g.id=m.inventory_group_id
      WHERE g.code<>'CONSIGNMENT' AND m.assigned_at<=u.occurred_at
        AND (m.archived_at IS NULL OR m.archived_at>u.occurred_at)''');
    await db.execute(
      "INSERT OR IGNORE INTO schema_migrations(version,applied_at) VALUES(25,strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
    );
  }
}
