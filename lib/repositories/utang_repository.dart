import 'package:sqflite/sqflite.dart';

import '../models/utang_draft.dart';
import 'consignment_allocation.dart';

class UtangRepository {
  const UtangRepository(this._database, {this.actorRole});
  final Database _database;
  Database get db => _database;
  final String? actorRole;

  Future<int> save(UtangDraft draft) async {
    return _database.transaction((txn) => saveWithExecutor(txn, draft));
  }

  Future<int> saveWithExecutor(DatabaseExecutor txn, UtangDraft draft) async {
    if (draft.items.isEmpty) throw ArgumentError('Utang must contain items.');
    if (draft.items.any((item) => item.effectiveQuantityValue <= 0)) {
      throw ArgumentError('Item quantities must be positive.');
    }

    final customer = await txn.query(
      'customers',
      columns: ['id', 'full_name'],
      where: 'id = ? AND is_archived = 0',
      whereArgs: [draft.customerId],
      limit: 1,
    );
    if (customer.isEmpty) throw StateError('Active customer not found.');

    final now = (draft.occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    final productRows =
        <
          ({
            UtangItemDraft draft,
            Map<String, Object?> row,
            int price,
            int baseQuantity,
            int line,
          })
        >[];
    final requiredByProduct = <int, int>{};
    var total = 0;
    for (final item in draft.items) {
      final rows = await txn.query(
        'products',
        where: 'id = ? AND is_archived = 0',
        whereArgs: [item.productId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Active product not found.');
      final row = rows.single;
      if (item.quantityScale <= 0 || item.baseQuantityPerUnit <= 0) {
        throw ArgumentError('Invalid selling quantity.');
      }
      if (item.sellingOptionId != null) {
        final option = await txn.query(
          'product_selling_options',
          where: 'id=? AND product_id=? AND is_archived=0',
          whereArgs: [item.sellingOptionId, item.productId],
          limit: 1,
        );
        if (option.isEmpty) {
          throw StateError(
            'The selected selling option is no longer available.',
          );
        }
      }
      final base = item.totalBaseQuantity;
      final needed = (requiredByProduct[item.productId] ?? 0) + base;
      requiredByProduct[item.productId] = needed;
      if ((row['current_quantity']! as int) < needed) {
        throw StateError(
          'Not enough ${item.baseUnitLabel}. Required: $needed; available: ${row['current_quantity']}.',
        );
      }
      final price =
          item.unitPriceCentavos ?? row['selling_price_centavos']! as int;
      final line = item.lineTotalCentavos(price);
      total += line;
      productRows.add((
        draft: item,
        row: row,
        price: price,
        baseQuantity: base,
        line: line,
      ));
    }
    if (total <= 0) throw StateError('Utang total must be positive.');

    final utangId = await txn.insert('utang_transactions', {
      'customer_id': draft.customerId,
      'total_centavos': total,
      'status': 'POSTED',
      'notes': draft.notes,
      'occurred_at': now,
      'created_at': now,
    });
    final reference = 'UTG-${utangId.toString().padLeft(6, '0')}';
    await txn.update(
      'utang_transactions',
      {'reference': reference},
      where: 'id=?',
      whereArgs: [utangId],
    );
    final inventoryTransactionId = await txn.insert('inventory_transactions', {
      'type': 'UTANG',
      'reference_number': reference,
      'notes': draft.notes,
      'occurred_at': now,
      'created_at': now,
    });

    var verifiedTotal = 0;
    final runningStock = <int, int>{};
    for (final entry in productRows) {
      final item = entry.draft;
      final row = entry.row;
      final productId = row['id']! as int;
      final price = entry.price;
      final before = runningStock[productId] ?? row['current_quantity']! as int;
      final lineTotal = entry.line;
      verifiedTotal += lineTotal;
      final itemId = await txn.insert('utang_transaction_items', {
        'utang_transaction_id': utangId,
        'product_id': productId,
        'product_name_snapshot': row['name']! as String,
        'unit_price_centavos': item.quantityScale == 1 ? price : lineTotal,
        'quantity': item.quantityScale == 1 ? item.effectiveQuantityValue : 1,
        'line_total_centavos': lineTotal,
        'selling_option_id': item.sellingOptionId,
        'selling_option_name_snapshot': item.sellingOptionName ?? 'Piece',
        'base_quantity_per_unit': item.baseQuantityPerUnit,
        'selling_quantity_value': item.effectiveQuantityValue,
        'selling_quantity_scale': item.quantityScale,
        'base_unit_snapshot': item.baseUnitLabel,
        'total_base_quantity': entry.baseQuantity,
        'selling_unit_price_centavos': price,
        'created_at': now,
      });
      await ConsignmentAllocation.postSale(
        txn,
        productId: productId,
        quantity: entry.baseQuantity,
        sellingPriceCentavos: entry.baseQuantity == 0
            ? 0
            : (lineTotal + entry.baseQuantity ~/ 2) ~/ entry.baseQuantity,
        totalSaleCentavos: lineTotal,
        utangItemId: itemId,
        occurredAt: now,
      );
      await txn.insert('inventory_movements', {
        'inventory_transaction_id': inventoryTransactionId,
        'product_id': productId,
        'quantity_change': -entry.baseQuantity,
        'quantity_before': before,
        'quantity_after': before - entry.baseQuantity,
        'utang_item_id': itemId,
        'created_at': now,
      });
      runningStock[productId] = before - entry.baseQuantity;
    }
    if (verifiedTotal != total) throw StateError('Utang total mismatch.');

    await txn.insert('customer_ledger_entries', {
      'customer_id': draft.customerId,
      'entry_type': 'UTANG',
      'amount_change_centavos': total,
      'utang_transaction_id': utangId,
      'description': '$reference UTANG',
      'occurred_at': now,
      'created_at': now,
    });
    await txn.insert('activity_logs', {
      'event_type': 'UTANG_CREATED',
      'description':
          'UTANG $reference created for ${customer.single['full_name']} — ₱${(total / 100).toStringAsFixed(2)}',
      'actor_role': actorRole,
      'related_entity_type': 'UTANG',
      'related_entity_id': utangId,
      'created_at': now,
    });
    return utangId;
  }
}
