import 'package:sqflite/sqflite.dart';

class ReversalException implements Exception {
  const ReversalException(this.message);
  final String message;
}

class ReversalRepository {
  const ReversalRepository(this.db, {this.actorRole = 'OWNER'});
  final Database db;
  final String actorRole;
  void _reason(String value, bool ownerPinAuthorized) {
    if (value.trim().isEmpty) {
      throw const ReversalException('Reversal reason is required.');
    }
    if (actorRole != 'OWNER' || !ownerPinAuthorized) {
      throw const ReversalException('Owner PIN authorization is required.');
    }
  }

  Future<int> reverseCashSale(
    int id,
    String reason, {
    required bool ownerPinAuthorized,
  }) => db.transaction(
    (tx) => reverseCashSaleWith(
      tx,
      id,
      reason,
      ownerPinAuthorized: ownerPinAuthorized,
    ),
  );
  Future<int> reverseUtang(
    int id,
    String reason, {
    required bool ownerPinAuthorized,
  }) => db.transaction(
    (tx) => reverseUtangWith(
      tx,
      id,
      reason,
      ownerPinAuthorized: ownerPinAuthorized,
    ),
  );
  Future<int> reverseCashSaleWith(
    DatabaseExecutor tx,
    int id,
    String reason, {
    required bool ownerPinAuthorized,
  }) => _reverseWith(tx, id, reason, 'CASH', ownerPinAuthorized);
  Future<int> reverseUtangWith(
    DatabaseExecutor tx,
    int id,
    String reason, {
    required bool ownerPinAuthorized,
  }) => _reverseWith(tx, id, reason, 'UTANG', ownerPinAuthorized);
  Future<int> reversePayment(
    int id,
    String reason, {
    required bool ownerPinAuthorized,
  }) async {
    _reason(reason, ownerPinAuthorized);
    return db.transaction(
      (tx) => reversePaymentWith(
        tx,
        id,
        reason,
        ownerPinAuthorized: ownerPinAuthorized,
      ),
    );
  }

  Future<int> reversePaymentWith(
    DatabaseExecutor tx,
    int id,
    String reason, {
    required bool ownerPinAuthorized,
  }) async {
    _reason(reason, ownerPinAuthorized);
    final rows = await tx.query(
      'utang_payments',
      where: "id=? AND status='POSTED'",
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const ReversalException(
        'Payment is unavailable or already reversed.',
      );
    }
    final p = rows.single, now = DateTime.now().toUtc().toIso8601String();
    final reversal = await _header(tx, reason, payment: id, now: now);
    await tx.insert('customer_ledger_entries', {
      'customer_id': p['customer_id'],
      'entry_type': 'PAYMENT_REVERSAL',
      'amount_change_centavos': p['amount_centavos'],
      'payment_id': id,
      'description': 'Payment reversal ${_ref(reversal)}',
      'occurred_at': now,
      'created_at': now,
    });
    await tx.update(
      'utang_payments',
      {'status': 'REVERSED'},
      where: 'id=?',
      whereArgs: [id],
    );
    await _log(
      tx,
      'Payment #$id reversed — ${reason.trim()}',
      'PAYMENT',
      id,
      now,
    );
    return reversal;
  }

  Future<int> _reverseWith(
    DatabaseExecutor tx,
    int id,
    String reason,
    String kind,
    bool ownerPinAuthorized,
  ) async {
    _reason(reason, ownerPinAuthorized);
    final cash = kind == 'CASH',
        table = cash ? 'cash_sales' : 'utang_transactions',
        itemTable = cash ? 'cash_sale_items' : 'utang_transaction_items',
        foreign = cash ? 'cash_sale_id' : 'utang_transaction_id';
    final headers = await tx.query(
      table,
      where: "id=? AND status='POSTED'",
      whereArgs: [id],
      limit: 1,
    );
    if (headers.isEmpty) {
      throw ReversalException(
        '${cash ? 'Cash Sale' : 'UTANG'} is unavailable or already reversed.',
      );
    }
    final header = headers.single,
        items = await tx.query(
          itemTable,
          where: '$foreign=?',
          whereArgs: [id],
          orderBy: 'id',
        ),
        now = DateTime.now().toUtc().toIso8601String();
    final reversal = await _header(
      tx,
      reason,
      cash: cash ? id : null,
      utang: cash ? null : id,
      now: now,
    );
    final inv = await tx.insert('inventory_transactions', {
      'type': 'REVERSAL',
      'reference_number': _ref(reversal),
      'notes': reason.trim(),
      'occurred_at': now,
      'created_at': now,
    });
    for (final item in items) {
      final product = (await tx.query(
            'products',
            where: 'id=?',
            whereArgs: [item['product_id']],
            limit: 1,
          )).single,
          before = product['current_quantity']! as int,
          quantity = item['quantity']! as int;
      await tx.insert('inventory_movements', {
        'inventory_transaction_id': inv,
        'product_id': item['product_id'],
        'quantity_change': quantity,
        'quantity_before': before,
        'quantity_after': before + quantity,
        'created_at': now,
      });
      await _reverseAllocations(
        tx,
        reversal,
        cashSaleItemId: cash ? item['id'] as int : null,
        utangItemId: cash ? null : item['id'] as int,
        now: now,
      );
    }
    if (!cash) {
      await tx.insert('customer_ledger_entries', {
        'customer_id': header['customer_id'],
        'entry_type': 'UTANG_REVERSAL',
        'amount_change_centavos': -(header['total_centavos']! as int),
        'utang_transaction_id': id,
        'description': 'UTANG reversal ${_ref(reversal)}',
        'occurred_at': now,
        'created_at': now,
      });
    }
    await tx.update(
      table,
      {'status': 'REVERSED'},
      where: 'id=?',
      whereArgs: [id],
    );
    final label = cash
        ? 'Cash sale ${header['reference']}'
        : 'UTANG ${header['reference']}';
    await _log(
      tx,
      '$label reversed — ${reason.trim()}',
      cash ? 'CASH_SALE' : 'UTANG',
      id,
      now,
    );
    return reversal;
  }

  Future<void> _reverseAllocations(
    DatabaseExecutor tx,
    int reversal, {
    int? cashSaleItemId,
    int? utangItemId,
    required String now,
  }) async {
    final rows = await tx.rawQuery(
      '''SELECT a.*,b.consignor_id FROM consignment_allocations a JOIN consignment_batches b ON b.id=a.batch_id WHERE ${cashSaleItemId != null ? 'a.cash_sale_item_id=?' : 'a.utang_item_id=?'}''',
      [cashSaleItemId ?? utangItemId],
    );
    for (final a in rows) {
      final balance =
          Sqflite.firstIntValue(
            await tx.rawQuery(
              '''SELECT COALESCE((SELECT SUM(amount_change_centavos) FROM consignor_ledger_entries WHERE consignor_id=?),0)+COALESCE((SELECT SUM(payable_change_centavos) FROM consignment_allocation_reversals WHERE consignor_id=?),0)''',
              [a['consignor_id'], a['consignor_id']],
            ),
          ) ??
          0;
      final payable = a['payable_centavos']! as int;
      if (balance - payable < 0) {
        throw const ReversalException(
          'Supplier payable was already remitted; reverse the remittance first.',
        );
      }
      await tx.insert('consignment_allocation_reversals', {
        'transaction_reversal_id': reversal,
        'allocation_id': a['id'],
        'consignor_id': a['consignor_id'],
        'quantity': a['quantity'],
        'payable_change_centavos': -payable,
        'margin_change_centavos': -(a['margin_centavos']! as int),
        'occurred_at': now,
        'created_at': now,
      });
      final batch = (await tx.query(
        'consignment_batches',
        columns: ['units_allocated'],
        where: 'id=?',
        whereArgs: [a['batch_id']],
      )).single;
      await tx.update(
        'consignment_batches',
        {
          'units_allocated':
              (batch['units_allocated']! as int) - (a['quantity']! as int),
        },
        where: 'id=?',
        whereArgs: [a['batch_id']],
      );
    }
  }

  Future<int> _header(
    DatabaseExecutor tx,
    String reason, {
    int? cash,
    int? utang,
    int? payment,
    required String now,
  }) => tx.insert('transaction_reversals', {
    'reference': 'REV-${DateTime.now().microsecondsSinceEpoch}',
    'cash_sale_id': cash,
    'utang_transaction_id': utang,
    'payment_id': payment,
    'reason': reason.trim(),
    'occurred_at': now,
    'created_at': now,
  });
  String _ref(int id) => 'REV-${id.toString().padLeft(6, '0')}';
  Future<void> _log(
    DatabaseExecutor tx,
    String description,
    String type,
    int id,
    String now,
  ) => tx.insert('activity_logs', {
    'event_type': 'TRANSACTION_REVERSED',
    'description': description,
    'actor_role': actorRole,
    'related_entity_type': type,
    'related_entity_id': id,
    'created_at': now,
  });
}
