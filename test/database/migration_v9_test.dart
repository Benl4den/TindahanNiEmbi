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

void main() {
  sqfliteFfiInit();
  test('V8 upgrades safely to resumable V9 and preserves data', () async {
    final dir = await Directory.systemTemp.createTemp('v8_v9_');
    final file = '${dir.path}/db.sqlite';
    final old = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 8,
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
          ]) {
            await migration.migrate(db);
          }
        },
      ),
    );
    final stamp = DateTime.now().toUtc().toIso8601String();
    await old.insert('categories', {
      'name': 'Preserved',
      'created_at': stamp,
      'updated_at': stamp,
    });
    await old.close();
    final app = AppDatabase(factory: databaseFactoryFfi, databasePath: file);
    final db = await app.database;
    expect(await db.getVersion(), 9);
    expect(
      await db.query('categories', where: "name='Preserved'"),
      hasLength(1),
    );
    expect(await db.query('expense_categories'), hasLength(12));
    expect(
      await db.query('schema_migrations', where: 'version=9'),
      hasLength(1),
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await app.close();
    await dir.delete(recursive: true);
  });
}
