import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v1.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v2.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
  });
  tearDown(() => app.close());
  test('salted PIN verifies and is never stored plain text', () async {
    final auth = AuthService(db);
    await auth.setPin(UserRole.owner, '1234');
    expect(await auth.verify('1234'), UserRole.owner);
    expect(await auth.verify('9999'), isNull);
    final row = (await db.query('security_profiles')).single;
    expect(row['pin_hash'], isNot('1234'));
    expect(row['salt'], isNotEmpty);
  });
  test('PIN setup requires exactly four digits', () async {
    final auth = AuthService(db);
    await expectLater(auth.setPin(UserRole.owner, '123'), throwsArgumentError);
    await expectLater(
      auth.setPin(UserRole.owner, '12345'),
      throwsArgumentError,
    );
    await auth.setPin(UserRole.owner, '4321');
    expect(await auth.verify('4321'), UserRole.owner);
  });

  test('named staff PIN is hashed, selectable, and can be disabled', () async {
    final auth = AuthService(db);
    final id = await auth.addStaff('Maria', '2468');
    final accounts = await auth.staffAccounts(activeOnly: true);
    expect(accounts.single.name, 'Maria');
    expect(await auth.verify('2468', staffId: id), UserRole.staff);
    final stored = (await db.query('staff_accounts')).single;
    expect(stored['pin_hash'], isNot('2468'));
    await auth.setStaffActive(id, false);
    expect(await auth.verify('2468', staffId: id), isNull);
  });

  test(
    'PIN lockout survives new services and reopening the database',
    () async {
      final directory = await Directory.systemTemp.createTemp('pin_retry_');
      final databasePath = '${directory.path}/store.db';
      var store = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      try {
        final storeDb = await store.database;
        await AuthService(storeDb).setPin(UserRole.owner, '1234');
        for (var attempt = 0; attempt < 5; attempt++) {
          expect(await AuthService(storeDb).verify('9999'), isNull);
          expect(await AuthService(storeDb).remainingAttempts, 4 - attempt);
        }
        await expectLater(
          AuthService(storeDb).verify('1234'),
          throwsStateError,
        );

        await store.close();
        store = AppDatabase(
          factory: databaseFactoryFfi,
          databasePath: databasePath,
        );
        await expectLater(
          AuthService(await store.database).verify('1234'),
          throwsStateError,
        );
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('simultaneous PIN checks share one retry limit', () async {
    await AuthService(db).setPin(UserRole.owner, '1234');
    final attempts = await Future.wait(
      List.generate(5, (_) => AuthService(db).verify('9999')),
    );
    expect(attempts, everyElement(isNull));
    await expectLater(AuthService(db).verify('1234'), throwsStateError);
  });

  test('expired lockout and successful PIN reset retry count', () async {
    await AuthService(db).setPin(UserRole.owner, '1234');
    for (var attempt = 0; attempt < 5; attempt++) {
      expect(await AuthService(db).verify('9999'), isNull);
    }
    await db.update(
      'app_settings',
      {
        'value': jsonEncode({
          'failed_attempts': 5,
          'locked_until': DateTime.now()
              .subtract(const Duration(seconds: 1))
              .toUtc()
              .toIso8601String(),
        }),
      },
      where: 'key=?',
      whereArgs: ['auth_pin_retry_state'],
    );
    expect(await AuthService(db).remainingAttempts, 5);
    expect(await AuthService(db).verify('9999'), isNull);
    expect(await AuthService(db).remainingAttempts, 4);
    expect(await AuthService(db).verify('1234'), UserRole.owner);
    expect(await AuthService(db).remainingAttempts, 5);
    for (var attempt = 0; attempt < 4; attempt++) {
      expect(await AuthService(db).verify('9999'), isNull);
    }
    expect(await AuthService(db).verify('1234'), UserRole.owner);
  });

  test('central permissions block staff sensitive actions', () {
    const p = PermissionService();
    expect(p.allows(UserRole.staff, AppPermission.cashSale), isTrue);
    expect(p.allows(UserRole.staff, AppPermission.backupRestore), isFalse);
    expect(
      () => p.require(UserRole.staff, AppPermission.adjustInventory),
      throwsStateError,
    );
    expect(p.allows(UserRole.owner, AppPermission.security), isTrue);
  });
  test('existing V2 database upgrades safely through V3', () async {
    final directory = await Directory.systemTemp.createTemp('v2_to_v3_');
    final databasePath = '${directory.path}/store.db';
    final old = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await MigrationV1().migrate(db);
          await MigrationV2().migrate(db);
        },
      ),
    );
    await old.close();
    final upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final upgradedDb = await upgraded.database;
    expect(
      (await upgradedDb.query(
        'schema_migrations',
        orderBy: 'version',
      )).map((r) => r['version']),
      [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
        27,
        28,
      ],
    );
    expect(
      await upgradedDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='security_profiles'",
      ),
      isNotEmpty,
    );
    await upgraded.close();
    await directory.delete(recursive: true);
  });
}
