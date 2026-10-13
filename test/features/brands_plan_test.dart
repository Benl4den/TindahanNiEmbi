import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/special_inventory/presentation/managed_brands_screen.dart';
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

class _PlanSource extends AppPlanSource {
  AppPlan current = AppPlan.free;
  @override
  AppPlan get plan => current;
  @override
  Future<AppPlan> load() async => current;
  void change(AppPlan plan) {
    current = plan;
    notifyListeners();
  }
}

void main() {
  sqfliteFfiInit();
  testWidgets('Brands overview ignores Selecta sales for an empty brand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 800);
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
    await tester.runAsync(() async {
      await special.createBrand('New Brand');
      final category = await categories.create('Ice Cream');
      final product = await products.create(
        ProductDraft(
          categoryId: category.id,
          name: 'Selecta Item',
          photoPath: '/selecta',
          purchasePriceCentavos: 3600,
          sellingPriceCentavos: 5000,
          startingQuantity: 2,
          minimumStockLevel: 1,
        ),
      );
      await special.assign(product.id, 'SELECTA');
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 1)]);
    });
    final source = _PlanSource()..current = AppPlan.pro;
    await tester.pumpWidget(
      MaterialApp(
        home: ManagedBrandsScreen(
          special: special,
          products: products,
          inventory: InventoryRepository(db),
          categories: categories,
          photoService: LocalProductPhotoService(),
          analytics: BrandAnalyticsRepository(db),
          access: FeatureAccessService(
            db,
            planController: AppPlanController(source),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    for (final width in [280.0, 320.0, 390.0, 700.0, 1400.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Brands at ${width}dp');
    }
    tester.view.physicalSize = const Size(280, 800);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('New Brand'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('New Brand'), findsOneWidget);
    expect(find.text('0 products'), findsWidgets);
    expect(find.text('₱0.00'), findsNWidgets(2));
    expect(find.text('Sales  ₱0.00'), findsOneWidget);
    expect(find.text('Profit  ₱0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Brands hides saved records on Free and restores them on Pro', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
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
    await tester.runAsync(() => special.createBrand('Private Brand'));
    final source = _PlanSource();
    await tester.pumpWidget(
      MaterialApp(
        home: ManagedBrandsScreen(
          special: special,
          products: SqliteProductRepository(db),
          inventory: InventoryRepository(db),
          categories: SqliteCategoryRepository(db),
          photoService: LocalProductPhotoService(),
          analytics: BrandAnalyticsRepository(db),
          access: FeatureAccessService(
            db,
            planController: AppPlanController(source),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PRO FEATURE'), findsOneWidget);
    expect(find.text('Private Brand'), findsNothing);
    expect(find.text('Preview Pro'), findsOneWidget);

    source.change(AppPlan.pro);
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Private Brand'), findsOneWidget);
    expect(find.text('Build your next product collection'), findsNothing);
    expect(find.text('Add Brand'), findsOneWidget);

    source.change(AppPlan.free);
    await tester.pumpAndSettle();
    expect(find.text('Private Brand'), findsNothing);
    expect((await tester.runAsync(() => special.managedBrands()))?.length, 1);
  });

  testWidgets('an empty Pro brand list offers Add Brand', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
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
    final source = _PlanSource()..current = AppPlan.pro;
    await tester.pumpWidget(
      MaterialApp(
        home: ManagedBrandsScreen(
          special: SpecialInventoryRepository(db),
          products: SqliteProductRepository(db),
          inventory: InventoryRepository(db),
          categories: SqliteCategoryRepository(db),
          photoService: LocalProductPhotoService(),
          analytics: BrandAnalyticsRepository(db),
          access: FeatureAccessService(
            db,
            planController: AppPlanController(source),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No brands yet'), findsOneWidget);
    expect(find.text('Add Brand'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Selecta appears in Managed Brands only after adding it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 900);
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
    final source = _PlanSource()..current = AppPlan.pro;
    await tester.pumpWidget(
      MaterialApp(
        home: ManagedBrandsScreen(
          special: special,
          products: SqliteProductRepository(db),
          inventory: InventoryRepository(db),
          categories: SqliteCategoryRepository(db),
          photoService: LocalProductPhotoService(),
          analytics: BrandAnalyticsRepository(db),
          access: FeatureAccessService(
            db,
            planController: AppPlanController(source),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No brands yet'), findsOneWidget);
    expect(find.text('Selecta'), findsNothing);

    await tester.tap(find.text('Add Brand').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Selecta');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Selecta'), findsOneWidget);
    expect((await tester.runAsync(() => special.managedBrands()))?.length, 1);
    await tester.ensureVisible(find.text('Selecta'));
    await tester.tap(find.text('Selecta'));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    }
    await tester.pump();
    expect(find.text('Products in Selecta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
