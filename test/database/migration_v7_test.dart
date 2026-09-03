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

void main() {
  sqfliteFfiInit();
  test('existing V6 upgrades to V7 with reversal history', () async {
    final dir = await Directory.systemTemp.createTemp('v6_v7'),
        file = '${dir.path}/db';
    final old = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          for (final m in [
            MigrationV1(),
            MigrationV2(),
            MigrationV3(),
            MigrationV4(),
            MigrationV5(),
            MigrationV6(),
          ]) {
            await m.migrate(db);
          }
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
    expect(await db.query('transaction_reversals'), isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await app.close();
    await dir.delete(recursive: true);
  });
}
