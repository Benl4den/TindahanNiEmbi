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

void main() {
  sqfliteFfiInit();
  test('V7 upgrades to resumable V8 correction relationships', () async {
    final dir = await Directory.systemTemp.createTemp('v7_v8_'),
        file = '${dir.path}/db.sqlite';
    final old = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, _) async {
          for (final migration in [
            MigrationV1(),
            MigrationV2(),
            MigrationV3(),
            MigrationV4(),
            MigrationV5(),
            MigrationV6(),
            MigrationV7(),
          ]) {
            await migration.migrate(db);
          }
        },
      ),
    );
    await old.close();
    final app = AppDatabase(factory: databaseFactoryFfi, databasePath: file),
        db = await app.database;
    expect(await db.getVersion(), 17);
    expect(
      await db.query('schema_migrations', where: 'version=8'),
      hasLength(1),
    );
    expect(
      await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='transaction_corrections'",
      ),
      isNotEmpty,
    );
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await app.close();
    await dir.delete(recursive: true);
  });
}
