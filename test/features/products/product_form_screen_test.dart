import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/products/presentation/product_form_screen.dart';
import 'package:tindahan_ni_embi/features/products/presentation/smart_packaging_editor.dart';
import 'package:tindahan_ni_embi/models/category.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/product_unit.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/services/product_photo_service.dart';

void main() {
  testWidgets('new product requires camera step before details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProductFormScreen(
          repository: _FakeProducts(),
          photoService: _FakePhotos(),
          categories: [
            Category(
              id: 1,
              name: 'Inom',
              isArchived: false,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        ),
      ),
    );
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Product Name'), findsNothing);
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Product Name'), findsOneWidget);
    expect(find.text('Units & Packaging'), findsOneWidget);
    expect(find.text('How do you buy this product?'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('cigarette pack price follows stick price and pack size', (
    tester,
  ) async {
    ProductUnitConfiguration? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartPackagingEditor(
              categoryName: 'Cigarettes & Tobacco',
              purchasePriceCentavos: 12000,
              sellingPriceCentavos: 800,
              onChanged: (value) => latest = value,
              onPricesChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Units & Packaging'), findsOneWidget);
    expect(find.text('Sticks per Pack'), findsNothing);
    await tester.tap(find.text('Units & Packaging'));
    await tester.pumpAndSettle();
    expect(find.text('Sticks per Pack'), findsOneWidget);
    TextField field(String label) => tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      ),
    );

    expect(field('Selling Price per Pack').readOnly, isTrue);
    expect(field('Selling Price per Pack').controller!.text, '160.00');
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Selling Price per Stick',
      ),
      '10',
    );
    await tester.pump();
    expect(field('Selling Price per Pack').controller!.text, '200.00');
    expect(latest!.sellingOptions.last.priceCentavos, 20000);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Sticks per Pack',
      ),
      '25',
    );
    await tester.pump();
    expect(field('Selling Price per Pack').controller!.text, '250.00');
    expect(latest!.purchasePackages.first.baseQuantity, 25);
  });

  testWidgets('editing cigarettes keeps the Units & Packaging control', (
    tester,
  ) async {
    final existing = ProductUnitConfiguration(
      baseUnit: BaseUnit.stick,
      purchasePackages: const [
        PurchasePackageDraft(name: 'Pack', baseQuantity: 25, isDefault: true),
      ],
      sellingOptions: const [
        SellingOptionDraft(
          name: 'Stick',
          baseQuantity: 1,
          priceCentavos: 1000,
          isDefault: true,
        ),
        SellingOptionDraft(
          name: 'Pack',
          baseQuantity: 25,
          priceCentavos: 25000,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartPackagingEditor(
              categoryName: 'Cigarettes & Tobacco',
              purchasePriceCentavos: 12000,
              sellingPriceCentavos: 1000,
              initial: existing,
              onChanged: (_) {},
              onPricesChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Units & Packaging'));
    await tester.pumpAndSettle();
    final size = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Sticks per Pack',
      ),
    );
    expect(size.controller!.text, '25');
  });

  testWidgets(
    'legacy piece-stock cigarette category can edit pack size safely',
    (tester) async {
      ProductUnitConfiguration? updated;
      final legacy = ProductUnitConfiguration(
        baseUnit: BaseUnit.piece,
        purchasePackages: const [
          PurchasePackageDraft(name: 'Piece', baseQuantity: 1, isDefault: true),
        ],
        sellingOptions: const [
          SellingOptionDraft(
            name: 'Piece',
            baseQuantity: 1,
            priceCentavos: 1200,
            isDefault: true,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SmartPackagingEditor(
                categoryName: 'Cigarette / Tobacco',
                purchasePriceCentavos: 1000,
                sellingPriceCentavos: 1200,
                initial: legacy,
                onChanged: (value) => updated = value,
                onPricesChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Units & Packaging'), findsOneWidget);
      await tester.tap(find.text('Units & Packaging'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Sticks per Pack',
        ),
        '20',
      );
      await tester.pump();
      expect(updated!.baseUnit, BaseUnit.piece);
      expect(updated!.purchasePackages.single.baseQuantity, 20);
      expect(updated!.sellingOptions.last.priceCentavos, 24000);
    },
  );

  testWidgets('cigarette packaging supports extra purchase and sale options', (
    tester,
  ) async {
    ProductUnitConfiguration? latest;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SmartPackagingEditor(
              categoryName: 'Cigarettes & Tobacco',
              purchasePriceCentavos: 10000,
              sellingPriceCentavos: 1000,
              onChanged: (value) => latest = value,
              onPricesChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Units & Packaging'));
    await tester.pumpAndSettle();
    expect(find.text('How do you buy this product?'), findsOneWidget);
    expect(find.text('How do you sell this product?'), findsOneWidget);
    await tester.ensureVisible(find.text('Add purchase package'));
    await tester.tap(find.text('Add purchase package'));
    await tester.pumpAndSettle();
    expect(latest!.purchasePackages.length, 2);
    await tester.ensureVisible(find.text('Add selling option'));
    await tester.tap(find.text('Add selling option'));
    await tester.pumpAndSettle();
    expect(latest!.sellingOptions.length, 3);
    expect(latest!.sellingOptions.last.priceCentavos, 1000);
  });

  testWidgets('new soft drink uses ordinary price fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProductFormScreen(
          repository: _FakeProducts(),
          photoService: _FakePhotos(),
          categories: [
            Category(
              id: 1,
              name: 'Soft Drinks',
              isArchived: false,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
          initialCategoryId: 1,
        ),
      ),
    );
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Piece Purchase Price'), findsOneWidget);
    expect(find.text('Selling Price'), findsOneWidget);
    expect(find.text('Units & Packaging'), findsOneWidget);
  });
}

class _FakePhotos implements ProductPhotoService {
  @override
  Future<String?> capture() async => '/does/not/need/to/exist.jpg';
  @override
  Future<void> delete(String photoPath) async {}
}

class _FakeProducts implements ProductRepository {
  @override
  Future<void> archive(int id) async {}
  @override
  Future<Product> create(ProductDraft draft) => throw UnimplementedError();
  @override
  Future<List<Product>> searchActive([String query = '']) async => [];
  @override
  Future<Product> update(Product product) => throw UnimplementedError();
}
