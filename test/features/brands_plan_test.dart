import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/special_inventory/presentation/managed_brands_screen.dart';
import 'package:tindahan_ni_embi/repositories/brand_analytics_repository.dart';
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
}
