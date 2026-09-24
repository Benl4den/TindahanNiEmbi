import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_insights_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';

void main() {
  sqfliteFfiInit();

  test(
    'insights use posted sales, historical costs, and real restocks',
    () async {
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final db = await app.database;
      final category = await SqliteCategoryRepository(db).create('Test snacks');
      final products = SqliteProductRepository(db);
      final product = await products.create(
        ProductDraft(
          categoryId: category.id,
          name: 'Test snack',
          photoPath: '/test/product.png',
          purchasePriceCentavos: 300,
          sellingPriceCentavos: 500,
          startingQuantity: 10,
          minimumStockLevel: 2,
        ),
      );
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 2)]);
      await InventoryRepository(db)
          .stockIn(productId: product.id, quantity: 5, unitCostCentavos: 400);
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 1)]);
      final current = (await products.searchActive()).single;
      final insights = await ProductInsightsRepository(db).load(
        current,
        ProductInsightsRange.last7Days,
        now: DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(insights.soldBaseQuantity, 3);
      expect(insights.totalSalesCentavos, 1500);
      expect(insights.grossProfitCentavos, 500);
      expect(insights.profitMargin, closeTo(33.33, 0.1));
      expect(insights.restockFrequency, 1);
      expect(insights.recentRestockUnitCostsCentavos, [400]);
      expect(insights.estimatedDaysOfStock, isNotNull);

      final later = DateTime.now().add(const Duration(days: 10));
      expect(
        (await ProductInsightsRepository(db).load(
          current,
          ProductInsightsRange.last7Days,
          now: later,
        )).soldBaseQuantity,
        0,
      );
      expect(
        (await ProductInsightsRepository(db).load(
          current,
          ProductInsightsRange.last30Days,
          now: later,
        )).soldBaseQuantity,
        3,
      );
    },
  );

  test('new product has finite, owner-friendly empty insights', () async {
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await app.database;
    final category = await SqliteCategoryRepository(db).create('Test goods');
    final product = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category.id,
        name: 'New item',
        photoPath: '/test/product.png',
        purchasePriceCentavos: 100,
        sellingPriceCentavos: 150,
        startingQuantity: 0,
        minimumStockLevel: 2,
      ),
    );
    final insights = await ProductInsightsRepository(db)
        .load(product, ProductInsightsRange.last30Days);
    expect(insights.soldBaseQuantity, 0);
    expect(insights.totalSalesCentavos, 0);
    expect(insights.grossProfitCentavos, 0);
    expect(insights.estimatedDaysOfStock, isNull);
    expect(insights.performance, 'No recent sales');
  });
}
