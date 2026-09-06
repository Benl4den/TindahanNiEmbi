import 'package:sqflite/sqflite.dart';

import '../models/consignment.dart';
import '../models/product.dart';
import '../models/product_unit.dart';
import '../services/app_refresh_controller.dart';
import 'product_unit_repository.dart';

class InvalidConsignmentOperation implements Exception {
  const InvalidConsignmentOperation(this.message);
  final String message;
}

class ConsignmentRepository {
  const ConsignmentRepository(this.db, {this.actorRole});
  final Database db;
  final String? actorRole;

  /// Read the product's saved configuration, never infer it from its category.
  Future<ProductUnitConfiguration> deliveryConfiguration(int productId) async {
    final rows = await db.query(
      'products',
      columns: ['base_unit_code'],
      where: 'id=? AND is_archived=0',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const InvalidConsignmentOperation('Active product is required.');
    }
    final units = ProductUnitRepository(db);
    final packages = await units.purchasePackages(productId);
    final options = await units.sellingOptions(productId);
    if (packages.where((p) => p.isDefault).length != 1 ||
        options.where((p) => p.isDefault).length != 1) {
      throw const InvalidConsignmentOperation(
        'Complete this product’s units and packaging before receiving a delivery.',
      );
    }
    return ProductUnitConfiguration(
      baseUnit: BaseUnit.values.singleWhere(
        (u) => u.code == rows.single['base_unit_code'],
      ),
      purchasePackages: packages
          .map(
            (p) => PurchasePackageDraft(
              name: p.name,
              baseQuantity: p.baseQuantity,
              isDefault: p.isDefault,
            ),
          )
          .toList(),
      sellingOptions: options
          .map(
            (p) => SellingOptionDraft(
              name: p.name,
              baseQuantity: p.baseQuantity,
              priceCentavos: p.priceCentavos,
              isDefault: p.isDefault,
            ),
          )
          .toList(),
    );
  }

  Future<List<Consignor>> consignors({bool activeOnly = true}) async =>
      (await db.query(
        'consignors',
        where: activeOnly ? 'is_archived=0' : null,
        orderBy: 'name COLLATE NOCASE',
      )).map(Consignor.fromMap).toList();

  Future<Map<int, int>> payableByConsignor() async {
    final rows = await db.rawQuery('''SELECT c.id,COALESCE((SELECT SUM(l.amount_change_centavos) FROM consignor_ledger_entries l WHERE l.consignor_id=c.id),0)+COALESCE((SELECT SUM(r.payable_change_centavos) FROM consignment_allocation_reversals r WHERE r.consignor_id=c.id),0) payable
         FROM consignors c WHERE c.is_archived=0''');
    return {for (final row in rows) row['id']! as int: row['payable']! as int};
  }

  Future<int> createConsignor(
    String name, {
    String? contactDetails,
    int? defaultCategoryId,
  }) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) {
      throw const InvalidConsignmentOperation('Consignor name is required.');
    }
    if (defaultCategoryId != null) {
      await _requireActiveCategory(db, defaultCategoryId);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      return await db.insert('consignors', {
        'name': clean,
        'contact_details': contactDetails?.trim(),
        'default_category_id': defaultCategoryId,
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const InvalidConsignmentOperation(
          'A consignor with this name already exists.',
        );
      }
      throw const InvalidConsignmentOperation(
        'Could not save the consignor. Please try again.',
      );
    }
  }

  Future<void> archiveConsignor(int id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final changed = await db.update(
      'consignors',
      {'is_archived': 1, 'updated_at': now},
      where: 'id=? AND is_archived=0',
      whereArgs: [id],
    );
    if (changed == 0) {
      throw const InvalidConsignmentOperation('Consignor not found.');
    }
  }

  Future<void> updateConsignor(
    int id, {
    required String name,
    String? contactDetails,
    int? defaultCategoryId,
  }) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) {
      throw const InvalidConsignmentOperation(
        'Company or consignor name is required.',
      );
    }
    if (defaultCategoryId != null) {
      await _requireActiveCategory(db, defaultCategoryId);
    }
    try {
      final changed = await db.update(
        'consignors',
        {
          'name': clean,
          'contact_details': contactDetails?.trim(),
          'default_category_id': defaultCategoryId,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=? AND is_archived=0',
        whereArgs: [id],
      );
      if (changed == 0) {
        throw const InvalidConsignmentOperation('Consignor not found.');
      }
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw const InvalidConsignmentOperation(
          'A consignor with this name already exists.',
        );
      }
      rethrow;
    }
  }

  Future<int> receive(ConsignmentReceiptDraft draft) async {
    if (draft.boxes <= 0 ||
        draft.unitsPerBox <= 0 ||
        draft.supplierCostBasisQuantity <= 0 ||
        draft.unitCostCentavos < 0 ||
        draft.sellingPriceCentavos <= 0) {
      throw const InvalidConsignmentOperation('Invalid receipt values.');
    }
    return AppRefreshController.instance.after(
      db.transaction((tx) => _receiveWith(tx, draft)),
    );
  }

  Future<int> receiveNewProduct({
    required ProductDraft product,
    required int consignorId,
    required int boxes,
    required int unitsPerBox,
    required int unitCostCentavos,
    required int sellingPriceCentavos,
    int supplierCostBasisQuantity = 1,
    String? packageName,
    String? baseUnitLabel,
    String? priceUnitName,
    String? notes,
  }) => AppRefreshController.instance.after(
    db.transaction((tx) async {
      final name = product.name.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.isEmpty ||
          product.photoPath.trim().isEmpty ||
          product.purchasePriceCentavos < 0 ||
          product.minimumStockLevel < 0) {
        throw const InvalidConsignmentOperation(
          'Valid product details are required.',
        );
      }
      final category = await tx.query(
        'categories',
        where: 'id=? AND is_archived=0',
        whereArgs: [product.categoryId],
        limit: 1,
      );
      if (category.isEmpty) {
        throw const InvalidConsignmentOperation('Active category is required.');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final units =
          product.unitConfiguration ??
          ProductUnitPreset.forCategory('', sellingPriceCentavos);
      final synchronizedSales = units.sellingOptions
          .map(
            (x) => SellingOptionDraft(
              name: x.name,
              baseQuantity: x.baseQuantity,
              priceCentavos: x.isDefault
                  ? sellingPriceCentavos
                  : x.priceCentavos,
              isDefault: x.isDefault,
            ),
          )
          .toList();
      final productId = await tx.insert('products', {
        'category_id': product.categoryId,
        'name': name,
        'photo_path': product.photoPath.trim(),
        'purchase_price_centavos': product.purchasePriceCentavos,
        'selling_price_centavos': sellingPriceCentavos,
        'current_quantity': 0,
        'minimum_stock_level': product.minimumStockLevel,
        'is_archived': 0,
        'created_at': now,
        'updated_at': now,
        'base_unit_code': units.baseUnit.code,
        'base_unit_label': units.baseUnit.label,
      });
      for (final package in units.purchasePackages) {
        await tx.insert('product_purchase_packages', {
          'product_id': productId,
          'name': package.name.trim(),
          'base_quantity': package.baseQuantity,
          'is_default': package.isDefault ? 1 : 0,
          'is_archived': 0,
          'created_at': now,
          'updated_at': now,
        });
      }
      for (final option in synchronizedSales) {
        await tx.insert('product_selling_options', {
          'product_id': productId,
          'name': option.name.trim(),
          'base_quantity': option.baseQuantity,
          'price_centavos': option.priceCentavos,
          'is_default': option.isDefault ? 1 : 0,
          'is_archived': 0,
          'created_at': now,
          'updated_at': now,
        });
      }
      await tx.insert('activity_logs', {
        'event_type': 'PRODUCT_CREATED',
        'description': 'Product created — $name',
        'actor_role': actorRole,
        'related_entity_type': 'PRODUCT',
        'related_entity_id': productId,
        'created_at': now,
      });
      return _receiveWith(
        tx,
        ConsignmentReceiptDraft(
          consignorId: consignorId,
          productId: productId,
          boxes: boxes,
          unitsPerBox: unitsPerBox,
          unitCostCentavos: unitCostCentavos,
          supplierCostBasisQuantity: supplierCostBasisQuantity,
          packageName: packageName,
          baseUnitLabel: baseUnitLabel,
          priceUnitName: priceUnitName,
          sellingPriceCentavos: sellingPriceCentavos,
          notes: notes,
        ),
      );
    }),
  );

  Future<void> _requireActiveCategory(DatabaseExecutor executor, int id) async {
    final category = await executor.query(
      'categories',
      columns: ['id'],
      where: 'id=? AND is_archived=0',
      whereArgs: [id],
      limit: 1,
    );
    if (category.isEmpty) {
      throw const InvalidConsignmentOperation('Active category is required.');
    }
  }

  Future<int> _receiveWith(
    DatabaseExecutor tx,
    ConsignmentReceiptDraft draft,
  ) async {
    if (draft.boxes <= 0 ||
        draft.unitsPerBox <= 0 ||
        draft.unitCostCentavos < 0 ||
        draft.sellingPriceCentavos <= 0) {
      throw const InvalidConsignmentOperation('Invalid receipt values.');
    }
    final consignor = await tx.query(
      'consignors',
      where: 'id=? AND is_archived=0',
      whereArgs: [draft.consignorId],
      limit: 1,
    );
    final product = await tx.query(
      'products',
      where: 'id=? AND is_archived=0',
      whereArgs: [draft.productId],
      limit: 1,
    );
    if (consignor.isEmpty || product.isEmpty) {
      throw const InvalidConsignmentOperation(
        'Active consignor and product are required.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String(),
        units = draft.totalUnits;
    final transactionId = await tx.insert('inventory_transactions', {
      'type': 'STOCK_IN',
      'reference_number': 'CONSIGNMENT',
      'notes': draft.notes,
      'occurred_at': now,
      'created_at': now,
    });
    final before = product.single['current_quantity']! as int;
    final movementId = await tx.insert('inventory_movements', {
      'inventory_transaction_id': transactionId,
      'product_id': draft.productId,
      'quantity_change': units,
      'quantity_before': before,
      'quantity_after': before + units,
      'unit_cost_centavos': draft.costForQuantity(1),
      'created_at': now,
    });
    final batchId = await tx.insert('consignment_batches', {
      'consignor_id': draft.consignorId,
      'product_id': draft.productId,
      'inventory_movement_id': movementId,
      'boxes_received': draft.boxes,
      'units_per_box': draft.unitsPerBox,
      'units_received': units,
      'unit_cost_centavos': draft.costForQuantity(1),
      'supplier_cost_centavos': draft.unitCostCentavos,
      'supplier_cost_basis_quantity': draft.supplierCostBasisQuantity,
      'package_name': draft.packageName,
      'package_count': draft.boxes,
      'base_quantity_per_package': draft.unitsPerBox,
      'base_unit_label': draft.baseUnitLabel,
      'price_unit_name': draft.priceUnitName,
      'price_unit_base_quantity': draft.supplierCostBasisQuantity,
      'selling_price_centavos': draft.sellingPriceCentavos,
      'notes': draft.notes?.trim(),
      'received_at': now,
      'created_at': now,
    });
    final group = (await tx.query(
      'inventory_groups',
      where: 'code=?',
      whereArgs: ['CONSIGNMENT'],
      limit: 1,
    )).single;
    await tx.insert('product_inventory_groups', {
      'product_id': draft.productId,
      'inventory_group_id': group['id'],
      'assigned_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await tx.update(
      'products',
      {'selling_price_centavos': draft.sellingPriceCentavos},
      where: 'id=?',
      whereArgs: [draft.productId],
    );
    await tx.update(
      'product_selling_options',
      {'price_centavos': draft.sellingPriceCentavos, 'updated_at': now},
      where: 'product_id=? AND is_default=1 AND is_archived=0',
      whereArgs: [draft.productId],
    );
    await tx.insert('activity_logs', {
      'event_type': 'CONSIGNMENT_RECEIVED',
      'description':
          'Consignment received from ${consignor.single['name']} — $units units',
      'actor_role': actorRole,
      'related_entity_type': 'CONSIGNMENT_BATCH',
      'related_entity_id': batchId,
      'created_at': now,
    });
    return batchId;
  }

  Future<void> returnUnits({
    required int batchId,
    required int quantity,
    String? notes,
  }) async {
    if (quantity <= 0) {
      throw const InvalidConsignmentOperation(
        'Return quantity must be positive.',
      );
    }
    await db.transaction((tx) async {
      final rows = await tx.rawQuery(
        '''SELECT b.*,p.current_quantity,p.name,c.name consignor_name FROM consignment_batches b JOIN products p ON p.id=b.product_id JOIN consignors c ON c.id=b.consignor_id WHERE b.id=?''',
        [batchId],
      );
      if (rows.isEmpty) {
        throw const InvalidConsignmentOperation('Batch not found.');
      }
      final b = rows.single;
      final available =
          (b['units_received']! as int) -
          (b['units_allocated']! as int) -
          (b['units_returned']! as int);
      if (quantity > available || quantity > (b['current_quantity']! as int)) {
        throw const InvalidConsignmentOperation(
          'Return exceeds available consigned stock.',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final transactionId = await tx.insert('inventory_transactions', {
        'type': 'RETURN',
        'reference_number': 'CONSIGNMENT-RETURN-$batchId',
        'notes': notes,
        'occurred_at': now,
        'created_at': now,
      });
      final before = b['current_quantity']! as int;
      final movementId = await tx.insert('inventory_movements', {
        'inventory_transaction_id': transactionId,
        'product_id': b['product_id'],
        'quantity_change': -quantity,
        'quantity_before': before,
        'quantity_after': before - quantity,
        'unit_cost_centavos': b['unit_cost_centavos'],
        'created_at': now,
      });
      final returnId = await tx.insert('consignment_returns', {
        'batch_id': batchId,
        'inventory_movement_id': movementId,
        'quantity': quantity,
        'unit_cost_centavos': b['unit_cost_centavos'],
        'notes': notes?.trim(),
        'returned_at': now,
        'created_at': now,
      });
      await tx.update(
        'consignment_batches',
        {'units_returned': (b['units_returned']! as int) + quantity},
        where: 'id=?',
        whereArgs: [batchId],
      );
      await tx.insert('activity_logs', {
        'event_type': 'CONSIGNMENT_RETURNED',
        'description':
            'Consignment return to ${b['consignor_name']} — $quantity units',
        'actor_role': actorRole,
        'related_entity_type': 'CONSIGNMENT_RETURN',
        'related_entity_id': returnId,
        'created_at': now,
      });
    });
  }

  Future<int> remit({
    required int consignorId,
    required int amountCentavos,
    String? notes,
  }) async {
    if (amountCentavos <= 0) {
      throw const InvalidConsignmentOperation('Amount must be positive.');
    }
    return db.transaction((tx) async {
      final party = await tx.query(
        'consignors',
        where: 'id=?',
        whereArgs: [consignorId],
        limit: 1,
      );
      if (party.isEmpty) {
        throw const InvalidConsignmentOperation('Consignor not found.');
      }
      final balance =
          Sqflite.firstIntValue(
            await tx.rawQuery(
              '''SELECT COALESCE((SELECT SUM(amount_change_centavos) FROM consignor_ledger_entries WHERE consignor_id=?),0)+
              COALESCE((SELECT SUM(payable_change_centavos) FROM consignment_allocation_reversals WHERE consignor_id=?),0)''',
              [consignorId, consignorId],
            ),
          ) ??
          0;
      if (amountCentavos > balance) {
        throw const InvalidConsignmentOperation(
          'Remittance exceeds outstanding payable.',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await tx.insert('consignor_remittances', {
        'consignor_id': consignorId,
        'amount_centavos': amountCentavos,
        'notes': notes?.trim(),
        'remitted_at': now,
        'created_at': now,
      });
      await tx.insert('consignor_ledger_entries', {
        'consignor_id': consignorId,
        'entry_type': 'REMITTANCE',
        'amount_change_centavos': -amountCentavos,
        'remittance_id': id,
        'description': 'Supplier remittance',
        'occurred_at': now,
        'created_at': now,
      });
      await tx.insert('activity_logs', {
        'event_type': 'CONSIGNMENT_REMITTANCE',
        'description':
            '₱${(amountCentavos / 100).toStringAsFixed(2)} remitted to ${party.single['name']}',
        'actor_role': actorRole,
        'related_entity_type': 'CONSIGNOR_REMITTANCE',
        'related_entity_id': id,
        'created_at': now,
      });
      return id;
    });
  }

  Future<ConsignmentSummary> summary() async {
    final payable =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COALESCE((SELECT SUM(amount_change_centavos) FROM consignor_ledger_entries),0)+COALESCE((SELECT SUM(payable_change_centavos) FROM consignment_allocation_reversals),0)''',
          ),
        ) ??
        0;
    final stock = await db.rawQuery('''SELECT COALESCE(SUM(units_received-units_allocated-units_returned),0) units,
      COALESCE(SUM(((units_received-units_allocated-units_returned)*
        COALESCE(supplier_cost_centavos,unit_cost_centavos)+
        COALESCE(supplier_cost_basis_quantity,1)/2)/
        COALESCE(supplier_cost_basis_quantity,1)),0) value
      FROM consignment_batches''');
    final margin =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COALESCE((SELECT SUM(COALESCE(actual_margin_centavos,margin_centavos)) FROM consignment_allocations),0)+COALESCE((SELECT SUM(margin_change_centavos) FROM consignment_allocation_reversals),0)''',
          ),
        ) ??
        0;
    return ConsignmentSummary(
      payableCentavos: payable,
      remainingUnits: stock.single['units']! as int,
      inventoryValueCentavos: stock.single['value']! as int,
      marginCentavos: margin,
    );
  }

  Future<ConsignmentSummary> summaryForConsignor(int consignorId) async {
    final payable =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COALESCE((SELECT SUM(amount_change_centavos) FROM consignor_ledger_entries WHERE consignor_id=?),0)+COALESCE((SELECT SUM(payable_change_centavos) FROM consignment_allocation_reversals WHERE consignor_id=?),0)''',
            [consignorId, consignorId],
          ),
        ) ??
        0;
    final stock = (await db.rawQuery(
      '''SELECT COALESCE(SUM(units_received-units_allocated-units_returned),0) units,
      COALESCE(SUM(((units_received-units_allocated-units_returned)*
        COALESCE(supplier_cost_centavos,unit_cost_centavos)+
        COALESCE(supplier_cost_basis_quantity,1)/2)/
        COALESCE(supplier_cost_basis_quantity,1)),0) value
      FROM consignment_batches WHERE consignor_id=?''',
      [consignorId],
    )).single;
    final margin =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''SELECT COALESCE((SELECT SUM(COALESCE(a.actual_margin_centavos,a.margin_centavos)) FROM consignment_allocations a JOIN consignment_batches b ON b.id=a.batch_id WHERE b.consignor_id=?),0)+COALESCE((SELECT SUM(margin_change_centavos) FROM consignment_allocation_reversals WHERE consignor_id=?),0)''',
            [consignorId, consignorId],
          ),
        ) ??
        0;
    return ConsignmentSummary(
      payableCentavos: payable,
      remainingUnits: stock['units']! as int,
      inventoryValueCentavos: stock['value']! as int,
      marginCentavos: margin,
    );
  }

  Future<List<Map<String, Object?>>> companyCards() => db.rawQuery('''SELECT c.id,c.name,c.contact_details,c.default_category_id,cat.name default_category_name,COUNT(DISTINCT CASE WHEN p.is_archived=0 THEN b.product_id END) product_count,MAX(b.received_at) last_receipt_at,
      (SELECT MAX(r.remitted_at) FROM consignor_remittances r WHERE r.consignor_id=c.id) last_remittance_at,
      COALESCE((SELECT SUM(l.amount_change_centavos) FROM consignor_ledger_entries l WHERE l.consignor_id=c.id),0)+
      COALESCE((SELECT SUM(r.payable_change_centavos) FROM consignment_allocation_reversals r WHERE r.consignor_id=c.id),0) payable_centavos
      FROM consignors c LEFT JOIN consignment_batches b ON b.consignor_id=c.id
      LEFT JOIN products p ON p.id=b.product_id
      LEFT JOIN categories cat ON cat.id=c.default_category_id
      WHERE c.is_archived=0 GROUP BY c.id ORDER BY c.name COLLATE NOCASE''');

  Future<List<Map<String, Object?>>> productCardsForConsignor(
    int consignorId,
  ) => db.rawQuery(
    '''SELECT b.product_id,p.name,p.photo_path,p.base_unit_label,c.name consignor_name,SUM(b.units_received) received,SUM(b.units_allocated) sold,SUM(b.units_received-b.units_allocated-b.units_returned) remaining,MAX(b.selling_price_centavos) selling_price_centavos,SUM(b.units_allocated*b.unit_cost_centavos) payable_centavos,SUM(b.units_allocated*(b.selling_price_centavos-b.unit_cost_centavos)) margin_centavos FROM consignment_batches b JOIN products p ON p.id=b.product_id JOIN consignors c ON c.id=b.consignor_id WHERE b.consignor_id=? AND p.is_archived=0 GROUP BY b.product_id,b.consignor_id ORDER BY p.name COLLATE NOCASE''',
    [consignorId],
  );

  Future<List<Map<String, Object?>>> archivedProductCardsForConsignor(
    int consignorId,
  ) => db.rawQuery(
    '''SELECT b.product_id,p.name,p.photo_path,p.base_unit_label,c.name consignor_name,SUM(b.units_received) received,SUM(b.units_allocated) sold,SUM(b.units_received-b.units_allocated-b.units_returned) remaining,MAX(b.selling_price_centavos) selling_price_centavos,SUM(b.units_allocated*b.unit_cost_centavos) payable_centavos,SUM(b.units_allocated*(b.selling_price_centavos-b.unit_cost_centavos)) margin_centavos FROM consignment_batches b JOIN products p ON p.id=b.product_id JOIN consignors c ON c.id=b.consignor_id WHERE b.consignor_id=? AND p.is_archived=1 GROUP BY b.product_id,b.consignor_id ORDER BY p.name COLLATE NOCASE''',
    [consignorId],
  );

  Future<List<Map<String, Object?>>> productCards() => db.rawQuery(
    '''SELECT b.product_id,p.name,p.photo_path,c.name consignor_name,SUM(b.units_received) received,SUM(b.units_allocated) sold,SUM(b.units_received-b.units_allocated-b.units_returned) remaining,MAX(b.selling_price_centavos) selling_price_centavos,SUM(b.units_allocated*b.unit_cost_centavos) payable_centavos,SUM(b.units_allocated*(b.selling_price_centavos-b.unit_cost_centavos)) margin_centavos FROM consignment_batches b JOIN products p ON p.id=b.product_id JOIN consignors c ON c.id=b.consignor_id WHERE p.is_archived=0 GROUP BY b.product_id,b.consignor_id ORDER BY p.name COLLATE NOCASE''',
  );
  Future<List<Map<String, Object?>>> history({int? consignorId}) => db.rawQuery(
    '''SELECT l.*,c.name consignor_name FROM consignor_ledger_entries l JOIN consignors c ON c.id=l.consignor_id ${consignorId == null ? '' : 'WHERE l.consignor_id=?'} ORDER BY l.occurred_at DESC,l.id DESC''',
    consignorId == null ? null : [consignorId],
  );

  Future<List<Map<String, Object?>>> deliveriesForConsignor(int consignorId) =>
      db.rawQuery(
        '''SELECT b.id,b.received_at,p.name,b.package_name,b.package_count,
          b.base_quantity_per_package,b.base_unit_label,b.units_received,
          b.supplier_cost_centavos,b.supplier_cost_basis_quantity,b.price_unit_name,
          b.selling_price_centavos,b.notes
          FROM consignment_batches b JOIN products p ON p.id=b.product_id
          WHERE b.consignor_id=? ORDER BY b.received_at DESC,b.id DESC''',
        [consignorId],
      );

  Future<List<Map<String, Object?>>> remittancesForConsignor(int consignorId) =>
      db.rawQuery(
        '''SELECT amount_centavos,notes,remitted_at FROM consignor_remittances
          WHERE consignor_id=? ORDER BY remitted_at DESC,id DESC''',
        [consignorId],
      );

  Future<List<Map<String, Object?>>> productHistory(
    int productId, {
    int? consignorId,
  }) => db.rawQuery(
    '''SELECT 'RECEIPT' event_type,b.received_at occurred_at,b.units_received quantity,
          b.unit_cost_centavos,b.selling_price_centavos,0 payable_centavos,0 margin_centavos,b.notes
        FROM consignment_batches b WHERE b.product_id=? AND (? IS NULL OR b.consignor_id=?)
        UNION ALL
        SELECT CASE WHEN a.cash_sale_item_id IS NOT NULL THEN 'CASH SALE' ELSE 'UTANG' END,
          a.occurred_at,-a.quantity,a.unit_cost_centavos,a.selling_price_centavos,
          COALESCE(a.actual_payable_centavos,a.payable_centavos) payable_centavos,
          COALESCE(a.actual_margin_centavos,a.margin_centavos) margin_centavos,NULL
        FROM consignment_allocations a JOIN consignment_batches b ON b.id=a.batch_id WHERE b.product_id=? AND (? IS NULL OR b.consignor_id=?)
        UNION ALL
        SELECT 'RETURN',r.returned_at,-r.quantity,r.unit_cost_centavos,b.selling_price_centavos,
          0,0,r.notes
        FROM consignment_returns r JOIN consignment_batches b ON b.id=r.batch_id WHERE b.product_id=? AND (? IS NULL OR b.consignor_id=?)
        ORDER BY occurred_at DESC''',
    [
      productId,
      consignorId,
      consignorId,
      productId,
      consignorId,
      consignorId,
      productId,
      consignorId,
      consignorId,
    ],
  );

  Future<List<Map<String, Object?>>> returnableBatches(
    int productId, {
    int? consignorId,
  }) => db.rawQuery(
    '''SELECT b.id,b.received_at,b.units_received-b.units_allocated-b.units_returned available,
          b.unit_cost_centavos,c.name consignor_name
        FROM consignment_batches b JOIN consignors c ON c.id=b.consignor_id
        WHERE b.product_id=? AND (? IS NULL OR b.consignor_id=?) AND b.units_received-b.units_allocated-b.units_returned>0
        ORDER BY b.received_at,b.id''',
    [productId, consignorId, consignorId],
  );
}
