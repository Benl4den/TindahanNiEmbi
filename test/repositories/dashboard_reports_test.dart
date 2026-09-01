import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/dashboard_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/reports_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

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
    expect((await reports.frequentProducts()).single['quantity'], 1);
    expect((await reports.inventory()).length, 2);
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
}
