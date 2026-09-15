import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/product_unit.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/dashboard_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/reports_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
  });
  tearDown(() => app.close());
  test(
    'mixed-unit popularity counts sales, not grams or duplicate lines',
    () async {
      final category = await SqliteCategoryRepository(db).create('Ranking');
      final products = <Product>[];
      for (final name in ['Egg', 'Rice', 'Oil']) {
        products.add(
          await SqliteProductRepository(db).create(
            ProductDraft(
              categoryId: category.id,
              name: name,
              photoPath: '/test-product',
              purchasePriceCentavos: 1,
              sellingPriceCentavos: 2,
              startingQuantity: 5000,
              minimumStockLevel: 1,
            ),
          ),
        );
      }
      await db.update(
        'products',
        {'base_unit_code': 'GRAM'},
        where: 'id=?',
        whereArgs: [products[1].id],
      );
      await db.update(
        'products',
        {'base_unit_code': 'MILLILITER'},
        where: 'id=?',
        whereArgs: [products[2].id],
      );
      final stamp = DateTime.now().toUtc().toIso8601String();
      for (var sale = 0; sale < 4; sale++) {
        final id = await db.insert('cash_sales', {
          'reference': 'RANK-$sale',
          'total_centavos': 2000,
          'status': 'POSTED',
          'occurred_at': stamp,
          'created_at': stamp,
        });
        final product = products[sale < 2 ? 0 : sale - 1];
        final qty = sale < 2 ? 1 : 1000;
        for (var line = 0; line < (sale == 0 ? 2 : 1); line++) {
          await db.insert('cash_sale_items', {
            'cash_sale_id': id,
            'product_id': product.id,
            'product_name_snapshot': product.name,
            'unit_price_centavos': 2,
            'quantity': qty,
            'total_base_quantity': qty,
            'line_total_centavos': qty * 2,
            'created_at': stamp,
          });
        }
      }
      final rows = await ReportsRepository(db).frequentProducts();
      expect(rows.first['name'], 'Egg');
      expect(rows.first['sale_count'], 2);
      expect(rows.first['quantity'], 3);
      expect(rows[1]['sale_count'], 1);
      expect(rows[2]['sale_count'], 1);
      final daily = await OperationsRepository(db).daily(DateTime.now());
      expect(
        daily.topProducts.map((r) => r['product_id']),
        rows.map((r) => r['product_id']),
      );
      await db.update(
        'cash_sales',
        {'status': 'REVERSED'},
        where: 'reference IN (?,?)',
        whereArgs: ['RANK-0', 'RANK-1'],
      );
      expect(
        (await ReportsRepository(
          db,
        ).frequentProducts()).any((r) => r['name'] == 'Egg'),
        isFalse,
      );
    },
  );
  test('dashboard and reports return correct live totals', () async {
    final cat = (await SqliteCategoryRepository(db).create('C')).id;
    final products = SqliteProductRepository(db);
    final a = await products.create(
      ProductDraft(
        categoryId: cat,
        name: 'A',
        photoPath: '/a',
        purchasePriceCentavos: 500,
        sellingPriceCentavos: 1000,
        startingQuantity: 5,
        minimumStockLevel: 2,
      ),
    );
    await products.create(
      ProductDraft(
        categoryId: cat,
        name: 'B',
        photoPath: '/b',
        purchasePriceCentavos: 200,
        sellingPriceCentavos: 300,
        startingQuantity: 0,
        minimumStockLevel: 1,
      ),
    );
    final customer = await SqliteCustomerRepository(db)
        .create(const CustomerDraft(fullName: 'Juan'));
    await UtangRepository(db).save(
      UtangDraft(
        customerId: customer.id,
        items: [UtangItemDraft(productId: a.id, quantity: 2)],
      ),
    );
    await PaymentRepository(db)
        .record(customerId: customer.id, amountCentavos: 500);
    await CashSaleRepository(db)
        .save([UtangItemDraft(productId: a.id, quantity: 1)]);
    final summary = await DashboardRepository(db).summary();
    expect(summary.products, 2);
    expect(summary.lowStock, 1);
    expect(summary.outOfStock, 1);
    expect(summary.outstandingCentavos, 1500);
    expect(summary.stockOutToday, 3);
    expect(summary.inventoryValueCentavos, 1000);
    final reports = ReportsRepository(db);
    expect(await reports.outstandingTotal(), 1500);
    final periods = await reports.salesPeriods();
    expect(periods.daily, 1000);
    expect(periods.weekly, 1000);
    expect(periods.monthly, 1000);
    expect((await reports.frequentProducts()).single['quantity'], 3);
    expect((await reports.frequentProducts()).single['sale_count'], 2);
    expect(await reports.frequentProductIds(), [a.id]);
    await db.update(
      'products',
      {'name': 'Renamed A'},
      where: 'id = ?',
      whereArgs: [a.id],
    );
    expect(await reports.frequentProductIds(), [a.id]);
    expect((await reports.inventory()).length, 2);
    final old = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 31))
        .toIso8601String();
    await db.update('cash_sales', {'occurred_at': old});
    await db.update('utang_transactions', {'occurred_at': old});
    expect(await reports.frequentProductIds(), isEmpty);
  });

  test('sales report honors day, calendar week and month boundaries', () async {
    Future<void> sale(int amount, String occurred) => db.insert('cash_sales', {
      'total_centavos': amount,
      'status': 'POSTED',
      'occurred_at': occurred,
      'created_at': occurred,
    });
    await sale(100, '2026-09-02T02:00:00.000Z');
    await sale(300, '2026-09-01T02:00:00.000Z');
    await sale(500, '2026-08-31T02:00:00.000Z');
    final summary = await ReportsRepository(db)
        .salesPeriods(now: DateTime(2026, 9, 2, 12));
    expect(summary.daily, 100);
    expect(summary.weekly, 900);
    expect(summary.monthly, 400);
  });

  test('inventory report values measured stock by purchase package', () async {
    final category = (await SqliteCategoryRepository(db).create('Rice')).id;
    final product = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category,
        name: 'Ganador',
        photoPath: '/rice',
        purchasePriceCentavos: 160000,
        sellingPriceCentavos: 8000,
        startingQuantity: 2,
        minimumStockLevel: 1000,
        unitConfiguration: const ProductUnitConfiguration(
          baseUnit: BaseUnit.gram,
          purchasePackages: [
            PurchasePackageDraft(
              name: '25 kg Sack',
              baseQuantity: 25000,
              isDefault: true,
            ),
          ],
          sellingOptions: [
            SellingOptionDraft(
              name: '1 kg',
              baseQuantity: 1000,
              priceCentavos: 8000,
              isDefault: true,
            ),
          ],
        ),
      ),
    );
    await InventoryRepository(db).adjust(
      productId: product.id,
      quantityChange: -6000,
      reason: 'Test 44 kg remaining',
    );

    final row = (await ReportsRepository(db).inventory()).single;
    expect(row['current_quantity'], 44000);
    expect(row['purchase_package_quantity'], 25000);
    expect(row['stock_value'], 281600);
  });
}
