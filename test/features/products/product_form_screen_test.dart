import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/products/presentation/product_form_screen.dart';
import 'package:tindahan_ni_embi/models/category.dart';
import 'package:tindahan_ni_embi/models/product.dart';
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
    expect(find.text('Save'), findsOneWidget);
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
