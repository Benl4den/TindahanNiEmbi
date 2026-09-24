import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/inventory/presentation/inventory_screen.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';

class _TestPlanSource extends AppPlanSource {
  AppPlan current = AppPlan.free;
  @override
  AppPlan get plan => current;
  @override
  Future<AppPlan> load() async => current;
  void change(AppPlan value) {
    current = value;
    notifyListeners();
  }
}

void main() {
  sqfliteFfiInit();
  testWidgets('Inventory switches Free and Pro without changing stock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
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
    final category = await tester.runAsync(
      () => SqliteCategoryRepository(db!).create('Seasonings'),
    );
    final product = await tester.runAsync(
      () => SqliteProductRepository(db!).create(
        ProductDraft(
          categoryId: category!.id,
          name: 'Ajinomoto Betsin',
          photoPath: '/missing.png',
          purchasePriceCentavos: 300,
          sellingPriceCentavos: 500,
          startingQuantity: 10,
          minimumStockLevel: 2,
        ),
      ),
    );
    final source = _TestPlanSource();
    final access = FeatureAccessService(
      db!,
      planController: AppPlanController(source),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: InventoryScreen(
          repository: InventoryRepository(db),
          access: access,
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inventory Value & Profit Insights'), findsOneWidget);
    expect(find.text('Current Inventory Cost'), findsNothing);
    expect(find.text('Cost: ₱3.00 / piece'), findsOneWidget);
    expect(find.text('Sell: ₱5.00 / piece'), findsOneWidget);
    expect(find.text('Search inventory'), findsOneWidget);

    source.change(AppPlan.pro);
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inventory Health'), findsOneWidget);
    expect(find.text('Current Inventory Cost'), findsOneWidget);
    expect(find.text('₱30.00'), findsWidgets);
    expect(find.text('₱50.00'), findsWidgets);
    expect(find.text('₱20.00'), findsWidgets);
    expect(tester.takeException(), isNull);

    source.change(AppPlan.free);
    await tester.pumpAndSettle();
    expect(find.text('Current Inventory Cost'), findsNothing);
    expect(find.text('Inventory Value & Profit Insights'), findsOneWidget);
    expect(
      (await tester.runAsync(() => InventoryRepository(db).current()))!
          .single
          .currentQuantity,
      product!.currentQuantity,
    );
    expect(tester.takeException(), isNull);
  });
}
