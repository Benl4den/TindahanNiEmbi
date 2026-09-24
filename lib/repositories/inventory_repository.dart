import 'package:sqflite/sqflite.dart';

import '../models/inventory_movement.dart';
import '../models/product.dart';
import '../services/app_refresh_controller.dart';

class InvalidInventoryOperation implements Exception {
  const InvalidInventoryOperation(this.message);
  final String message;
}

class OwnedInventoryProductValue {
  const OwnedInventoryProductValue({
    required this.productId,
    required this.currentStockCostCentavos,
    required this.potentialSalesValueCentavos,
    this.hasIncompletePurchaseHistory = false,
  });

  final int productId;
  final bool hasIncompletePurchaseHistory;
  final int currentStockCostCentavos;
  final int potentialSalesValueCentavos;
  int get potentialGrossProfitCentavos =>
      potentialSalesValueCentavos - currentStockCostCentavos;
}

class OwnedInventorySummary {
  const OwnedInventorySummary({
    required this.inventoryCostCentavos,
    required this.potentialSalesValueCentavos,
    this.incompleteHistoryProductCount = 0,
  });

  final int inventoryCostCentavos;
  final int incompleteHistoryProductCount;
  final int potentialSalesValueCentavos;
  int get potentialGrossProfitCentavos =>
      potentialSalesValueCentavos - inventoryCostCentavos;
}

class OwnedInventoryHealth {
  const OwnedInventoryHealth({
    required this.productIds,
    required this.activeProducts,
    required this.lowStock,
    required this.outOfStock,
    required this.noRecentSales,
  });

  final Set<int> productIds;
  final int activeProducts;
  final int lowStock;
  final int outOfStock;
  final int noRecentSales;
}

class InventoryRepository {
  const InventoryRepository(this._database, {this.actorRole});
  final Database _database;
  Database get db => _database;
  final String? actorRole;

  Future<List<Product>> current({ProductStockStatus? status}) async {
    var where = 'is_archived = 0';
    if (status == ProductStockStatus.outOfStock) {
      where += ' AND current_quantity = 0';
    }
    if (status == ProductStockStatus.lowStock) where += ' AND current_quantity > 0 AND current_quantity <= minimum_stock_level';
    final rows = await _database.query(
      'products',
      where: where,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Product.fromMap).toList(growable: false);
  }

  Future<int> inventoryValueCentavos() async {
    return (await ownedSummary()).inventoryCostCentavos;
  }

  /// Operational ownership and stock status; does not read financial totals.
  Future<OwnedInventoryHealth> ownedHealth({
    bool includeRecentSales = false,
  }) async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 30))
        .toIso8601String();
    final rows = await _database.rawQuery(
      '''SELECT p.id, p.current_quantity, p.minimum_stock_level,
      ${includeRecentSales ? '''CASE WHEN EXISTS(
        SELECT 1 FROM cash_sale_items i JOIN cash_sales s ON s.id=i.cash_sale_id
        WHERE i.product_id=p.id AND s.status='POSTED' AND s.occurred_at>=?
      ) OR EXISTS(
        SELECT 1 FROM utang_transaction_items i JOIN utang_transactions s ON s.id=i.utang_transaction_id
        WHERE i.product_id=p.id AND s.status='POSTED' AND s.occurred_at>=?
      ) THEN 1 ELSE 0 END''' : '0'} AS recently_sold
      FROM products p WHERE p.is_archived=0 AND NOT EXISTS(
        SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id
        WHERE m.product_id=p.id AND m.archived_at IS NULL AND g.code='CONSIGNMENT')''',
      includeRecentSales ? [cutoff, cutoff] : [],
    );
    var active = 0;
    var low = 0;
    var out = 0;
    var noSales = 0;
    for (final row in rows) {
      final quantity = row['current_quantity'] as int;
      if (quantity == 0) {
        out++;
      } else {
        active++;
        if (quantity <= (row['minimum_stock_level'] as int)) low++;
        if (includeRecentSales && row['recently_sold'] == 0) noSales++;
      }
    }
    return OwnedInventoryHealth(
      productIds: {for (final row in rows) row['id'] as int},
      activeProducts: active,
      lowStock: low,
      outOfStock: out,
      noRecentSales: noSales,
    );
  }

  Future<OwnedInventorySummary> ownedSummary() async {
    final row = (await _database.rawQuery(
      '''SELECT
      COALESCE(SUM((p.current_quantity * p.purchase_price_centavos +
        COALESCE((SELECT k.base_quantity FROM product_purchase_packages k WHERE k.product_id=p.id AND k.is_default=1 AND k.is_archived=0 LIMIT 1),1)/2) /
        COALESCE((SELECT k.base_quantity FROM product_purchase_packages k WHERE k.product_id=p.id AND k.is_default=1 AND k.is_archived=0 LIMIT 1),1)),0) inventory_cost,
      COALESCE(SUM(p.current_quantity * p.selling_price_centavos),0) potential_sales
      FROM products p WHERE p.is_archived=0 AND NOT EXISTS(
        SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id
        WHERE m.product_id=p.id AND m.archived_at IS NULL AND g.code='CONSIGNMENT')''',
    )).single;
    return OwnedInventorySummary(
      inventoryCostCentavos: row['inventory_cost']! as int,
      potentialSalesValueCentavos: row['potential_sales']! as int,
      incompleteHistoryProductCount: (await ownedProductValues()).values
          .where((v) => v.hasIncompletePurchaseHistory)
          .length,
    );
  }

  Future<Map<int, OwnedInventoryProductValue>> ownedProductValues() async {
    final rows = await _database.rawQuery(
      '''SELECT p.id,
      EXISTS(SELECT 1 FROM inventory_movements m JOIN inventory_transactions t ON t.id=m.inventory_transaction_id
        WHERE m.product_id=p.id AND t.type IN('INITIAL_STOCK','STOCK_IN')
          AND m.quantity_change>0 AND m.unit_cost_centavos IS NULL) incomplete_history,
      (p.current_quantity * p.purchase_price_centavos +
        COALESCE((SELECT k.base_quantity FROM product_purchase_packages k WHERE k.product_id=p.id AND k.is_default=1 AND k.is_archived=0 LIMIT 1),1)/2) /
        COALESCE((SELECT k.base_quantity FROM product_purchase_packages k WHERE k.product_id=p.id AND k.is_default=1 AND k.is_archived=0 LIMIT 1),1) AS stock_cost,
      p.current_quantity * p.selling_price_centavos AS potential_sales
      FROM products p WHERE p.is_archived=0 AND NOT EXISTS(
        SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id
        WHERE m.product_id=p.id AND m.archived_at IS NULL AND g.code='CONSIGNMENT')''',
    );
    return {
      for (final row in rows)
        row['id']! as int: OwnedInventoryProductValue(
          productId: row['id']! as int,
          hasIncompletePurchaseHistory: row['incomplete_history'] == 1,
          currentStockCostCentavos: row['stock_cost']! as int,
          potentialSalesValueCentavos: row['potential_sales']! as int,
        ),
    };
  }

  Future<void> stockIn({
    required int productId,
    required int quantity,
    int? unitCostCentavos,
    String? notes,
  }) => _post(
    productId: productId,
    quantityChange: quantity,
    type: 'STOCK_IN',
    unitCostCentavos: unitCostCentavos,
    notes: notes,
  );

  Future<void> adjust({
    required int productId,
    required int quantityChange,
    required String reason,
    int? expectedCurrentQuantity,
  }) {
    if (reason.trim().isEmpty) {
      throw const InvalidInventoryOperation('Reason is required.');
    }
    return _post(
      productId: productId,
      quantityChange: quantityChange,
      type: quantityChange > 0 ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT',
      notes: reason.trim(),
      expectedCurrentQuantity: expectedCurrentQuantity,
    );
  }

  Future<void> _post({
    required int productId,
    required int quantityChange,
    required String type,
    int? unitCostCentavos,
    String? notes,
    int? expectedCurrentQuantity,
  }) async {
    if (quantityChange == 0 ||
        (type == 'STOCK_IN' && quantityChange < 0) ||
        (unitCostCentavos != null && unitCostCentavos < 0)) {
      throw const InvalidInventoryOperation('Invalid inventory values.');
    }
    await _database.transaction((txn) async {
      final products = await txn.query(
        'products',
        where: 'id = ? AND is_archived = 0',
        whereArgs: [productId],
        limit: 1,
      );
      if (products.isEmpty) {
        throw const InvalidInventoryOperation('Product not found.');
      }
      if (type == 'STOCK_IN' || type.startsWith('ADJUSTMENT_')) {
        final consigned = await txn.rawQuery(
          '''SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id
             WHERE m.product_id=? AND m.archived_at IS NULL AND g.code='CONSIGNMENT' LIMIT 1''',
          [productId],
        );
        if (consigned.isNotEmpty) {
          throw const InvalidInventoryOperation(
            'Use Consignment to manage supplier-owned stock.',
          );
        }
      }
      final before = products.single['current_quantity']! as int;
      if (expectedCurrentQuantity != null &&
          before != expectedCurrentQuantity) {
        throw const InvalidInventoryOperation(
          'Stock changed since this form opened. Close it and try again.',
        );
      }
      final after = before + quantityChange;
      if (after < 0) {
        throw const InvalidInventoryOperation('Insufficient stock.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final transactionId = await txn.insert('inventory_transactions', {
        'type': type,
        'notes': notes,
        'occurred_at': now,
        'created_at': now,
      });
      await txn.insert('inventory_movements', {
        'inventory_transaction_id': transactionId,
        'product_id': productId,
        'quantity_change': quantityChange,
        'quantity_before': before,
        'quantity_after': after,
        'unit_cost_centavos': unitCostCentavos,
        'created_at': now,
      });
      final name = products.single['name'];
      final action = type == 'STOCK_IN' ? 'Stock In' : 'Inventory adjusted';
      await txn.insert('activity_logs', {
        'event_type': type == 'STOCK_IN'
            ? 'INVENTORY_STOCK_IN'
            : 'INVENTORY_ADJUSTMENT',
        'description':
            '$action — $name ${quantityChange > 0 ? '+' : ''}$quantityChange',
        'actor_role': actorRole,
        'related_entity_type': 'PRODUCT',
        'related_entity_id': productId,
        'created_at': now,
      });
    });
    AppRefreshController.instance.dataChanged();
  }

  Future<List<InventoryMovement>> history() async {
    final rows = await _database.rawQuery(
      '''SELECT m.id, p.name product_name,p.base_unit_code,p.base_unit_label,
      t.type,m.quantity_change,m.quantity_before,m.quantity_after,t.notes,t.occurred_at
      FROM inventory_movements m JOIN products p ON p.id=m.product_id
      JOIN inventory_transactions t ON t.id=m.inventory_transaction_id
      ORDER BY t.occurred_at DESC,m.id DESC''',
    );
    return rows.map(InventoryMovement.fromMap).toList(growable: false);
  }
}
