import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v1.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v2.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v3.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v4.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v5.dart';

void main() {
  sqfliteFfiInit();
  test(
    'existing V5 upgrades to V6 without modifying historical migrations',
    () async {
      final dir = await Directory.systemTemp.createTemp('v5_v6_');
      final file = '${dir.path}/db.sqlite';
      final old = await databaseFactoryFfi.openDatabase(
        file,
        options: OpenDatabaseOptions(
          version: 5,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: (db, _) async {
            await MigrationV1().migrate(db);
            await MigrationV2().migrate(db);
            await MigrationV3().migrate(db);
            await MigrationV4().migrate(db);
            await MigrationV5().migrate(db);
          },
        ),
      );
      await old.close();
      final app = AppDatabase(factory: databaseFactoryFfi, databasePath: file);
      final db = await app.database;
      expect(
        (await db.query(
          'schema_migrations',
          orderBy: 'version',
        )).map((x) => x['version']),
        [1, 2, 3, 4, 5, 6, 7, 8, 9],
      );
      expect(
        (await db.query('inventory_groups')).map((x) => x['code']),
        containsAll(['SELECTA', 'CONSIGNMENT']),
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await app.close();
      await dir.delete(recursive: true);
    },
  );

  test('partially-created V6 schema resumes safely during startup', () async {
    final dir = await Directory.systemTemp.createTemp('partial_v6_');
    final file = '${dir.path}/db.sqlite';
    final old = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await MigrationV1().migrate(db);
          await MigrationV2().migrate(db);
          await MigrationV3().migrate(db);
          await MigrationV4().migrate(db);
          await MigrationV5().migrate(db);
          await db.execute('''CREATE TABLE inventory_groups(
            id INTEGER PRIMARY KEY,
            code TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(code))>0),
            name TEXT NOT NULL CHECK(length(trim(name))>0),
            is_archived INTEGER NOT NULL DEFAULT 0 CHECK(is_archived IN(0,1)),
            created_at TEXT NOT NULL)''');
        },
      ),
    );
    await old.close();
    final app = AppDatabase(factory: databaseFactoryFfi, databasePath: file);
    final db = await app.database;
    expect(await db.getVersion(), 9);
    expect(
      (await db.query('inventory_groups')).map((x) => x['code']),
      containsAll(['SELECTA', 'CONSIGNMENT']),
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await app.close();
    await dir.delete(recursive: true);
  });
}
