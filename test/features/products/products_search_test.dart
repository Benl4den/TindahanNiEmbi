import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/products/presentation/products_screen.dart';
import 'package:tindahan_ni_embi/models/category.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/services/product_photo_service.dart';

void main() {
  testWidgets('Products search filters visible cards immediately', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProductsScreen(
          repository: _Products(),
          categoryRepository: _Categories(),
          photoService: _Photos(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alcohol'), findsOneWidget);
    expect(find.text('Corneto'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'corn');
    await tester.pump();
    expect(find.text('Corneto'), findsOneWidget);
    expect(find.text('Alcohol'), findsNothing);
  });
}

Product _product(int id, String name) => Product(
  id: id,
  categoryId: 1,
  name: name,
  photoPath: '/missing.jpg',
  purchasePriceCentavos: 1000,
  sellingPriceCentavos: 1500,
  currentQuantity: 10,
  minimumStockLevel: 1,
  isArchived: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _Products implements ProductRepository {
  @override
  Future<List<Product>> searchActive([String query = '']) async => [
    _product(1, 'Alcohol'),
    _product(2, 'Corneto'),
  ];
  @override
  Future<void> archive(int id) async {}
  @override
  Future<Product> create(ProductDraft draft) => throw UnimplementedError();
  @override
  Future<Product> update(Product product) => throw UnimplementedError();
}

class _Categories implements CategoryRepository {
  final category = Category(
    id: 1,
    name: 'Other',
    isArchived: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  @override
  Future<List<Category>> getActive() async => [category];
  @override
  Future<void> archive(int id) async {}
  @override
  Future<Category> create(String name) async => category;
  @override
  Future<Category> update({required int id, required String name}) async =>
      category;
}

class _Photos implements ProductPhotoService {
  @override
  Future<String?> capture() async => null;
  @override
  Future<void> delete(String photoPath) async {}
}
