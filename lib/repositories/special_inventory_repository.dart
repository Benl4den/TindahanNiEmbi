import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
import '../services/app_refresh_controller.dart';

class InventoryGroup {
  const InventoryGroup({
    required this.id,
    required this.code,
    required this.name,
  });
  final int id;
  final String code, name;
}

class SpecialInventoryRepository {
  const SpecialInventoryRepository(this.db, {this.actorRole});
  final Database db;
  final String? actorRole;

  Future<List<InventoryGroup>> managedBrands() async =>
      (await db.query(
            'inventory_groups',
            where: "is_archived=0 AND code<>'CONSIGNMENT'",
            orderBy: "CASE code WHEN 'SELECTA' THEN 0 ELSE 1 END,name COLLATE NOCASE",
          ))
          .map(
            (x) => InventoryGroup(
              id: x['id']! as int,
              code: x['code']! as String,
              name: x['name']! as String,
            ),
          )
          .toList(growable: false);

  Future<InventoryGroup> createBrand(String value) async {
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) throw ArgumentError('Brand name is required.');
    final now = DateTime.now().toUtc().toIso8601String();
    final code = 'BRAND_${DateTime.now().microsecondsSinceEpoch}';
    final id = await db.insert('inventory_groups', {
      'code': code,
      'name': name,
      'created_at': now,
    });
    AppRefreshController.instance.dataChanged();
    return InventoryGroup(id: id, code: code, name: name);
  }

  Future<void> remove(int productId, String code) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawUpdate(
      '''UPDATE product_inventory_groups SET archived_at=?
      WHERE product_id=? AND inventory_group_id=(SELECT id FROM inventory_groups WHERE code=?)''',
      [now, productId, code],
    );
    AppRefreshController.instance.dataChanged();
  }

  Future<List<Product>> products(
    String code, {
    String query = '',
    ProductStockStatus? status,
  }) async {
    final conditions = <String>[
      'g.code=?',
      'm.archived_at IS NULL',
      'p.is_archived=0',
    ];
    final args = <Object?>[code];
    if (query.trim().isNotEmpty) {
      conditions.add('p.name LIKE ? COLLATE NOCASE');
      args.add('%${query.trim()}%');
    }
    if (status == ProductStockStatus.lowStock) {
      conditions.add(
        'p.current_quantity>0 AND p.current_quantity<=p.minimum_stock_level',
      );
    }
    if (status == ProductStockStatus.outOfStock) {
      conditions.add('p.current_quantity=0');
    }
    final rows = await db.rawQuery(
      '''SELECT p.* FROM products p
      JOIN product_inventory_groups m ON m.product_id=p.id
      JOIN inventory_groups g ON g.id=m.inventory_group_id
      WHERE ${conditions.join(' AND ')} ORDER BY p.name COLLATE NOCASE''',
      args,
    );
    return rows.map(Product.fromMap).toList(growable: false);
  }

  Future<void> assign(int productId, String code) async {
    await db.transaction((tx) async {
      final groups = await tx.query(
        'inventory_groups',
        where: 'code=? AND is_archived=0',
        whereArgs: [code],
        limit: 1,
      );
      final products = await tx.query(
        'products',
        where: 'id=? AND is_archived=0',
        whereArgs: [productId],
        limit: 1,
      );
      if (groups.isEmpty || products.isEmpty) {
        throw StateError('Product or inventory group unavailable.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final existing = await tx.query(
        'product_inventory_groups',
        where: 'product_id=? AND inventory_group_id=?',
        whereArgs: [productId, groups.single['id']],
        limit: 1,
      );
      if (existing.isEmpty) {
        await tx.insert('product_inventory_groups', {
          'product_id': productId,
          'inventory_group_id': groups.single['id'],
          'assigned_at': now,
        });
      } else {
        await tx.update(
          'product_inventory_groups',
          {'archived_at': null, 'assigned_at': now},
          where: 'id=?',
          whereArgs: [existing.single['id']],
        );
      }
      await tx.insert('activity_logs', {
        'event_type': 'SPECIAL_INVENTORY_ASSIGNED',
        'description': '${products.single['name']} assigned to $code',
        'actor_role': actorRole,
        'related_entity_type': 'PRODUCT',
        'related_entity_id': productId,
        'created_at': now,
      });
    });
    AppRefreshController.instance.dataChanged();
  }
}
