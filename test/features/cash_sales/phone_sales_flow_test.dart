import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/cash_sales/presentation/cash_sale_screen.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/product_unit.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/sale_draft_repository.dart';

void main() {
  sqfliteFfiInit();

  testWidgets(
    'phone rice sale uses existing atomic checkout and shows success',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      late final CashSaleRepository sales;
      late final SqliteProductRepository products;
      late final Product rice;
      await tester.runAsync(() async {
        final db = await app.database;
        sales = CashSaleRepository(db);
        products = SqliteProductRepository(db);
        final category = (await SqliteCategoryRepository(db).create('Rice')).id;
        rice = await products.create(
          ProductDraft(
            categoryId: category,
            name: 'Rice',
            photoPath: '/missing',
            purchasePriceCentavos: 120000,
            sellingPriceCentavos: 5500,
            startingQuantity: 1,
            minimumStockLevel: 1000,
            unitConfiguration: ProductUnitPreset.forCategory('Rice', 5500),
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashSaleScreen(
              embedded: true,
              products: [rice],
              repository: sales,
              loadProducts: products.searchActive,
              drafts: SaleDraftRepository(sales.db),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();

      await tester.tap(find.text('Rice').first);
      await tester.pumpAndSettle();
      expect(find.text('Select selling option'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, '0.5'));
      await tester.pump();
      await tester.tap(find.text('Add to Sale'));
      await tester.pumpAndSettle();
      expect(find.text('1 item'), findsOneWidget);
      await tester.tap(find.text('1 item'));
      await tester.pump();
      expect(find.text('₱27.50'), findsWidgets);
      await tester.ensureVisible(find.text('Complete Sale'));
      await tester.tap(find.text('Complete Sale'));
      await tester.pumpAndSettle();
      expect(find.text('Review Sale'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale').last);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      });
      await tester.pump();
      final db = sales.db;
      final rows = await tester.runAsync(() => db.query('cash_sales'));
      expect(rows, hasLength(1));
      for (
        var i = 0;
        i < 10 && find.text('Sale Completed!').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
      }
      expect(find.text('Sale Completed!'), findsOneWidget);
      final stock = await tester.runAsync(
        () => db.query('products', where: 'id=?', whereArgs: [rice.id]),
      );
      expect(stock!.single['current_quantity'], 24500);
      await tester.tap(find.text('New Sale'));
      await tester.pump();
      expect(find.text('Sale Completed!'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
