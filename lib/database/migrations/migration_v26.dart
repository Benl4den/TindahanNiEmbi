import 'package:sqflite/sqflite.dart';

import '../database_migration.dart';

/// Adds earlier posted sales for products that were assigned to a brand after
/// the sale. Existing frozen attributions keep their original cost snapshots.
class MigrationV26 implements DatabaseMigration {
  @override
  int get version => 26;

  @override
  Future<void> migrate(DatabaseExecutor db) async {
    await db.execute('''INSERT OR IGNORE INTO brand_sale_attributions(
      inventory_group_id,cash_sale_item_id,cost_centavos,is_estimate)
      SELECT m.inventory_group_id,i.id,
        COALESCE((SELECT SUM(COALESCE(a.actual_payable_centavos,a.payable_centavos))
          FROM consignment_allocations a WHERE a.cash_sale_item_id=i.id),
          CAST(ROUND(1.0*COALESCE(i.total_base_quantity,i.quantity)*p.purchase_price_centavos/
            COALESCE((SELECT k.base_quantity FROM product_purchase_packages k
              WHERE k.product_id=p.id AND k.is_default=1 AND k.is_archived=0 LIMIT 1),1)) AS INTEGER)),1
      FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id
      JOIN products p ON p.id=i.product_id
      JOIN product_inventory_groups m ON m.product_id=p.id AND m.archived_at IS NULL
      JOIN inventory_groups g ON g.id=m.inventory_group_id
      WHERE g.code<>'CONSIGNMENT' AND s.status='POSTED' ''');
    await db.execute('''INSERT OR IGNORE INTO brand_sale_attributions(
      inventory_group_id,utang_item_id,cost_centavos,is_estimate)
      SELECT m.inventory_group_id,i.id,
        COALESCE((SELECT SUM(COALESCE(a.actual_payable_centavos,a.payable_centavos))
          FROM consignment_allocations a WHERE a.utang_item_id=i.id),
          CAST(ROUND(1.0*COALESCE(i.total_base_quantity,i.quantity)*p.purchase_price_centavos/
            COALESCE((SELECT k.base_quantity FROM product_purchase_packages k
              WHERE k.product_id=p.id AND k.is_default=1 AND k.is_archived=0 LIMIT 1),1)) AS INTEGER)),1
      FROM utang_transaction_items i
      JOIN utang_transactions u ON u.id=i.utang_transaction_id
      JOIN products p ON p.id=i.product_id
      JOIN product_inventory_groups m ON m.product_id=p.id AND m.archived_at IS NULL
      JOIN inventory_groups g ON g.id=m.inventory_group_id
      WHERE g.code<>'CONSIGNMENT' AND u.status='POSTED'
        AND COALESCE(u.is_existing_balance,0)=0''');
    await db.execute(
      "INSERT OR IGNORE INTO schema_migrations(version,applied_at) VALUES(26,strftime('%Y-%m-%dT%H:%M:%fZ','now'))",
    );
  }
}
