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
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
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
