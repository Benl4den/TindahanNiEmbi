import 'package:sqflite/sqflite.dart';

class BrandAnalyticsRepository {
  const BrandAnalyticsRepository(this.db);
  final Database db;

  /// Called in the sale transaction, after consignment allocation has been
  /// posted, so later brand assignments and price edits cannot rewrite sales.
  static Future<void> recordSaleItem(
    DatabaseExecutor tx, {
    required int productId,
    required int baseQuantity,
    required int unitCostCentavos,
    int? cashSaleItemId,
    int? utangItemId,
  }) async {
    if ((cashSaleItemId == null) == (utangItemId == null)) {
      throw ArgumentError('Exactly one sale item is required.');
    }
    final allocation = await tx.rawQuery(
      '''SELECT SUM(COALESCE(actual_payable_centavos,payable_centavos)) cost
      FROM consignment_allocations WHERE ${cashSaleItemId == null ? 'utang_item_id' : 'cash_sale_item_id'}=?''',
      [cashSaleItemId ?? utangItemId],
    );
    final consignmentCost = allocation.single['cost'] as int?;
    final packages = await tx.rawQuery(
      '''SELECT base_quantity FROM product_purchase_packages
      WHERE product_id=? AND is_default=1 AND is_archived=0 LIMIT 1''',
      [productId],
    );
    final packageQuantity = packages.isEmpty
        ? 1
        : (packages.single['base_quantity']! as int);
    final estimatedCost =
        (baseQuantity * unitCostCentavos + packageQuantity ~/ 2) ~/
        packageQuantity;
    final memberships = await tx.rawQuery(
      '''SELECT m.inventory_group_id FROM product_inventory_groups m
      JOIN inventory_groups g ON g.id=m.inventory_group_id
      WHERE m.product_id=? AND m.archived_at IS NULL AND g.code<>'CONSIGNMENT' ''',
      [productId],
    );
    for (final membership in memberships) {
      await tx.insert('brand_sale_attributions', {
        'inventory_group_id': membership['inventory_group_id'],
        'cash_sale_item_id': cashSaleItemId,
        'utang_item_id': utangItemId,
        'cost_centavos': consignmentCost ?? estimatedCost,
        'is_estimate': consignmentCost == null ? 1 : 0,
      });
    }
  }

  Future<Map<String, Object?>> summary(
    String groupCode, {
    DateTime? from,
    DateTime? to,
  }) async {
    final conditions = <String>["g.code=?", "s.status='POSTED'"],
        args = <Object?>[groupCode];
    if (from != null) {
      conditions.add('s.occurred_at>=?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      conditions.add('s.occurred_at<?');
      args.add(to.toUtc().toIso8601String());
    }
    final cash = await db.rawQuery(
      '''SELECT COALESCE(SUM(i.line_total_centavos),0) sales,COALESCE(SUM(COALESCE(i.total_base_quantity,i.quantity)),0) units,
      COALESCE(SUM(a.cost_centavos),0) cost,COALESCE(SUM(a.is_estimate),0) estimates
      FROM brand_sale_attributions a JOIN cash_sale_items i ON i.id=a.cash_sale_item_id
      JOIN cash_sales s ON s.id=i.cash_sale_id
      JOIN inventory_groups g ON g.id=a.inventory_group_id
      WHERE ${conditions.join(' AND ')}''',
      args,
    );
    final utangConditions = conditions
        .map((x) => x.replaceAll('s.', 'u.'))
        .toList();
    final utang = await db.rawQuery(
      '''SELECT COALESCE(SUM(i.line_total_centavos),0) sales,COALESCE(SUM(COALESCE(i.total_base_quantity,i.quantity)),0) units,
      COALESCE(SUM(a.cost_centavos),0) cost,COALESCE(SUM(a.is_estimate),0) estimates
      FROM brand_sale_attributions a JOIN utang_transaction_items i ON i.id=a.utang_item_id
      JOIN utang_transactions u ON u.id=i.utang_transaction_id
      JOIN inventory_groups g ON g.id=a.inventory_group_id
      WHERE ${utangConditions.join(' AND ')}''',
      args,
    );
    final a = cash.single, b = utang.single;
    final sales = (a['sales']! as int) + (b['sales']! as int),
        cost = (a['cost']! as int) + (b['cost']! as int);
    return {
      'sales': sales,
      'units': (a['units']! as int) + (b['units']! as int),
      'cost': cost,
      'profit': sales - cost,
      'estimatedItems': (a['estimates']! as int) + (b['estimates']! as int),
    };
  }

  Future<List<Map<String, Object?>>> products(String groupCode) => db.rawQuery(
    '''SELECT p.id,p.name,p.current_quantity,p.purchase_price_centavos,p.selling_price_centavos,p.photo_path,
    CASE WHEN p.current_quantity=0 THEN 'Out of Stock' WHEN p.current_quantity<=p.minimum_stock_level THEN 'Low Stock' ELSE 'In Stock' END stock_status
    FROM products p JOIN product_inventory_groups m ON m.product_id=p.id AND m.archived_at IS NULL JOIN inventory_groups g ON g.id=m.inventory_group_id
    WHERE g.code=? AND p.is_archived=0 ORDER BY p.name COLLATE NOCASE''',
    [groupCode],
  );
}
