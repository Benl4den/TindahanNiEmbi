import 'package:sqflite/sqflite.dart';

import '../models/inventory_movement.dart';
import '../models/product.dart';

class InvalidInventoryOperation implements Exception {
  const InvalidInventoryOperation(this.message);
  final String message;
}

class InventoryRepository {
  const InventoryRepository(this._database, {this.actorRole});
  final Database _database;
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
    final rows = await _database.rawQuery(
      'SELECT COALESCE(SUM(current_quantity * purchase_price_centavos), 0) value FROM products WHERE is_archived = 0',
    );
    return rows.single['value']! as int;
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
  }) {
    if (reason.trim().isEmpty) {
      throw const InvalidInventoryOperation('Reason is required.');
    }
    return _post(
      productId: productId,
      quantityChange: quantityChange,
      type: quantityChange > 0 ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT',
      notes: reason.trim(),
    );
  }

  Future<void> _post({
    required int productId,
    required int quantityChange,
    required String type,
    int? unitCostCentavos,
    String? notes,
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
      final before = products.single['current_quantity']! as int;
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
  }

  Future<List<InventoryMovement>> history() async {
    final rows = await _database.rawQuery(
      '''SELECT m.id, p.name product_name, t.type, m.quantity_change, m.quantity_before, m.quantity_after, t.notes, t.occurred_at FROM inventory_movements m JOIN products p ON p.id=m.product_id JOIN inventory_transactions t ON t.id=m.inventory_transaction_id ORDER BY t.occurred_at DESC, m.id DESC''',
    );
    return rows.map(InventoryMovement.fromMap).toList(growable: false);
  }
}
