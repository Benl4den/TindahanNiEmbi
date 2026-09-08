import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v18.dart';

void main() {
  sqfliteFfiInit();

  test('V18 adds payment sources and safely backfills legacy rows', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
      'CREATE TABLE schema_migrations(version INTEGER PRIMARY KEY,applied_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE cash_sales(id INTEGER PRIMARY KEY,total_centavos INTEGER NOT NULL,occurred_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE expenses(id INTEGER PRIMARY KEY,amount_centavos INTEGER NOT NULL,expense_datetime TEXT NOT NULL)',
    );
    await db.execute('CREATE TABLE utang_payments(id INTEGER PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE consignor_remittances(id INTEGER PRIMARY KEY)',
    );
    final now = DateTime.utc(2026, 9, 9).toIso8601String();
    await db.insert('cash_sales', {
      'total_centavos': 12500,
      'occurred_at': now,
    });
    await db.insert('expenses', {
      'amount_centavos': 3000,
      'expense_datetime': now,
    });

    await MigrationV18().migrate(db);
    await MigrationV18().migrate(db);

    expect((await db.query('sale_payments')).single['payment_method'], 'CASH');
    expect(
      (await db.query('expense_payments')).single['payment_method'],
      'CASH',
    );
    expect(await db.query('gcash_ledger_entries'), isEmpty);
    expect(
      await db.query('schema_migrations', where: 'version=18'),
      hasLength(1),
    );
    await expectLater(
      db.update('sale_payments', {'payment_method': 'GCASH'}),
      throwsA(anything),
    );
  });
}
