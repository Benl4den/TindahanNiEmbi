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

void main() {
  sqfliteFfiInit();
  test('V9 upgrades to V10 with safe 1:1 defaults', () async {
    final dir = await Directory.systemTemp.createTemp('v9_v10_');
    final file = '${dir.path}/db.sqlite';
    final old = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 9,
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
          ]) {
            await migration.migrate(db);
          }
        },
      ),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final category = await old.insert('categories', {
      'name': 'Drinks',
      'created_at': now,
      'updated_at': now,
    });
    final product = await old.insert('products', {
      'category_id': category,
      'name': 'Cola',
      'photo_path': '/cola.jpg',
      'selling_price_centavos': 1500,
      'current_quantity': 0,
      'created_at': now,
      'updated_at': now,
    });
    await old.close();

    final app = AppDatabase(factory: databaseFactoryFfi, databasePath: file);
    final db = await app.database;
    expect(await db.getVersion(), 16);
    final row = (await db.query(
      'products',
      where: 'id=?',
      whereArgs: [product],
    )).single;
    expect(row['base_unit_code'], 'PIECE');
    expect(
      (await db.query('product_selling_options')).single,
      containsPair('base_quantity', 1),
    );
    expect(
      (await db.query('product_purchase_packages')).single,
      containsPair('base_quantity', 1),
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await app.close();
    await dir.delete(recursive: true);
  });
}
