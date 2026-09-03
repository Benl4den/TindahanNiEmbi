import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase appDatabase;
  late Database database;
  late SqliteProductRepository products;
  late SqliteCategoryRepository categories;
  late int categoryId;

  setUp(() async {
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    database = await appDatabase.database;
    products = SqliteProductRepository(database);
    categories = SqliteCategoryRepository(database);
    categoryId = (await categories.create('Mga Ilimnon')).id;
  });
  tearDown(() => appDatabase.close());

  ProductDraft draft({
    int stock = 0,
    int purchase = 500,
    int selling = 900,
    String name = 'Nescafe',
    String photo = '/local/nescafe.jpg',
  }) => ProductDraft(
    categoryId: categoryId,
    name: name,
    photoPath: photo,
    purchasePriceCentavos: purchase,
    sellingPriceCentavos: selling,
    startingQuantity: stock,
    minimumStockLevel: 3,
  );

  test(
    'creates at zero then posts starting stock through INITIAL_STOCK',
    () async {
      final zero = await products.create(draft());
      expect(zero.currentQuantity, 0);
      expect(zero.sellingPriceCentavos, 900);
      expect(
        (await database.query(
          'product_selling_options',
          where: 'product_id=? AND is_default=1 AND is_archived=0',
          whereArgs: [zero.id],
        )).single['price_centavos'],
        900,
      );
      expect(
        await database.query(
          'inventory_movements',
          where: 'product_id = ?',
          whereArgs: [zero.id],
        ),
        isEmpty,
      );

      final stocked = await products.create(
        draft(stock: 12, name: 'Kape', photo: '/local/kape.jpg'),
      );
      expect(stocked.currentQuantity, 12);
      final movement = (await database.rawQuery(
        'SELECT m.*, t.type FROM inventory_movements m JOIN inventory_transactions t ON t.id = m.inventory_transaction_id WHERE m.product_id = ?',
        [stocked.id],
      )).single;
      expect(movement['type'], 'INITIAL_STOCK');
      expect(movement['quantity_before'], 0);
      expect(movement['quantity_after'], 12);
      expect(movement['quantity_change'], 12);
      expect(stocked.photoPath, '/local/kape.jpg');
    },
  );

  test('rejects all negative numeric values', () async {
    for (final invalid in [
      draft(stock: -1),
      draft(purchase: -1),
      draft(selling: -1),
      ProductDraft(
        categoryId: categoryId,
        name: 'X',
        photoPath: '/x.jpg',
        purchasePriceCentavos: 0,
        sellingPriceCentavos: 0,
        startingQuantity: 0,
        minimumStockLevel: -1,
      ),
    ]) {
      await expectLater(
        products.create(invalid),
        throwsA(isA<InvalidProductException>()),
      );
    }
    expect(await products.searchActive(), isEmpty);
  });

  test(
    'rejects archived category and archives product without deleting',
    () async {
      await categories.archive(categoryId);
      await expectLater(
        products.create(draft()),
        throwsA(isA<InvalidProductException>()),
      );

      categoryId = (await categories.create('Bag-o')).id;
      final product = await products.create(draft());
      await products.archive(product.id);
      expect(await products.searchActive(), isEmpty);
      expect(
        (await database.query(
          'products',
          where: 'id = ?',
          whereArgs: [product.id],
        )).single['is_archived'],
        1,
      );
    },
  );

  test(
    'search is case-insensitive, partial, and excludes archived products',
    () async {
      await products.create(draft(name: 'Nescafe Classic'));
      await products.create(draft(name: 'Sardinas', photo: '/s.jpg'));
      expect(
        (await products.searchActive('CAFE')).single.name,
        'Nescafe Classic',
      );
      expect(await products.searchActive('wala'), isEmpty);
    },
  );

  test(
    'price edit does not alter utang snapshot or historical reference',
    () async {
      final product = await products.create(draft(stock: 5));
      const now = '2026-09-02T00:00:00.000Z';
      final customerId = await database.insert('customers', {
        'full_name': 'Juan',
        'created_at': now,
        'updated_at': now,
      });
      final utangId = await UtangRepository(database).save(
        UtangDraft(
          customerId: customerId,
          items: [UtangItemDraft(productId: product.id, quantity: 1)],
        ),
      );
      await products.update(
        Product(
          id: product.id,
          categoryId: product.categoryId,
          name: product.name,
          photoPath: product.photoPath,
          purchasePriceCentavos: product.purchasePriceCentavos,
          sellingPriceCentavos: 1200,
          currentQuantity: 4,
          minimumStockLevel: product.minimumStockLevel,
          isArchived: false,
          createdAt: product.createdAt,
          updatedAt: product.updatedAt,
        ),
      );
      await products.archive(product.id);
      final item = (await database.query(
        'utang_transaction_items',
        where: 'utang_transaction_id = ?',
        whereArgs: [utangId],
      )).single;
      expect(item['unit_price_centavos'], 900);
      expect(item['product_id'], product.id);
    },
  );

  test(
    'failure during initial movement rolls back product and transaction',
    () async {
      await database.execute(
        "CREATE TRIGGER test_fail_initial BEFORE INSERT ON inventory_movements BEGIN SELECT RAISE(ABORT, 'TEST_FAILURE'); END",
      );
      await expectLater(
        products.create(draft(stock: 5)),
        throwsA(isA<DatabaseException>()),
      );
      expect(await database.query('products'), isEmpty);
      expect(await database.query('inventory_transactions'), isEmpty);
    },
  );

  test('stock display status is derived correctly', () {
    Product product(int quantity, int minimum) => Product(
      id: 1,
      categoryId: 1,
      name: 'X',
      photoPath: '/x',
      purchasePriceCentavos: 0,
      sellingPriceCentavos: 0,
      currentQuantity: quantity,
      minimumStockLevel: minimum,
      isArchived: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(product(0, 3).stockStatus, ProductStockStatus.outOfStock);
    expect(product(2, 3).stockStatus, ProductStockStatus.lowStock);
    expect(product(4, 3).stockStatus, ProductStockStatus.inStock);
  });
}
