import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/formatters/number_format.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/services/settings_service.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('phone dashboard header stays below Android status bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(database: db, navigate: (_) {}),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Good day!')).dy,
      greaterThanOrEqualTo(32),
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(280, 640);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Receive Consignment'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('phone-quick-consignment')))
          .width,
      greaterThan(80),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phone grid uses live totals and navigates at compact widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    await tester.runAsync(() async {
      await SettingsService(
        db,
      ).setStoreName('A very long but valid neighborhood sari-sari store name');
      final category = await SqliteCategoryRepository(db).create('Drinks');
      final first = await SqliteProductRepository(db).create(
        ProductDraft(
          categoryId: category.id,
          name: 'Drink',
          photoPath: '/drink',
          purchasePriceCentavos: 500,
          sellingPriceCentavos: 1000,
          startingQuantity: 2,
          minimumStockLevel: 2,
        ),
      );
      await SqliteProductRepository(db).create(
        ProductDraft(
          categoryId: category.id,
          name: 'Empty',
          photoPath: '/empty',
          purchasePriceCentavos: 100,
          sellingPriceCentavos: 200,
          startingQuantity: 0,
          minimumStockLevel: 1,
        ),
      );
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: first.id, quantity: 1)]);
    });
    final daily = await tester.runAsync(
      () => OperationsRepository(db).daily(DateTime.now()),
    );
    final stock = await tester.runAsync(
      () => InventoryRepository(db).ownedHealth(),
    );
    var destination = -1;
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final width in [280.0, 320.0, 360.0, 390.0]) {
        tester.view.physicalSize = Size(width, 760);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: DashboardScreen(
              key: ValueKey('dashboard-$width-${theme.brightness}'),
              database: db,
              navigate: (target) => destination = target,
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('A very long but valid neighborhood sari-sari store name'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('phone-metric-sales')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('phone-metric-sales')),
            matching: find.text(
              standardMoney(daily!.totalSales + daily.newUtang),
            ),
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('phone-stock-active')),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('phone-stock-active')),
            matching: find.text('${stock!.activeProducts}'),
          ),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('phone-quick-sale')),
          -140,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('phone-quick-sale')));
        expect(destination, 0);
        expect(
          tester.takeException(),
          isNull,
          reason: '$width ${theme.brightness}',
        );
      }
    }
    tester.view.physicalSize = const Size(1024, 768);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DashboardScreen(database: db, navigate: (_) {}),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-metric-sales')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
