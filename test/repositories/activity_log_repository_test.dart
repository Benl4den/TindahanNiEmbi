import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v1.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v2.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v3.dart';
import 'package:tindahan_ni_embi/repositories/activity_log_repository.dart';

void main() {
  sqfliteFfiInit();
  test(
    'fresh V4 stores timestamp, filters by date and is append-only',
    () async {
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final db = await app.database;
      expect(
        (await db.query(
          'schema_migrations',
          orderBy: 'version',
        )).map((x) => x['version']),
        [1, 2, 3, 4, 5, 6, 7, 8],
      );
      final at = DateTime.utc(2026, 9, 2, 8, 42);
      final id = await ActivityLogRepository(db).add(
        eventType: 'SALES_CASH_SALE',
        description: 'Cash sale completed',
        actorRole: 'STAFF',
        at: at,
      );
      final logs = await ActivityLogRepository(db).forDate(at.toLocal());
      expect(logs.single.createdAt, at);
      expect(logs.single.actorRole, 'STAFF');
      expect(
        await ActivityLogRepository(db)
            .forDate(at.toLocal(), query: 'cash sale'),
        hasLength(1),
      );
      expect(
        await ActivityLogRepository(db).forDate(at.toLocal(), query: 'Juan'),
        isEmpty,
      );
      expect(
        await ActivityLogRepository(db)
            .forDate(at.toLocal(), category: 'SALES'),
        hasLength(1),
      );
      await expectLater(
        db.update(
          'activity_logs',
          {'description': 'changed'},
          where: 'id=?',
          whereArgs: [id],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.delete('activity_logs', where: 'id=?', whereArgs: [id]),
        throwsA(anything),
      );
      await app.close();
    },
  );

  test('existing V3 upgrades to V4 without losing data', () async {
    final dir = await Directory.systemTemp.createTemp('v3_v4_');
    final file = '${dir.path}/db.sqlite';
    final old = await databaseFactoryFfi.openDatabase(
      file,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await MigrationV1().migrate(db);
          await MigrationV2().migrate(db);
          await MigrationV3().migrate(db);
        },
      ),
    );
    await old.insert('categories', {
      'name': 'Existing',
      'is_archived': 0,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    await old.close();
    final app = AppDatabase(factory: databaseFactoryFfi, databasePath: file);
    final db = await app.database;
    expect(await db.query('categories'), hasLength(1));
    expect(await db.query('activity_logs'), isEmpty);
    await app.close();
    await dir.delete(recursive: true);
  });
}
