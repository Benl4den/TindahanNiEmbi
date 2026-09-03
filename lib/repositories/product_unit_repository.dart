import 'package:sqflite/sqflite.dart';

import '../models/product_unit.dart';

class InvalidProductUnit implements Exception {
  const InvalidProductUnit(this.message);
  final String message;
}

class ProductUnitRepository {
  const ProductUnitRepository(this.db, {this.actorRole});
  final Database db;
  final String? actorRole;

  Future<List<PurchasePackage>> purchasePackages(int productId) async =>
      (await db.query(
        'product_purchase_packages',
        where: 'product_id=? AND is_archived=0',
        whereArgs: [productId],
        orderBy: 'is_default DESC,name COLLATE NOCASE',
      )).map(PurchasePackage.fromMap).toList(growable: false);

  Future<List<SellingOption>> sellingOptions(int productId) async =>
      (await db.query(
        'product_selling_options',
        where: 'product_id=? AND is_archived=0',
        whereArgs: [productId],
        orderBy: 'is_default DESC,name COLLATE NOCASE',
      )).map(SellingOption.fromMap).toList(growable: false);

  Future<void> configure({
    required int productId,
    required BaseUnit baseUnit,
    required List<({String name, int baseQuantity, bool isDefault})>
    purchasePackages,
    required List<
      ({String name, int baseQuantity, int priceCentavos, bool isDefault})
    >
    sellingOptions,
  }) async {
    if (purchasePackages.isEmpty ||
        sellingOptions.isEmpty ||
        purchasePackages.where((x) => x.isDefault).length != 1 ||
        sellingOptions.where((x) => x.isDefault).length != 1 ||
        purchasePackages.any(
          (x) => x.name.trim().isEmpty || x.baseQuantity <= 0,
        ) ||
        sellingOptions.any(
          (x) =>
              x.name.trim().isEmpty ||
              x.baseQuantity <= 0 ||
              x.priceCentavos < 0,
        )) {
      throw const InvalidProductUnit(
        'Enter valid packages and select one default.',
      );
    }
    await db.transaction((tx) async {
      final product = await tx.query(
        'products',
        columns: ['id'],
        where: 'id=? AND is_archived=0',
        whereArgs: [productId],
        limit: 1,
      );
      if (product.isEmpty) throw const InvalidProductUnit('Product not found.');
      final now = DateTime.now().toUtc().toIso8601String();
      await tx.update(
        'product_purchase_packages',
        {'is_archived': 1, 'is_default': 0, 'updated_at': now},
        where: 'product_id=? AND is_archived=0',
        whereArgs: [productId],
      );
      await tx.update(
        'product_selling_options',
        {'is_archived': 1, 'is_default': 0, 'updated_at': now},
        where: 'product_id=? AND is_archived=0',
        whereArgs: [productId],
      );
      await tx.update(
        'products',
        {
          'base_unit_code': baseUnit.code,
          'base_unit_label': baseUnit.label,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [productId],
      );
      for (final p in purchasePackages) {
        await tx.insert('product_purchase_packages', {
          'product_id': productId,
          'name': p.name.trim(),
          'base_quantity': p.baseQuantity,
          'is_default': p.isDefault ? 1 : 0,
          'is_archived': 0,
          'created_at': now,
          'updated_at': now,
        });
      }
      for (final o in sellingOptions) {
        await tx.insert('product_selling_options', {
          'product_id': productId,
          'name': o.name.trim(),
          'base_quantity': o.baseQuantity,
          'price_centavos': o.priceCentavos,
          'is_default': o.isDefault ? 1 : 0,
          'is_archived': 0,
          'created_at': now,
          'updated_at': now,
        });
      }
      await tx.insert('activity_logs', {
        'event_type': 'PRODUCT_UNITS_CONFIGURED',
        'description': 'Product units configured',
        'actor_role': actorRole,
        'related_entity_type': 'PRODUCT',
        'related_entity_id': productId,
        'created_at': now,
      });
    });
  }

  Future<void> receive({
    required int productId,
    required int packageId,
    required int packageCount,
    int? packageCostCentavos,
    String? notes,
  }) async {
    if (packageCount <= 0 ||
        (packageCostCentavos != null && packageCostCentavos < 0)) {
      throw const InvalidProductUnit(
        'Enter a valid received quantity and cost.',
      );
    }
    await db.transaction((tx) async {
      final rows = await tx.rawQuery(
        '''SELECT p.current_quantity,p.name,k.name package_name,k.base_quantity
        FROM products p JOIN product_purchase_packages k ON k.product_id=p.id
        WHERE p.id=? AND k.id=? AND p.is_archived=0 AND k.is_archived=0''',
        [productId, packageId],
      );
      if (rows.isEmpty) {
        throw const InvalidProductUnit('Purchase package is unavailable.');
      }
      final row = rows.single, before = row['current_quantity']! as int;
      final perPackage = row['base_quantity']! as int,
          baseQuantity = packageCount * perPackage;
      final now = DateTime.now().toUtc().toIso8601String();
      final transaction = await tx.insert('inventory_transactions', {
        'type': 'STOCK_IN',
        'notes': notes,
        'occurred_at': now,
        'created_at': now,
      });
      await tx.insert('inventory_movements', {
        'inventory_transaction_id': transaction,
        'product_id': productId,
        'quantity_change': baseQuantity,
        'quantity_before': before,
        'quantity_after': before + baseQuantity,
        'unit_cost_centavos': packageCostCentavos,
        'entered_quantity': packageCount,
        'entered_unit_snapshot': row['package_name'],
        'base_quantity_per_entered_unit': perPackage,
        'created_at': now,
      });
      await tx.insert('activity_logs', {
        'event_type': 'INVENTORY_STOCK_IN',
        'description':
            'Stock In — ${row['name']} +$packageCount ${row['package_name']}',
        'actor_role': actorRole,
        'related_entity_type': 'PRODUCT',
        'related_entity_id': productId,
        'created_at': now,
      });
    });
  }
}
