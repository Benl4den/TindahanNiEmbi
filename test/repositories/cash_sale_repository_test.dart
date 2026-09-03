import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v1.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late Product p;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    final c = (await SqliteCategoryRepository(db).create('C')).id;
    p = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: c,
        name: 'Kape',
        photoPath: '/k',
        purchasePriceCentavos: 500,
        sellingPriceCentavos: 900,
        startingQuantity: 5,
        minimumStockLevel: 1,
      ),
    );
  });
  tearDown(() => app.close());
  test('V2 installed and cash sale atomically snapshots and deducts', () async {
    expect(AppDatabase.schemaVersion, 11);
    expect(
      (await db.query(
        'schema_migrations',
        orderBy: 'version',
      )).map((x) => x['version']),
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    );
    final id = await CashSaleRepository(db)
        .save([UtangItemDraft(productId: p.id, quantity: 2)]);
    final sale = (await db.query(
          'cash_sales',
          where: 'id=?',
          whereArgs: [id],
        )).single,
        item = (await db.query('cash_sale_items')).single;
    expect(sale['total_centavos'], 1800);
    expect(item['product_name_snapshot'], 'Kape');
    expect(item['unit_price_centavos'], 900);
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [p.id],
      )).single['current_quantity'],
      3,
    );
    expect(
      (await db.rawQuery(
        "SELECT t.type FROM inventory_movements m JOIN inventory_transactions t ON t.id=m.inventory_transaction_id WHERE t.type='CASH_SALE'",
      )).single['type'],
      'CASH_SALE',
    );
    final log = (await db.query(
      'activity_logs',
      where: "event_type='SALES_CASH_SALE'",
    )).single;
    expect(log['event_type'], 'SALES_CASH_SALE');
    expect(log['related_entity_id'], id);
  });
  test('insufficient stock rolls back all sale rows', () async {
    await expectLater(
      CashSaleRepository(db)
          .save([UtangItemDraft(productId: p.id, quantity: 6)]),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('cash_sales'), isEmpty);
    expect(
      await db.query('activity_logs', where: "event_type='SALES_CASH_SALE'"),
      isEmpty,
    );
    expect(
      (await db.query(
        'products',
        where: 'id=?',
        whereArgs: [p.id],
      )).single['current_quantity'],
      5,
    );
  });
  test('later product edit does not change snapshots', () async {
    await CashSaleRepository(db)
        .save([UtangItemDraft(productId: p.id, quantity: 1)]);
    await SqliteProductRepository(db).update(
      Product(
        id: p.id,
        categoryId: p.categoryId,
        name: 'Bag-o',
        photoPath: p.photoPath,
        purchasePriceCentavos: 500,
        sellingPriceCentavos: 1200,
        currentQuantity: 4,
        minimumStockLevel: 1,
        isArchived: false,
        createdAt: p.createdAt,
        updatedAt: p.updatedAt,
      ),
    );
    final item = (await db.query('cash_sale_items')).single;
    expect(item['product_name_snapshot'], 'Kape');
    expect(item['unit_price_centavos'], 900);
  });

  test(
    'Sales history combines cash and UTANG without duplicating data',
    () async {
      final cash = CashSaleRepository(db);
      await cash.save([UtangItemDraft(productId: p.id, quantity: 1)]);
      final customer = await SqliteCustomerRepository(db)
          .create(const CustomerDraft(fullName: 'Maria'));
      await UtangRepository(db).save(
        UtangDraft(
          customerId: customer.id,
          items: [UtangItemDraft(productId: p.id, quantity: 2)],
        ),
      );
      final all = await cash.history();
      expect(all, hasLength(2));
      expect(all.map((x) => x.type).toSet(), {'CASH', 'UTANG'});
      expect((await cash.history(type: 'UTANG')).single.customerName, 'Maria');
      expect(
        (await cash.utangItems(all.firstWhere((x) => x.isUtang).id))
            .single['product_name_snapshot'],
        'Kape',
      );
    },
  );

  test('existing V1 database upgrades safely to V2', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tindahan_upgrade_',
    );
    final databasePath = '${directory.path}/upgrade.db';
    final v1 = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) => MigrationV1().migrate(db),
      ),
    );
    await v1.close();
    final upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final upgradedDb = await upgraded.database;
    expect(
      (await upgradedDb.query(
        'schema_migrations',
        orderBy: 'version',
      )).map((row) => row['version']),
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
    );
    expect(
      await upgradedDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='cash_sales'",
      ),
      isNotEmpty,
    );
    await upgraded.close();
    await directory.delete(recursive: true);
  });
}
