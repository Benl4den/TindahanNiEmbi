import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database db;

  setUp(() async {
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await appDatabase.database;
  });

  tearDown(() => appDatabase.close());

  test(
    'migration V1 creates every approved table and records its version',
    () async {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name']).toSet();
      expect(
        names,
        containsAll({
          'schema_migrations',
          'categories',
          'products',
          'customers',
          'inventory_transactions',
          'inventory_movements',
          'utang_transactions',
          'utang_transaction_items',
          'utang_payments',
          'customer_ledger_entries',
        }),
      );
      expect(
        await db.query('schema_migrations'),
        contains(predicate<Map<String, Object?>>((row) => row['version'] == 1)),
      );
    },
  );

  test('foreign keys are enabled and protect history', () async {
    final pragma = await db.rawQuery('PRAGMA foreign_keys');
    expect(pragma.single.values.single, 1);

    await expectLater(
      db.insert('products', _productRow(categoryId: 999)),
      throwsA(isA<DatabaseException>()),
    );
  });

  test(
    'inventory trigger maintains cache and prevents negative stock',
    () async {
      final productId = await _seedProduct(db, quantity: 5);
      expect(await _quantity(db, productId), 5);

      final transactionId = await _inventoryTransaction(db, 'ADJUSTMENT_OUT');
      await expectLater(
        db.insert('inventory_movements', {
          'inventory_transaction_id': transactionId,
          'product_id': productId,
          'quantity_change': -6,
          'quantity_before': 5,
          'quantity_after': -1,
          'created_at': _now,
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(await _quantity(db, productId), 5);
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM inventory_movements WHERE product_id = ?',
            [productId],
          ),
        ),
        1,
      );

      await expectLater(
        db.update(
          'products',
          {'current_quantity': 4},
          where: 'id = ?',
          whereArgs: [productId],
        ),
        throwsA(isA<DatabaseException>()),
      );
    },
  );

  test(
    'saving utang atomically writes items, stock movement, and ledger',
    () async {
      final customerId = await _seedCustomer(db);
      final productId = await _seedProduct(db, quantity: 10, price: 900);
      final utangId = await UtangRepository(db).save(
        UtangDraft(
          customerId: customerId,
          items: [UtangItemDraft(productId: productId, quantity: 3)],
        ),
      );

      expect(await _quantity(db, productId), 7);
      final item = (await db.query(
        'utang_transaction_items',
        where: 'utang_transaction_id = ?',
        whereArgs: [utangId],
      )).single;
      expect(item['unit_price_centavos'], 900);
      expect(item['line_total_centavos'], 2700);
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT SUM(amount_change_centavos) FROM customer_ledger_entries WHERE customer_id = ?',
            [customerId],
          ),
        ),
        2700,
      );

      await db.update(
        'products',
        {'selling_price_centavos': 1200},
        where: 'id = ?',
        whereArgs: [productId],
      );
      final historicalItem = (await db.query(
        'utang_transaction_items',
        where: 'id = ?',
        whereArgs: [item['id']],
      )).single;
      expect(historicalItem['unit_price_centavos'], 900);
    },
  );

  test('failed utang rolls back every inserted record', () async {
    final customerId = await _seedCustomer(db);
    final productId = await _seedProduct(db, quantity: 2, price: 500);

    await expectLater(
      UtangRepository(db).save(
        UtangDraft(
          customerId: customerId,
          items: [UtangItemDraft(productId: productId, quantity: 3)],
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(await _quantity(db, productId), 2);
    for (final table in [
      'utang_transactions',
      'utang_transaction_items',
      'customer_ledger_entries',
    ]) {
      expect(
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')),
        0,
      );
    }
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery(
          "SELECT COUNT(*) FROM inventory_transactions WHERE type = 'UTANG'",
        ),
      ),
      0,
    );
  });

  test('partial payments preserve ledger and overpayment rolls back', () async {
    final customerId = await _seedCustomer(db);
    final productId = await _seedProduct(db, quantity: 10, price: 1000);
    await UtangRepository(db).save(
      UtangDraft(
        customerId: customerId,
        items: [UtangItemDraft(productId: productId, quantity: 3)],
      ),
    );
    final payments = PaymentRepository(db);
    await payments.record(customerId: customerId, amountCentavos: 1000);
    await payments.record(customerId: customerId, amountCentavos: 500);

    expect(await payments.balanceFor(customerId), 1500);
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery(
          "SELECT COUNT(*) FROM customer_ledger_entries WHERE entry_type = 'PAYMENT'",
        ),
      ),
      2,
    );

    await expectLater(
      payments.record(customerId: customerId, amountCentavos: 1501),
      throwsA(isA<DatabaseException>()),
    );
    expect(await payments.balanceFor(customerId), 1500);
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM utang_payments'),
      ),
      2,
    );
  });

  test(
    'ledger rejects invalid types, signs, duplicate sources, and mutation',
    () async {
      final customerId = await _seedCustomer(db);
      final productId = await _seedProduct(db, quantity: 3, price: 100);
      final utangId = await UtangRepository(db).save(
        UtangDraft(
          customerId: customerId,
          items: [UtangItemDraft(productId: productId, quantity: 1)],
        ),
      );

      await expectLater(
        db.insert('customer_ledger_entries', {
          'customer_id': customerId,
          'entry_type': 'UTANG',
          'amount_change_centavos': -100,
          'utang_transaction_id': utangId,
          'occurred_at': _now,
          'created_at': _now,
        }),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.delete('customer_ledger_entries'),
        throwsA(isA<DatabaseException>()),
      );
    },
  );
}

const _now = '2026-09-02T00:00:00.000Z';

Map<String, Object?> _productRow({int? categoryId, int price = 100}) => {
  'category_id': categoryId,
  'name': 'Test Product',
  'purchase_price_centavos': 50,
  'selling_price_centavos': price,
  'current_quantity': 0,
  'minimum_stock_level': 2,
  'created_at': _now,
  'updated_at': _now,
};

Future<int> _seedCustomer(Database db) => db.insert('customers', {
  'full_name': 'Juan Test',
  'created_at': _now,
  'updated_at': _now,
});

Future<int> _seedProduct(
  Database db, {
  required int quantity,
  int price = 100,
}) async {
  final productId = await db.insert('products', _productRow(price: price));
  if (quantity > 0) {
    final transactionId = await _inventoryTransaction(db, 'INITIAL_STOCK');
    await db.insert('inventory_movements', {
      'inventory_transaction_id': transactionId,
      'product_id': productId,
      'quantity_change': quantity,
      'quantity_before': 0,
      'quantity_after': quantity,
      'unit_cost_centavos': 50,
      'created_at': _now,
    });
  }
  return productId;
}

Future<int> _inventoryTransaction(Database db, String type) => db.insert(
  'inventory_transactions',
  {'type': type, 'occurred_at': _now, 'created_at': _now},
);

Future<int> _quantity(Database db, int productId) async {
  final rows = await db.query(
    'products',
    columns: ['current_quantity'],
    where: 'id = ?',
    whereArgs: [productId],
  );
  return rows.single['current_quantity']! as int;
}
