import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v17.dart';

void main() {
  sqfliteFfiInit();

  test('V17 repairs missing consignment accounting columns safely', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''CREATE TABLE schema_migrations(
      version INTEGER PRIMARY KEY,
      applied_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE consignment_allocations(
      id INTEGER PRIMARY KEY,
      quantity INTEGER NOT NULL,
      selling_price_centavos INTEGER NOT NULL,
      payable_centavos INTEGER NOT NULL,
      margin_centavos INTEGER NOT NULL
    )''');
    await db.insert('consignment_allocations', {
      'quantity': 2,
      'selling_price_centavos': 300,
      'payable_centavos': 400,
      'margin_centavos': 200,
    });
    await db.execute('''CREATE TRIGGER consignment_allocations_no_update
      BEFORE UPDATE ON consignment_allocations BEGIN
      SELECT RAISE(ABORT,'CONSIGNMENT_ALLOCATIONS_ARE_APPEND_ONLY'); END''');

    await MigrationV17().migrate(db);

    final columns = (await db.rawQuery(
      'PRAGMA table_info(consignment_allocations)',
    )).map((row) => row['name']).toSet();
    expect(
      columns,
      containsAll([
        'sale_revenue_centavos',
        'actual_margin_centavos',
        'actual_payable_centavos',
      ]),
    );
    final row = (await db.query('consignment_allocations')).single;
    expect(row['sale_revenue_centavos'], 600);
    expect(row['actual_margin_centavos'], 200);
    expect(row['actual_payable_centavos'], 400);
    await expectLater(
      db.update('consignment_allocations', {'quantity': 3}),
      throwsA(anything),
    );
  });
}
