import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/cash_sales/presentation/cash_sale_screen.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';

void main() {
  testWidgets(
    'Sales workspace is usable in landscape and portrait tablet sizes',
    (tester) async {
      final now = DateTime.utc(2026);
      final products = [
        Product(
          id: 1,
          categoryId: 1,
          name: 'Coffee',
          photoPath: '/missing',
          purchasePriceCentavos: 500,
          sellingPriceCentavos: 1000,
          currentQuantity: 4,
          minimumStockLevel: 1,
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        ),
        Product(
          id: 2,
          categoryId: 1,
          name: 'Milk',
          photoPath: '/missing',
          purchasePriceCentavos: 300,
          sellingPriceCentavos: 700,
          currentQuantity: 0,
          minimumStockLevel: 1,
          isArchived: false,
          createdAt: now,
          updatedAt: now,
        ),
      ];
      for (final size in [const Size(1280, 800), const Size(800, 1280)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: CashSaleScreen(products: products, saveSale: (_) async => 1),
          ),
        );
        await tester.pump();
        expect(find.text('Sales'), findsOneWidget);
        expect(find.text('Coffee'), findsOneWidget);
        expect(find.text('Out of Stock'), findsWidgets);
        if (size.width >= 900) {
          expect(find.text('No sales recorded yet.'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
    },
  );

  testWidgets(
    'Sales UTANG checkout receives exact cart and only clears on success',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final now = DateTime.utc(2026);
      final product = Product(
        id: 7,
        categoryId: 1,
        name: 'Coffee',
        photoPath: '/missing',
        purchasePriceCentavos: 500,
        sellingPriceCentavos: 1000,
        currentQuantity: 4,
        minimumStockLevel: 1,
        isArchived: false,
        createdAt: now,
        updatedAt: now,
      );
      var succeeds = false;
      List<UtangItemDraft>? received;
      await tester.pumpWidget(
        MaterialApp(
          home: CashSaleScreen(
            products: [product],
            saveSale: (_) async => 1,
            onUtang: (items) async {
              received = items;
              return succeeds;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.tap(find.text('UTANG'));
      await tester.pump();
      expect(received!.single.productId, 7);
      expect(received!.single.quantity, 1);
      expect(find.text('1 × ₱10.00'), findsOneWidget);
      succeeds = true;
      await tester.tap(find.text('UTANG'));
      await tester.pump();
      expect(
        find.text('Your cart is empty.\nSelect products to begin a sale.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Clear Sale confirmation protects the current cart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final now = DateTime.utc(2026);
    final product = Product(
      id: 1,
      categoryId: 1,
      name: 'Juice',
      photoPath: '/missing',
      purchasePriceCentavos: 100,
      sellingPriceCentavos: 500,
      currentQuantity: 3,
      minimumStockLevel: 1,
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CashSaleScreen(products: [product], saveSale: (_) async => 1),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Clear Sale'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.tap(find.text('Clear Sale'));
    await tester.pump();
    expect(find.text('Clear current sale?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('1 × ₱5.00'), findsOneWidget);
    await tester.tap(find.text('Clear Sale'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear Sale'));
    await tester.pump();
    expect(
      find.text('Your cart is empty.\nSelect products to begin a sale.'),
      findsOneWidget,
    );
  });
}
