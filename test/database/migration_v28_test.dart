import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v28.dart';
import 'package:tindahan_ni_embi/repositories/loan_repository.dart';

void main() {
  sqfliteFfiInit();

  test(
    'V28 adds lender profile fields without changing an existing lender',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('''CREATE TABLE loan_lenders(
      id INTEGER PRIMARY KEY, name TEXT NOT NULL, contact_number TEXT,
      notes TEXT, is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''');
      await db.execute('''CREATE TABLE schema_migrations(
      version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL
    )''');
      await db.insert('loan_lenders', {
        'name': 'Rusi',
        'contact_number': '0917 000 0000',
        'notes': 'Existing lender',
        'created_at': '2026-09-01T00:00:00Z',
        'updated_at': '2026-09-01T00:00:00Z',
      });
      await MigrationV28().migrate(db);
      final lender = (await db.query('loan_lenders')).single;
      expect(lender['name'], 'Rusi');
      expect(lender['contact_number'], '0917 000 0000');
      expect(lender['notes'], 'Existing lender');
      expect(lender['collection_frequency'], 'DAILY');
      expect(lender['collection_method'], 'COLLECTOR_VISITS');
      expect(lender['contact_person'], isNull);
      expect((await db.query('schema_migrations')).single['version'], 28);
    },
  );

  test('a lender profile persists without any loan after reopening', () async {
    final directory = await Directory.systemTemp.createTemp('lender_profile_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/store.db';
    final app = AppDatabase(factory: databaseFactoryFfi, databasePath: path);
    final db = await app.database;
    final lenderId = await LoanRepository(db).createLender(
      'Juan Lending',
      contactPerson: 'Juan Dela Cruz',
      contact: '0917 123 4567',
      notes: 'Collects at 4 PM',
      frequency: 'WEEKLY',
      method: 'OWNER_PAYS',
    );
    await app.close();

    final reopened = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    addTearDown(reopened.close);
    final saved = (await LoanRepository(
      await reopened.database,
    ).lenders()).single;
    expect(saved['id'], lenderId);
    expect(saved['name'], 'Juan Lending');
    expect(saved['contact_person'], 'Juan Dela Cruz');
    expect(saved['collection_frequency'], 'WEEKLY');
    expect(saved['collection_method'], 'OWNER_PAYS');
    expect(await LoanRepository(await reopened.database).loans(), isEmpty);
  });
}
