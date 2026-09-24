import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/products/presentation/product_details_screen.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';

void main() {
  sqfliteFfiInit();

  testWidgets(
    'Product Details switches Free to Pro without leaking locked values',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('product_plan_test_'),
      );
      if (directory == null) throw StateError('Test directory unavailable');
      addTearDown(() => directory.delete(recursive: true));
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final db = await tester.runAsync(() => app.database);
      if (db == null) throw StateError('Test database unavailable');
      final product = await tester.runAsync(() async {
        final category = await SqliteCategoryRepository(db)
            .create('Seasonings');
        return SqliteProductRepository(db).create(
          ProductDraft(
            categoryId: category.id,
            name: 'Ajinomoto Betsin',
            photoPath: '/test/product.png',
            purchasePriceCentavos: 300,
            sellingPriceCentavos: 500,
            startingQuantity: 10,
            minimumStockLevel: 2,
          ),
        );
      });
      if (product == null) throw StateError('Test product unavailable');
      final controller = AppPlanController(
        DevelopmentPlanSource(
          enabled: true,
          preferenceFile: () async => File('${directory.path}/plan.txt'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: ProductDetailsScreen(
            product: product,
            repository: SqliteProductRepository(db),
            access: FeatureAccessService(db, planController: controller),
            categoryName: 'Seasonings',
            onEdit: () {},
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ajinomoto Betsin'), findsOneWidget);
      expect(find.text('Current Stock Cost'), findsNothing);
      expect(find.text('Upgrade to Pro'), findsOneWidget);
      expect(find.text('View Purchase History'), findsOneWidget);

      await tester.runAsync(() => controller.setDevelopmentPlan(AppPlan.pro));
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Current Stock Cost'), findsOneWidget);
      expect(find.text('Potential Sales Value'), findsOneWidget);
      expect(find.text('₱30.00'), findsOneWidget);
      expect(find.text('Upgrade to Pro'), findsNothing);

      tester.view.physicalSize = const Size(620, 500);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

    await tester.runAsync(() => controller.setDevelopmentPlan(AppPlan.free));
    await tester.pumpAndSettle();
    expect(find.text('Current Stock Cost'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Upgrade to Pro'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Upgrade to Pro'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
