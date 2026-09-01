import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late InventoryRepository inventory;
  late Product product;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    final category = (await SqliteCategoryRepository(db).create('Test')).id;
    product = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category,
        name: 'Kape',
        photoPath: '/k.jpg',
        purchasePriceCentavos: 500,
        sellingPriceCentavos: 800,
        startingQuantity: 5,
        minimumStockLevel: 2,
      ),
    );
    inventory = InventoryRepository(db);
  });
  tearDown(() => app.close());

  test('stock-in and adjustments use ledger and cached stock', () async {
    await inventory.stockIn(
      productId: product.id,
      quantity: 4,
      unitCostCentavos: 600,
      notes: 'Delivery',
    );
    await inventory.adjust(
      productId: product.id,
      quantityChange: -2,
      reason: 'Nadaot',
    );
    final current = (await inventory.current()).single;
    expect(current.currentQuantity, 7);
    final history = await inventory.history();
    expect(
      history.map((m) => m.type),
      containsAll(['INITIAL_STOCK', 'STOCK_IN', 'ADJUSTMENT_OUT']),
    );
    expect(await inventory.inventoryValueCentavos(), 3500);
  });

  test('negative-result adjustment rolls back cleanly', () async {
    await expectLater(
      inventory.adjust(
        productId: product.id,
        quantityChange: -6,
        reason: 'Sayop',
      ),
      throwsA(isA<InvalidInventoryOperation>()),
    );
    expect((await inventory.current()).single.currentQuantity, 5);
    expect((await inventory.history()).length, 1);
  });

  test(
    'requires adjustment reason and exposes low/out-of-stock lists',
    () async {
      expect(
        () => inventory.adjust(
          productId: product.id,
          quantityChange: -1,
          reason: ' ',
        ),
        throwsA(isA<InvalidInventoryOperation>()),
      );
      await inventory.adjust(
        productId: product.id,
        quantityChange: -3,
        reason: 'Count',
      );
      expect(
        (await inventory.current(status: ProductStockStatus.lowStock))
            .single
            .id,
        product.id,
      );
      await inventory.adjust(
        productId: product.id,
        quantityChange: -2,
        reason: 'Count',
      );
      expect(
        (await inventory.current(status: ProductStockStatus.outOfStock))
            .single
            .id,
        product.id,
      );
    },
  );
}
