import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/product_unit.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_unit_repository.dart';
import 'package:tindahan_ni_embi/repositories/reversal_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late Product oil;
  late int customerId;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    final category = (await SqliteCategoryRepository(db).create('Cooking Oil'))
        .id;
    oil = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category,
        name: 'Cooking Oil',
        photoPath: '/oil.jpg',
        purchasePriceCentavos: 30000,
        sellingPriceCentavos: 2500,
        startingQuantity: 1,
        minimumStockLevel: 250,
        unitConfiguration: ProductUnitPreset.forCategory('Cooking Oil', 2500),
      ),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    customerId = await db.insert('customers', {
      'full_name': 'Juan',
      'is_archived': 0,
      'created_at': now,
      'updated_at': now,
    });
  });
  tearDown(() => app.close());

  UtangItemDraft line(SellingOption option, int quantity) => UtangItemDraft(
    productId: oil.id,
    quantity: quantity,
    sellingOptionId: option.id,
    sellingOptionName: option.name,
    quantityValue: quantity,
    baseQuantityPerUnit: option.baseQuantity,
    baseUnitLabel: 'mL',
    unitPriceCentavos: option.priceCentavos,
  );

  test('Cash Lapad sale snapshots and deducts exact base stock', () async {
    final option = (await ProductUnitRepository(db).sellingOptions(oil.id))
        .firstWhere((x) => x.name == 'Lapad');
    final sale = await CashSaleRepository(db).saveWithResult([line(option, 2)]);
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [oil.id],
      )).single['current_quantity'],
      3285,
    );
    final item = (await db.query(
      'cash_sale_items',
      where: 'cash_sale_id=?',
      whereArgs: [sale.id],
    )).single;
    expect(item['selling_option_name_snapshot'], 'Lapad');
    expect(item['total_base_quantity'], 500);
    await ReversalRepository(db)
        .reverseCashSale(sale.id, 'Mistake', ownerPinAuthorized: true);
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [oil.id],
      )).single['current_quantity'],
      3785,
    );
  });

  test('Credit Half Lapad uses same conversion and remains atomic', () async {
    final option = (await ProductUnitRepository(db).sellingOptions(oil.id))
        .firstWhere((x) => x.name == 'Half Lapad');
    final id = await UtangRepository(db)
        .save(UtangDraft(customerId: customerId, items: [line(option, 3)]));
    final item = (await db.query(
      'utang_transaction_items',
      where: 'utang_transaction_id=?',
      whereArgs: [id],
    )).single;
    expect(item['total_base_quantity'], 375);
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [oil.id],
      )).single['current_quantity'],
      3410,
    );
  });

  test('measured rice arithmetic uses exact integers and half-up centavos', () {
    final draft = UtangItemDraft(
      productId: 1,
      quantity: 1,
      quantityValue: 15,
      quantityScale: 10,
      baseQuantityPerUnit: 1000,
      baseUnitLabel: 'g',
      unitPriceCentavos: 5500,
    );
    expect(draft.totalBaseQuantity, 1500);
    expect(draft.lineTotalCentavos(0), 8250);
  });

  test('1.5 kg Rice Credit deducts and reversal restores 1500 g', () async {
    final category = (await SqliteCategoryRepository(db).create('Rice')).id;
    final rice = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category,
        name: 'Rice',
        photoPath: '/rice.jpg',
        purchasePriceCentavos: 120000,
        sellingPriceCentavos: 5500,
        startingQuantity: 1,
        minimumStockLevel: 1000,
        unitConfiguration: ProductUnitPreset.forCategory('Rice', 5500),
      ),
    );
    final option = (await ProductUnitRepository(db).sellingOptions(rice.id))
        .single;
    final id = await UtangRepository(db).save(
      UtangDraft(
        customerId: customerId,
        items: [
          UtangItemDraft(
            productId: rice.id,
            quantity: 1,
            sellingOptionId: option.id,
            sellingOptionName: 'kg',
            quantityValue: 15,
            quantityScale: 10,
            baseQuantityPerUnit: 1000,
            baseUnitLabel: 'g',
            unitPriceCentavos: 5500,
          ),
        ],
      ),
    );
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [rice.id],
      )).single['current_quantity'],
      23500,
    );
    expect(
      (await db.query(
        'utang_transactions',
        where: 'id=?',
        whereArgs: [id],
      )).single['total_centavos'],
      8250,
    );
    expect(
      (await db.query(
        'inventory_movements',
        where: 'product_id=?',
        whereArgs: [rice.id],
        orderBy: 'id DESC',
        limit: 1,
      )).single['quantity_change'],
      -1500,
    );
    await ReversalRepository(db)
        .reverseUtang(id, 'Correction', ownerPinAuthorized: true);
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [rice.id],
      )).single['current_quantity'],
      25000,
    );
  });

  test('24-bottle case Cash reversal restores 24 bottles', () async {
    final category = (await SqliteCategoryRepository(db).create('Soft Drinks'))
        .id;
    final coke = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category,
        name: 'Coke',
        photoPath: '/coke.jpg',
        purchasePriceCentavos: 30000,
        sellingPriceCentavos: 1500,
        startingQuantity: 2,
        minimumStockLevel: 12,
        unitConfiguration: ProductUnitPreset.forCategory('Soft Drinks', 1500),
      ),
    );
    final option = (await ProductUnitRepository(db).sellingOptions(coke.id))
        .firstWhere((x) => x.name == 'Case');
    final sale = await CashSaleRepository(db).saveWithResult([
      UtangItemDraft(
        productId: coke.id,
        quantity: 1,
        sellingOptionId: option.id,
        sellingOptionName: option.name,
        baseQuantityPerUnit: 24,
        baseUnitLabel: 'bottle',
        unitPriceCentavos: option.priceCentavos,
      ),
    ]);
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [coke.id],
      )).single['current_quantity'],
      24,
    );
    await ReversalRepository(db)
        .reverseCashSale(sale.id, 'Correction', ownerPinAuthorized: true);
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [coke.id],
      )).single['current_quantity'],
      48,
    );
  });
}
