import 'package:sqflite/sqflite.dart';

import '../models/utang_draft.dart';

class UtangRepository {
  const UtangRepository(this._database, {this.actorRole});
  final Database _database;
  final String? actorRole;

  Future<int> save(UtangDraft draft) async {
    if (draft.items.isEmpty) throw ArgumentError('Utang must contain items.');
    if (draft.items.any((item) => item.quantity <= 0)) {
      throw ArgumentError('Item quantities must be positive.');
    }

    return _database.transaction((txn) async {
      final customer = await txn.query(
        'customers',
        columns: ['id', 'full_name'],
        where: 'id = ? AND is_archived = 0',
        whereArgs: [draft.customerId],
        limit: 1,
      );
      if (customer.isEmpty) throw StateError('Active customer not found.');

      final now = (draft.occurredAt ?? DateTime.now())
          .toUtc()
          .toIso8601String();
      final productRows =
          <({UtangItemDraft draft, Map<String, Object?> row})>[];
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
        final price = row['selling_price_centavos']! as int;
        total += price * item.quantity;
        productRows.add((draft: item, row: row));
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
      final inventoryTransactionId = await txn.insert(
        'inventory_transactions',
        {
          'type': 'UTANG',
          'reference_number': reference,
          'notes': draft.notes,
          'occurred_at': now,
          'created_at': now,
        },
      );

      var verifiedTotal = 0;
      for (final entry in productRows) {
        final item = entry.draft;
        final row = entry.row;
        final productId = row['id']! as int;
        final price = row['selling_price_centavos']! as int;
        final before = row['current_quantity']! as int;
        final lineTotal = price * item.quantity;
        verifiedTotal += lineTotal;
        final itemId = await txn.insert('utang_transaction_items', {
          'utang_transaction_id': utangId,
          'product_id': productId,
          'product_name_snapshot': row['name']! as String,
          'unit_price_centavos': price,
          'quantity': item.quantity,
          'line_total_centavos': lineTotal,
          'created_at': now,
        });
        await txn.insert('inventory_movements', {
          'inventory_transaction_id': inventoryTransactionId,
          'product_id': productId,
          'quantity_change': -item.quantity,
          'quantity_before': before,
          'quantity_after': before - item.quantity,
          'utang_item_id': itemId,
          'created_at': now,
        });
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
    });
  }
}
