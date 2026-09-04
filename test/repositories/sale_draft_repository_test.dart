import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/transactions/product_selection_controller.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/product_unit.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/sale_draft_repository.dart';

void main() {
  sqfliteFfiInit();

  test('active cart survives reload and never changes stock', () async {
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await app.database;
    final category = await SqliteCategoryRepository(db).create('Test');
    final product = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category.id,
        name: 'Coffee',
        photoPath: '/coffee.jpg',
        purchasePriceCentavos: 500,
        sellingPriceCentavos: 700,
        startingQuantity: 10,
        minimumStockLevel: 1,
      ),
    );
    final option = SellingOption(
      id: -product.id,
      productId: product.id,
      name: 'Piece',
      baseQuantity: 1,
      priceCentavos: 700,
      isDefault: true,
    );
    final cart = ProductSelectionController([product])..add(product, option);
    final drafts = SaleDraftRepository(db);

    await drafts.save(cart.lines);
    final restored = await drafts.load([product]);

    expect(restored, hasLength(1));
    expect(restored.single.lineTotalCentavos, 700);
    expect((await db.query('products')).single['current_quantity'], 10);
    await drafts.clear();
    expect(await drafts.load([product]), isEmpty);
  });
}
