import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v12.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';

void main() {
  sqfliteFfiInit();
  test('V12 repairs only zero current default selling prices', () async {
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await app.database;
    final category = await SqliteCategoryRepository(db).create('General');
    final product = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category.id,
        name: 'Item',
        photoPath: '/item.jpg',
        purchasePriceCentavos: 500,
        sellingPriceCentavos: 750,
        startingQuantity: 0,
        minimumStockLevel: 0,
      ),
    );
    await db.update(
      'product_selling_options',
      {'price_centavos': 0},
      where: 'product_id=? AND is_default=1',
      whereArgs: [product.id],
    );

    await MigrationV12().migrate(db);

    final option = (await db.query(
      'product_selling_options',
      where: 'product_id=? AND is_default=1',
      whereArgs: [product.id],
    )).single;
    expect(option['price_centavos'], 750);
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [product.id],
      )).single['selling_price_centavos'],
      750,
    );
    await app.close();
  });
}
