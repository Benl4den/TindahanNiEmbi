import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/special_inventory/presentation/selecta_screen.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/brand_analytics_repository.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/special_inventory_repository.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';
import 'package:tindahan_ni_embi/services/product_photo_service.dart';
import 'package:tindahan_ni_embi/widgets/product_image.dart';

class _ProSource extends AppPlanSource {
  @override
  AppPlan get plan => AppPlan.pro;
  @override
  Future<AppPlan> load() async => AppPlan.pro;
}

void main() {
  sqfliteFfiInit();

  for (final variant in [
    (
      size: const Size(1600, 1000),
      theme: AppTheme.dark,
      name: 'dark landscape',
    ),
    (
      size: const Size(700, 1100),
      theme: AppTheme.light,
      name: 'light portrait',
    ),
  ]) {
    testWidgets('Selecta dashboard ${variant.name} and safe removal', (
      tester,
    ) async {
      tester.view.physicalSize = variant.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final db = await tester.runAsync(() => app.database);
      if (db == null) throw StateError('Test database did not open.');
      final special = SpecialInventoryRepository(db);
      final products = SqliteProductRepository(db);
      final categories = SqliteCategoryRepository(db);
      final product = await tester.runAsync(() async {
        final category = await categories.create('Ice & Frozen Treats');
        final created = await products.create(
          ProductDraft(
            categoryId: category.id,
            name: 'Corneto Vanilla Extra Long Product Name',
            photoPath: '/corneto',
            purchasePriceCentavos: variant.name == 'light portrait'
                ? 100000000
                : 1800,
            sellingPriceCentavos: variant.name == 'light portrait'
                ? 123456789
                : 2500,
            startingQuantity: 12,
            minimumStockLevel: 2,
          ),
        );
        await special.assign(created.id, 'SELECTA');
        await CashSaleRepository(db)
            .save([UtangItemDraft(productId: created.id, quantity: 1)]);
        final unrelated = await products.create(
          ProductDraft(
            categoryId: category.id,
            name: 'Unbranded Product',
            photoPath: '/unbranded',
            purchasePriceCentavos: 3600,
            sellingPriceCentavos: 5000,
            startingQuantity: 2,
            minimumStockLevel: 1,
          ),
        );
        await CashSaleRepository(db)
            .save([UtangItemDraft(productId: unrelated.id, quantity: 1)]);
        return created;
      });
      if (product == null) throw StateError('Test product was not created.');
      await tester.pumpWidget(
        MaterialApp(
          theme: variant.theme,
          home: SelectaScreen(
            special: special,
            products: products,
            inventory: InventoryRepository(db),
            categories: categories,
            photoService: LocalProductPhotoService(),
            analytics: BrandAnalyticsRepository(db),
            access: FeatureAccessService(
              db,
              planController: AppPlanController(_ProSource()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text('Products in Selecta'), findsOneWidget);
      expect(find.text('Brand Performance'), findsOneWidget);
      expect(find.text('Ice cream and frozen treats'), findsOneWidget);
      expect(find.text('Assign Existing Products'), findsOneWidget);
      expect(find.text('Add New Product'), findsOneWidget);
      expect(find.text('Brand Performance'), findsOneWidget);
      expect(find.text('Cost of Sold Products'), findsOneWidget);
      expect(find.text('Gross Profit'), findsOneWidget);
      expect(find.text('Units Sold'), findsOneWidget);
      expect(find.text('Performance Insights'), findsOneWidget);
      expect(find.text('Profit Margin'), findsOneWidget);
      expect(find.text('Top Product'), findsOneWidget);
      expect(find.text('Sales This Month'), findsOneWidget);
      expect(find.text('Stock Health'), findsOneWidget);
      expect(
        find.text(
          variant.name == 'light portrait' ? '₱1,234,567.89' : '₱25.00',
        ),
        findsWidgets,
      );
      expect(find.text('₱50.00'), findsNothing);
      expect(find.text('Products in Selecta'), findsOneWidget);
      expect(find.text('1 product'), findsOneWidget);
      expect(find.text('Stock In'), findsOneWidget);
      expect(find.text('Sale History'), findsOneWidget);
      expect(find.byType(ProductImage), findsNothing);
      expect(tester.takeException(), isNull);

      if (variant.name == 'dark landscape') {
        await tester.tap(find.text('This Month'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Last Month').first);
        await tester.pump();
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        expect(find.text('No sales yet'), findsOneWidget);
        await tester.tap(find.text('Last Month').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('This Month').last);
        await tester.pump();
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }

      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'not a product');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('No matching products found.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      await tester.ensureVisible(find.text('Low Stock'));
      await tester.tap(find.text('Low Stock'));
      await tester.pump();
      expect(find.text('No matching products found.'), findsOneWidget);
      await tester.tap(find.text('All'));
      await tester.pump();
      await tester.tap(find.byTooltip('Sort products, currently Name'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price').last);
      await tester.pump();
      expect(find.byTooltip('Sort products, currently Price'), findsOneWidget);

      await tester.ensureVisible(find.text('Sale History'));
      await tester.tap(find.text('Sale History'));
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.textContaining('Sales History'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byTooltip('More product actions'));
      await tester.tap(find.byTooltip('More product actions'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Product'), findsOneWidget);
      expect(find.text('View Sale History'), findsOneWidget);
      expect(find.text('Remove from Selecta'), findsOneWidget);
      await tester.tap(find.text('Remove from Selecta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from Brand'));
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text('No products assigned to Selecta yet.'), findsOneWidget);
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text('No sales yet'), findsOneWidget);
      expect(find.text('₱0.00'), findsWidgets);
      expect(
        (await tester.runAsync(() => special.products('SELECTA'))),
        isEmpty,
      );
      expect(
        (await tester.runAsync(
          () => db.query('products', where: 'id=?', whereArgs: [product.id]),
        ))?.single['is_archived'],
        0,
      );
      expect(
        (await tester.runAsync(() => special.productSalesHistory(product.id)))
            ?.length,
        1,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
