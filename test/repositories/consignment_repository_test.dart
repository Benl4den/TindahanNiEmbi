import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/consignment.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/consignment_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_unit_repository.dart';
import 'package:tindahan_ni_embi/models/product_unit.dart';
import 'package:tindahan_ni_embi/repositories/special_inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late ConsignmentRepository consignment;
  late Product product;
  late int consignor;

  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    final category = await SqliteCategoryRepository(db).create('Drinks');
    product = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category.id,
        name: 'Bottle',
        photoPath: '/bottle.jpg',
        purchasePriceCentavos: 0,
        sellingPriceCentavos: 300,
        startingQuantity: 0,
        minimumStockLevel: 2,
      ),
    );
    consignment = ConsignmentRepository(db);
    consignor = await consignment.createConsignor('ABC Trading');
  });
  tearDown(() => app.close());

  Future<int> receive({
    required int units,
    required int cost,
    required int sell,
  }) => consignment.receive(
    ConsignmentReceiptDraft(
      consignorId: consignor,
      productId: product.id,
      boxes: 1,
      unitsPerBox: units,
      unitCostCentavos: cost,
      sellingPriceCentavos: sell,
    ),
  );

  test('delivery reads all saved packages and authoritative price, not category defaults', () async {
    await ProductUnitRepository(db).configure(
      productId: product.id,
      baseUnit: BaseUnit.bottle,
      purchasePackages: [
        (name: 'Crate', baseQuantity: 12, isDefault: true),
        (name: 'Small Pack', baseQuantity: 4, isDefault: false),
      ],
      sellingOptions: [
        (name: 'Bottle', baseQuantity: 1, priceCentavos: 4500, isDefault: true),
        (
          name: 'Crate',
          baseQuantity: 12,
          priceCentavos: 50000,
          isDefault: false,
        ),
      ],
    );
    final config = await consignment.deliveryConfiguration(product.id);
    expect(config.baseUnit, BaseUnit.bottle);
    expect(config.purchasePackages.map((p) => p.baseQuantity), [12, 4]);
    expect(
      config.sellingOptions.singleWhere((p) => p.isDefault).priceCentavos,
      4500,
    );
    await SqliteProductRepository(db).archive(product.id);
    await expectLater(
      consignment.deliveryConfiguration(product.id),
      throwsA(isA<InvalidConsignmentOperation>()),
    );
  });

  test('measured supplier cost remains exact through FIFO payable', () async {
    await consignment.receive(
      ConsignmentReceiptDraft(
        consignorId: consignor,
        productId: product.id,
        boxes: 1,
        unitsPerBox: 2000,
        unitCostCentavos: 7500,
        supplierCostBasisQuantity: 1000,
        packageName: '2 kg Sack',
        baseUnitLabel: 'g',
        priceUnitName: '1 kg',
        sellingPriceCentavos: 10000,
      ),
    );
    final batch = (await db.query('consignment_batches')).single;
    expect(batch['supplier_cost_centavos'], 7500);
    expect(batch['supplier_cost_basis_quantity'], 1000);
    expect(batch['package_name'], '2 kg Sack');
    expect((await consignment.summary()).inventoryValueCentavos, 15000);

    await CashSaleRepository(db)
        .save([UtangItemDraft(productId: product.id, quantity: 1000)]);
    final allocation = (await db.query('consignment_allocations')).single;
    expect(allocation['actual_payable_centavos'], 7500);
    expect((await consignment.payableByConsignor())[consignor], 7500);
    expect((await consignment.summary()).inventoryValueCentavos, 7500);
  });

  test(
    'V6 installs reusable groups and Selecta shares product stock truth',
    () async {
      expect(
        (await db.query('inventory_groups')).map((x) => x['code']),
        containsAll(['SELECTA', 'CONSIGNMENT']),
      );
      await SpecialInventoryRepository(db).assign(product.id, 'SELECTA');
      await receive(units: 4, cost: 200, sell: 300);
      expect(
        (await SpecialInventoryRepository(db).products('SELECTA'))
            .single
            .currentQuantity,
        4,
      );
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 2)]);
      expect(
        (await SpecialInventoryRepository(db).products('SELECTA'))
            .single
            .currentQuantity,
        2,
      );
      expect((await db.query('inventory_movements')).length, 2);
    },
  );

  test(
    'company product history and return batches exclude other consignors',
    () async {
      await receive(units: 4, cost: 200, sell: 300);
      final other = await consignment.createConsignor('Other company');
      await consignment.receive(
        ConsignmentReceiptDraft(
          consignorId: other,
          productId: product.id,
          boxes: 1,
          unitsPerBox: 9,
          unitCostCentavos: 100,
          sellingPriceCentavos: 300,
        ),
      );
      expect(await consignment.productHistory(product.id), hasLength(2));
      final history = await consignment.productHistory(
        product.id,
        consignorId: consignor,
      );
      expect(history, hasLength(1));
      expect(history.single['quantity'], 4);
      final batches = await consignment.returnableBatches(
        product.id,
        consignorId: consignor,
      );
      expect(batches, hasLength(1));
      expect(batches.single['available'], 4);
      expect(await consignment.returnableBatches(product.id), hasLength(2));
    },
  );

  test(
    'managed brands reuse products and removal only changes membership',
    () async {
      final special = SpecialInventoryRepository(db);
      final brand = await special.createBrand('San Miguel');
      await special.assign(product.id, brand.code);
      expect((await special.products(brand.code)).single.id, product.id);
      expect((await db.query('products')), hasLength(1));

      await special.remove(product.id, brand.code);

      expect(await special.products(brand.code), isEmpty);
      expect((await db.query('products')).single['is_archived'], 0);
      expect((await db.query('products')).single['current_quantity'], 0);
    },
  );

  test(
    'company cards and active product list exclude archived products',
    () async {
      await receive(units: 5, cost: 100, sell: 300);
      var companies = await consignment.companyCards();
      expect(companies.single['product_count'], 1);
      expect(
        await consignment.productCardsForConsignor(consignor),
        hasLength(1),
      );

      await SqliteProductRepository(db).archive(product.id);

      companies = await consignment.companyCards();
      expect(companies.single['product_count'], 0);
      expect(await consignment.productCardsForConsignor(consignor), isEmpty);
    },
  );

  test(
    'receipt math, FIFO historical costs, payable and margin are preserved',
    () async {
      await receive(units: 5, cost: 100, sell: 300);
      await receive(units: 5, cost: 200, sell: 400);
      expect((await db.query('products')).single['current_quantity'], 10);
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 7)]);
      final allocations = await db.query(
        'consignment_allocations',
        orderBy: 'id',
      );
      expect(allocations.map((x) => x['quantity']), [5, 2]);
      expect(allocations.map((x) => x['unit_cost_centavos']), [100, 200]);
      final summary = await consignment.summary();
      expect(summary.payableCentavos, 900);
      expect(summary.marginCentavos, 1900);
      expect(summary.remainingUnits, 3);
    },
  );

  test(
    'UTANG posts supplier liability independently of customer payment',
    () async {
      await receive(units: 3, cost: 250, sell: 400);
      final customer = await SqliteCustomerRepository(db)
          .create(const CustomerDraft(fullName: 'Juan'));
      await UtangRepository(db).save(
        UtangDraft(
          customerId: customer.id,
          items: [UtangItemDraft(productId: product.id, quantity: 2)],
        ),
      );
      expect((await consignment.summary()).payableCentavos, 500);
      expect(
        (await db.query('customer_ledger_entries'))
            .single['amount_change_centavos'],
        800,
      );
      expect((await db.query('products')).single['current_quantity'], 1);
    },
  );

  test('partial/full remittance and over-remittance integrity', () async {
    await receive(units: 3, cost: 200, sell: 300);
    await CashSaleRepository(db)
        .save([UtangItemDraft(productId: product.id, quantity: 3)]);
    await consignment.remit(consignorId: consignor, amountCentavos: 250);
    expect((await consignment.summary()).payableCentavos, 350);
    await expectLater(
      consignment.remit(consignorId: consignor, amountCentavos: 351),
      throwsA(isA<InvalidConsignmentOperation>()),
    );
    await consignment.remit(consignorId: consignor, amountCentavos: 350);
    expect((await consignment.summary()).payableCentavos, 0);
  });

  test('return reduces stock without payable and rejects excess', () async {
    final batch = await receive(units: 8, cost: 200, sell: 300);
    await consignment.returnUnits(batchId: batch, quantity: 3);
    expect((await db.query('products')).single['current_quantity'], 5);
    expect((await consignment.summary()).payableCentavos, 0);
    await expectLater(
      consignment.returnUnits(batchId: batch, quantity: 6),
      throwsA(isA<InvalidConsignmentOperation>()),
    );
    expect((await db.query('consignment_returns')).length, 1);
  });

  test(
    'failed sale rolls back stock, sale, allocation and supplier ledger',
    () async {
      await receive(units: 2, cost: 200, sell: 300);
      await expectLater(
        CashSaleRepository(db)
            .save([UtangItemDraft(productId: product.id, quantity: 3)]),
        throwsStateError,
      );
      expect(await db.query('cash_sales'), isEmpty);
      expect(await db.query('consignment_allocations'), isEmpty);
      expect(await db.query('consignor_ledger_entries'), isEmpty);
      expect((await db.query('products')).single['current_quantity'], 2);
    },
  );

  test('new product receipt creates stock exactly once', () async {
    final category = (await db.query('categories')).single['id']! as int;
    await consignment.receiveNewProduct(
      product: ProductDraft(
        categoryId: category,
        name: 'New Juice',
        photoPath: '/juice.jpg',
        purchasePriceCentavos: 0,
        sellingPriceCentavos: 450,
        startingQuantity: 99,
        minimumStockLevel: 3,
      ),
      consignorId: consignor,
      boxes: 2,
      unitsPerBox: 12,
      unitCostCentavos: 400,
      sellingPriceCentavos: 450,
    );
    final created = (await db.query(
      'products',
      where: 'name=?',
      whereArgs: ['New Juice'],
    )).single;
    expect(created['current_quantity'], 24);
    expect(created['selling_price_centavos'], 450);
    expect(
      (await db.query(
        'product_selling_options',
        where: 'product_id=? AND is_default=1 AND is_archived=0',
        whereArgs: [created['id']],
      )).single['price_centavos'],
      450,
    );
    expect(
      (await db.query(
        'inventory_movements',
        where: 'product_id=?',
        whereArgs: [created['id']],
      )).length,
      1,
    );
    expect(
      (await SpecialInventoryRepository(db).products('CONSIGNMENT'))
          .map((p) => p.name),
      contains('New Juice'),
    );
    expect(
      (await SqliteProductRepository(db).searchActive()).map((p) => p.name),
      contains('New Juice'),
    );
    await expectLater(
      InventoryRepository(db)
          .stockIn(productId: created['id']! as int, quantity: 1),
      throwsA(isA<InvalidInventoryOperation>()),
    );
  });

  test('failed new product receipt leaves no orphan product', () async {
    final category = (await db.query('categories')).single['id']! as int;
    await expectLater(
      consignment.receiveNewProduct(
        product: ProductDraft(
          categoryId: category,
          name: 'Orphan',
          photoPath: '/o.jpg',
          purchasePriceCentavos: 0,
          sellingPriceCentavos: 100,
          startingQuantity: 0,
          minimumStockLevel: 0,
        ),
        consignorId: consignor,
        boxes: 0,
        unitsPerBox: 12,
        unitCostCentavos: 50,
        sellingPriceCentavos: 100,
      ),
      throwsA(isA<InvalidConsignmentOperation>()),
    );
    expect(
      await db.query('products', where: 'name=?', whereArgs: ['Orphan']),
      isEmpty,
    );
  });
}
