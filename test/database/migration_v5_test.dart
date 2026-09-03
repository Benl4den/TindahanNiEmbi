import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v1.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v2.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v3.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v4.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';

void main() {
  sqfliteFfiInit();
  test('existing V4 upgrades to V5', () async {
    final dir = await Directory.systemTemp.createTemp('v4_v5_'),
        file = '${dir.path}/db.sqlite';
    final old = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await MigrationV1().migrate(db);
          await MigrationV2().migrate(db);
          await MigrationV3().migrate(db);
          await MigrationV4().migrate(db);
        },
      ),
    );
    await old.close();
    final app = AppDatabase(factory: databaseFactoryFfi, databasePath: file),
        db = await app.database;
    expect(
      (await db.query(
        'schema_migrations',
        orderBy: 'version',
      )).map((x) => x['version']),
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    );
    expect((await db.query('app_settings')).single['value'], '0');
    await app.close();
    await dir.delete(recursive: true);
  });

  test('sale references are unique and survive reopen', () async {
    final dir = await Directory.systemTemp.createTemp('sale_ref_'),
        file = '${dir.path}/db.sqlite';
    var app = AppDatabase(factory: databaseFactoryFfi, databasePath: file),
        db = await app.database;
    final category = await SqliteCategoryRepository(db).create('Food');
    final product = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category.id,
        name: 'Bread',
        photoPath: '/bread',
        purchasePriceCentavos: 500,
        sellingPriceCentavos: 1000,
        startingQuantity: 5,
        minimumStockLevel: 1,
      ),
    );
    final first = await CashSaleRepository(db)
        .saveWithResult([UtangItemDraft(productId: product.id, quantity: 1)]);
    final second = await CashSaleRepository(db)
        .saveWithResult([UtangItemDraft(productId: product.id, quantity: 1)]);
    expect(first.reference, 'SALE-000001');
    expect(second.reference, 'SALE-000002');
    await expectLater(
      db.update(
        'cash_sales',
        {'reference': 'SALE-999999'},
        where: 'id=?',
        whereArgs: [first.id],
      ),
      throwsA(anything),
    );
    await app.close();
    app = AppDatabase(factory: databaseFactoryFfi, databasePath: file);
    db = await app.database;
    expect((await CashSaleRepository(db).latest())!.reference, 'SALE-000002');
    final details = await CashSaleRepository(db).details(first.id);
    expect(details.items.single['product_name_snapshot'], 'Bread');
    await app.close();
    await dir.delete(recursive: true);
  });
}
