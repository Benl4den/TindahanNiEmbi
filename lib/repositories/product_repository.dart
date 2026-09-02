import 'package:sqflite/sqflite.dart';

import '../models/product.dart';

class InvalidProductException implements Exception {
  const InvalidProductException(this.message);
  final String message;
}

abstract interface class ProductRepository {
  Future<List<Product>> searchActive([String query = '']);
  Future<Product> create(ProductDraft draft);
  Future<Product> update(Product product);
  Future<void> archive(int id);
}

class SqliteProductRepository implements ProductRepository {
  const SqliteProductRepository(this._database, {this.actorRole});
  final Database _database;
  final String? actorRole;

  @override
  Future<List<Product>> searchActive([String query = '']) async {
    return searchAll(query: query, archiveFilter: 'ACTIVE');
  }

  Future<List<Product>> searchAll({
    String query = '',
    String archiveFilter = 'ALL',
    int? categoryId,
    String? groupCode,
  }) async {
    final normalized = query.trim();
    final clauses = <String>[], args = <Object?>[];
    if (archiveFilter == 'ACTIVE') clauses.add('p.is_archived=0');
    if (archiveFilter == 'ARCHIVED') clauses.add('p.is_archived=1');
    if (normalized.isNotEmpty) {
      clauses.add("p.name LIKE ? ESCAPE '\\' COLLATE NOCASE");
      args.add('%${_escapeLike(normalized)}%');
    }
    if (categoryId != null) {
      clauses.add('p.category_id=?');
      args.add(categoryId);
    }
    if (groupCode != null) {
      clauses.add(
        'EXISTS(SELECT 1 FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id WHERE m.product_id=p.id AND m.archived_at IS NULL AND g.code=?)',
      );
      args.add(groupCode);
    }
    final rows = await _database.rawQuery(
      'SELECT p.* FROM products p${clauses.isEmpty ? '' : ' WHERE ${clauses.join(' AND ')}'} ORDER BY p.name COLLATE NOCASE',
      args,
    );
    return rows.map(Product.fromMap).toList(growable: false);
  }

  Future<Map<int, List<String>>> inventoryGroups(
    Iterable<int> productIds,
  ) async {
    final ids = productIds.toList();
    if (ids.isEmpty) return {};
    final rows = await _database.rawQuery(
      '''SELECT m.product_id,g.name FROM product_inventory_groups m JOIN inventory_groups g ON g.id=m.inventory_group_id WHERE m.archived_at IS NULL AND m.product_id IN(${List.filled(ids.length, '?').join(',')})''',
      ids,
    );
    final result = <int, List<String>>{};
    for (final row in rows) {
      result
          .putIfAbsent(row['product_id']! as int, () => [])
          .add(row['name']! as String);
    }
    return result;
  }

  @override
  Future<Product> create(ProductDraft draft) async {
    final name = _validate(draft);
    return _database.transaction((txn) async {
      await _requireActiveCategory(txn, draft.categoryId);
      final now = DateTime.now().toUtc().toIso8601String();
      final productId = await txn.insert('products', {
        'category_id': draft.categoryId,
        'name': name,
        'photo_path': draft.photoPath.trim(),
        'purchase_price_centavos': draft.purchasePriceCentavos,
        'selling_price_centavos': draft.sellingPriceCentavos,
        'current_quantity': 0,
        'minimum_stock_level': draft.minimumStockLevel,
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
      });
      if (draft.startingQuantity > 0) {
        final transactionId = await txn.insert('inventory_transactions', {
          'type': 'INITIAL_STOCK',
          'reference_number': 'PRODUCT-$productId',
          'notes': 'Starting stock',
          'occurred_at': now,
          'created_at': now,
        });
        await txn.insert('inventory_movements', {
          'inventory_transaction_id': transactionId,
          'product_id': productId,
          'quantity_change': draft.startingQuantity,
          'quantity_before': 0,
          'quantity_after': draft.startingQuantity,
          'unit_cost_centavos': draft.purchasePriceCentavos,
          'created_at': now,
        });
      }
      await txn.insert('activity_logs', {
        'event_type': 'PRODUCT_CREATED',
        'description': 'Product created — $name',
        'actor_role': actorRole,
        'related_entity_type': 'PRODUCT',
        'related_entity_id': productId,
        'created_at': now,
      });
      return Product.fromMap(
        (await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        )).single,
      );
    });
  }

  @override
  Future<Product> update(Product product) async {
    final name = _normalizeName(product.name);
    _nonnegative([
      product.purchasePriceCentavos,
      product.sellingPriceCentavos,
      product.minimumStockLevel,
    ]);
    if (product.photoPath.trim().isEmpty) {
      throw const InvalidProductException('Product photo is required.');
    }
    return _database.transaction((txn) async {
      await _requireActiveCategory(txn, product.categoryId);
      final now = DateTime.now().toUtc().toIso8601String();
      final changed = await txn.update(
        'products',
        {
          'category_id': product.categoryId,
          'name': name,
          'photo_path': product.photoPath,
          'purchase_price_centavos': product.purchasePriceCentavos,
          'selling_price_centavos': product.sellingPriceCentavos,
          'minimum_stock_level': product.minimumStockLevel,
          'updated_at': now,
        },
        where: 'id = ? AND is_archived = 0',
        whereArgs: [product.id],
      );
      if (changed == 0) {
        throw const InvalidProductException('Product not found.');
      }
      await txn.insert('activity_logs', {
        'event_type': 'PRODUCT_EDITED',
        'description': 'Product edited — $name',
        'actor_role': actorRole,
        'related_entity_type': 'PRODUCT',
        'related_entity_id': product.id,
        'created_at': now,
      });
      return Product.fromMap(
        (await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [product.id],
        )).single,
      );
    });
  }

  @override
  Future<void> archive(int id) async {
    await _database.transaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['name'],
        where: 'id=? AND is_archived=0',
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        throw const InvalidProductException('Product not found.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.update(
        'products',
        {'is_archived': 1, 'updated_at': now},
        where: 'id=?',
        whereArgs: [id],
      );
      await txn.insert('activity_logs', {
        'event_type': 'PRODUCT_ARCHIVED',
        'description': 'Product archived — ${rows.single['name']}',
        'actor_role': actorRole,
        'related_entity_type': 'PRODUCT',
        'related_entity_id': id,
        'created_at': now,
      });
    });
  }

  String _validate(ProductDraft draft) {
    final name = _normalizeName(draft.name);
    if (draft.photoPath.trim().isEmpty) {
      throw const InvalidProductException('Product photo is required.');
    }
    _nonnegative([
      draft.purchasePriceCentavos,
      draft.sellingPriceCentavos,
      draft.startingQuantity,
      draft.minimumStockLevel,
    ]);
    return name;
  }

  String _normalizeName(String value) {
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) {
      throw const InvalidProductException('Product name is required.');
    }
    return name;
  }

  void _nonnegative(Iterable<int> values) {
    if (values.any((value) => value < 0)) {
      throw const InvalidProductException('Values cannot be negative.');
    }
  }

  Future<void> _requireActiveCategory(DatabaseExecutor db, int id) async {
    final rows = await db.query(
      'categories',
      columns: ['id'],
      where: 'id = ? AND is_archived = 0',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const InvalidProductException('Active category is required.');
    }
  }

  String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
