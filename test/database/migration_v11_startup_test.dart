import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v1.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v2.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v3.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v4.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v5.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v6.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v7.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v8.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v9.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v10.dart';

void main() {
  sqfliteFfiInit();

  test('V10 allocation history upgrades without mutation', () async {
    final dir = await Directory.systemTemp.createTemp('v11_allocation_');
    final file = '${dir.path}/db.sqlite';
    final old = await _v10(file);
    final now = DateTime.now().toUtc().toIso8601String();
    final category = await old.insert('categories', {
      'name': 'Test',
      'created_at': now,
      'updated_at': now,
    });
    final product = await old.insert('products', {
      'category_id': category,
      'name': 'Bottle',
      'photo_path': '/x',
      'current_quantity': 0,
      'created_at': now,
      'updated_at': now,
    });
    final inventory = await old.insert('inventory_transactions', {
      'type': 'STOCK_IN',
      'occurred_at': now,
      'created_at': now,
    });
    final movement = await old.insert('inventory_movements', {
      'inventory_transaction_id': inventory,
      'product_id': product,
      'quantity_change': 2,
      'quantity_before': 0,
      'quantity_after': 2,
      'created_at': now,
    });
    final sale = await old.insert('cash_sales', {
      'reference': 'SALE-1',
      'total_centavos': 2000,
      'status': 'POSTED',
      'occurred_at': now,
      'created_at': now,
    });
    final item = await old.insert('cash_sale_items', {
      'cash_sale_id': sale,
      'product_id': product,
      'product_name_snapshot': 'Bottle',
      'unit_price_centavos': 1000,
      'quantity': 2,
      'line_total_centavos': 2000,
      'created_at': now,
    });
    final consignor = await old.insert('consignors', {
      'name': 'Supplier',
      'created_at': now,
      'updated_at': now,
    });
    final batch = await old.insert('consignment_batches', {
      'consignor_id': consignor,
      'product_id': product,
      'inventory_movement_id': movement,
      'boxes_received': 1,
      'units_per_box': 2,
      'units_received': 2,
      'units_allocated': 2,
      'units_returned': 0,
      'unit_cost_centavos': 700,
      'selling_price_centavos': 1000,
      'received_at': now,
      'created_at': now,
    });
    final allocation = await old.insert('consignment_allocations', {
      'batch_id': batch,
      'cash_sale_item_id': item,
      'quantity': 2,
      'unit_cost_centavos': 700,
      'selling_price_centavos': 1000,
      'payable_centavos': 1400,
      'margin_centavos': 600,
      'occurred_at': now,
    });
    await old.close();

    final app = AppDatabase(factory: databaseFactoryFfi, databasePath: file);
    final db = await app.database;
    expect(await db.getVersion(), 17);
    final legacy = (await db.query(
      'consignment_allocations',
      where: 'id=?',
      whereArgs: [allocation],
    )).single;
    expect(legacy['sale_revenue_centavos'], 2000);
    expect(legacy['actual_margin_centavos'], 600);
    expect(legacy['actual_payable_centavos'], 1400);
    await expectLater(
      db.update(
        'consignment_allocations',
        {'quantity': 1},
        where: 'id=?',
        whereArgs: [allocation],
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await app.close();
    await dir.delete(recursive: true);
  });

  test('V11 resumes safely when one column already exists', () async {
    final dir = await Directory.systemTemp.createTemp('v11_partial_');
    final file = '${dir.path}/db.sqlite';
    final old = await _v10(file);
    await old.execute(
      'ALTER TABLE cash_sale_items ADD COLUMN selling_quantity_value INTEGER CHECK(selling_quantity_value>0)',
    );
    await old.close();
    final app = AppDatabase(factory: databaseFactoryFfi, databasePath: file);
    final db = await app.database;
    expect(await db.getVersion(), 17);
    final columns = await db.rawQuery('PRAGMA table_info(cash_sale_items)');
    expect(
      columns.map((x) => x['name']),
      containsAll([
        'selling_quantity_value',
        'selling_quantity_scale',
        'total_base_quantity',
      ]),
    );
    await app.close();
    await dir.delete(recursive: true);
  });
}

Future<Database> _v10(String file) => databaseFactoryFfi.openDatabase(
  file,
  options: OpenDatabaseOptions(
    version: 10,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
    onCreate: (db, _) async {
      for (final migration in [
        MigrationV1(),
        MigrationV2(),
        MigrationV3(),
        MigrationV4(),
        MigrationV5(),
        MigrationV6(),
        MigrationV7(),
        MigrationV8(),
        MigrationV9(),
        MigrationV10(),
      ]) {
        await migration.migrate(db);
      }
    },
  ),
);
