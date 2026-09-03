import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/product_unit.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_unit_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late int productId;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    final category = (await SqliteCategoryRepository(db).create('Cooking Oil'))
        .id;
    productId = (await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category,
        name: 'Cooking Oil',
        photoPath: '/oil.jpg',
        purchasePriceCentavos: 30000,
        sellingPriceCentavos: 2000,
        startingQuantity: 0,
        minimumStockLevel: 250,
      ),
    )).id;
  });
  tearDown(() => app.close());

  test('configures gallon and fixed Lapad portions', () async {
    final units = ProductUnitRepository(db);
    await units.configure(
      productId: productId,
      baseUnit: BaseUnit.milliliter,
      purchasePackages: [(name: 'Gallon', baseQuantity: 3785, isDefault: true)],
      sellingOptions: [
        (
          name: 'Half Lapad',
          baseQuantity: 125,
          priceCentavos: 1000,
          isDefault: false,
        ),
        (
          name: 'Lapad',
          baseQuantity: 250,
          priceCentavos: 2000,
          isDefault: true,
        ),
      ],
    );
    expect((await units.purchasePackages(productId)).single.baseQuantity, 3785);
    expect(
      (await units.sellingOptions(productId)).map((x) => x.baseQuantity),
      containsAll([125, 250]),
    );
  });

  test(
    'receiving two gallons atomically posts 7570 mL with snapshot',
    () async {
      final units = ProductUnitRepository(db);
      await units.configure(
        productId: productId,
        baseUnit: BaseUnit.milliliter,
        purchasePackages: [
          (name: 'Gallon', baseQuantity: 3785, isDefault: true),
        ],
        sellingOptions: [
          (
            name: 'Lapad',
            baseQuantity: 250,
            priceCentavos: 2000,
            isDefault: true,
          ),
        ],
      );
      final package = (await units.purchasePackages(productId)).single;
      await units.receive(
        productId: productId,
        packageId: package.id,
        packageCount: 2,
        packageCostCentavos: 50000,
      );
      expect(
        (await db.query(
          'products',
          where: 'id=?',
          whereArgs: [productId],
        )).single['current_quantity'],
        7570,
      );
      final movement = (await db.query('inventory_movements')).single;
      expect(movement, containsPair('entered_quantity', 2));
      expect(movement, containsPair('base_quantity_per_entered_unit', 3785));
      expect(movement, containsPair('unit_cost_centavos', 50000));
    },
  );

  test('invalid package receiving changes nothing', () async {
    final units = ProductUnitRepository(db);
    final before = await db.query('inventory_movements');
    await expectLater(
      units.receive(productId: productId, packageId: 999, packageCount: 1),
      throwsA(isA<InvalidProductUnit>()),
    );
    expect(await db.query('inventory_movements'), before);
    expect(await db.query('inventory_transactions'), isEmpty);
  });

  test('category presets use exact integer sari-sari conversions', () {
    final rice = ProductUnitPreset.forCategory('Rice', 5000);
    expect(rice.baseUnit, BaseUnit.gram);
    expect(rice.purchasePackages.map((x) => x.baseQuantity), [25000, 50000]);
    final drinks = ProductUnitPreset.forCategory('Soft Drinks', 1500);
    expect(drinks.purchasePackages.single.baseQuantity, 24);
    final bigDrink = ProductUnitConfiguration(
      baseUnit: BaseUnit.bottle,
      purchasePackages: const [
        PurchasePackageDraft(
          name: 'Big Bottle Case',
          baseQuantity: 12,
          isDefault: true,
        ),
      ],
      sellingOptions: const [
        SellingOptionDraft(
          name: 'Bottle',
          baseQuantity: 1,
          priceCentavos: 2500,
          isDefault: true,
        ),
      ],
    );
    expect(bigDrink.purchasePackages.single.baseQuantity, 12);
    final oil = ProductUnitPreset.forCategory('Cooking Oil', 2000);
    expect(oil.purchasePackages.single.baseQuantity, 3785);
    expect(oil.sellingOptions.map((x) => x.baseQuantity), [250, 125]);
    expect(oil.sellingOptions.first.isDefault, isTrue);
    final cigarettes = ProductUnitPreset.forCategory('Cigarettes', 800);
    expect(cigarettes.baseUnit, BaseUnit.stick);
    expect(cigarettes.sellingOptions.map((x) => x.priceCentavos), [800, 800]);
    final independentPrices = ProductUnitConfiguration(
      baseUnit: BaseUnit.stick,
      purchasePackages: const [
        PurchasePackageDraft(name: 'Pack', baseQuantity: 20, isDefault: true),
      ],
      sellingOptions: const [
        SellingOptionDraft(
          name: 'Stick',
          baseQuantity: 1,
          priceCentavos: 800,
          isDefault: true,
        ),
        SellingOptionDraft(
          name: 'Pack',
          baseQuantity: 20,
          priceCentavos: 14500,
        ),
      ],
    );
    expect(independentPrices.sellingOptions.map((x) => x.priceCentavos), [
      800,
      14500,
    ]);
    expect(
      ProductUnitPreset.forCategory('My Custom Category', 100).baseUnit,
      BaseUnit.piece,
    );
  });

  test(
    'configured product creation converts starting packages atomically',
    () async {
      final category = (await SqliteCategoryRepository(
        db,
      ).create('Soft Drinks')).id;
      final product = await SqliteProductRepository(db).create(
        ProductDraft(
          categoryId: category,
          name: 'Cola Mismo',
          photoPath: '/cola.jpg',
          purchasePriceCentavos: 25000,
          sellingPriceCentavos: 1500,
          startingQuantity: 2,
          minimumStockLevel: 12,
          unitConfiguration: ProductUnitPreset.forCategory('Soft Drinks', 1500),
        ),
      );
      expect(product.currentQuantity, 48);
      final movement = (await db.query(
        'inventory_movements',
        where: 'product_id=?',
        whereArgs: [product.id],
      )).single;
      expect(movement['entered_unit_snapshot'], 'Case');
      expect(movement['base_quantity_per_entered_unit'], 24);
      final reloaded = await SqliteProductRepository(db)
          .unitConfiguration(product.id);
      expect(
        reloaded.sellingOptions.map((x) => x.name),
        containsAll(['Bottle', 'Case']),
      );
    },
  );
}
