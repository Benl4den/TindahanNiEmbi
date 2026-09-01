import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';

void main() {
  sqfliteFfiInit();

  late AppDatabase appDatabase;
  late Database database;
  late SqliteCategoryRepository repository;

  setUp(() async {
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    database = await appDatabase.database;
    repository = SqliteCategoryRepository(database);
  });

  tearDown(() => appDatabase.close());

  test('creates and reads active categories in alphabetical order', () async {
    final drinks = await repository.create('  Mga   Ilimnon  ');
    await repository.create('Biskwit');

    expect(drinks.name, 'Mga Ilimnon');
    final active = await repository.getActive();
    expect(active.map((category) => category.name), ['Biskwit', 'Mga Ilimnon']);
    expect(active.every((category) => !category.isArchived), isTrue);
  });

  test('edits an active category', () async {
    final category = await repository.create('Softdrinks');
    final updated = await repository.update(
      id: category.id,
      name: 'Mga Softdrinks',
    );

    expect(updated.id, category.id);
    expect(updated.name, 'Mga Softdrinks');
    expect((await repository.getActive()).single.name, 'Mga Softdrinks');
  });

  test('rejects duplicate category names ignoring case', () async {
    await repository.create('De Lata');

    await expectLater(
      repository.create('de lata'),
      throwsA(isA<DuplicateCategoryNameException>()),
    );

    final second = await repository.create('Inom');
    await expectLater(
      repository.update(id: second.id, name: 'DE LATA'),
      throwsA(isA<DuplicateCategoryNameException>()),
    );
  });

  test(
    'archives without deleting and excludes category from active reads',
    () async {
      final category = await repository.create('Kape');
      await repository.archive(category.id);

      expect(await repository.getActive(), isEmpty);
      final stored = (await database.query(
        'categories',
        where: 'id = ?',
        whereArgs: [category.id],
      )).single;
      expect(stored['is_archived'], 1);
      expect(stored['name'], 'Kape');
    },
  );

  test(
    'archived category keeps historical product foreign key valid',
    () async {
      final category = await repository.create('Tinapay');
      const now = '2026-09-02T00:00:00.000Z';
      final productId = await database.insert('products', {
        'category_id': category.id,
        'name': 'Pan de Sal',
        'purchase_price_centavos': 200,
        'selling_price_centavos': 300,
        'current_quantity': 0,
        'minimum_stock_level': 2,
        'created_at': now,
        'updated_at': now,
      });

      await repository.archive(category.id);
      final product = (await database.query(
        'products',
        where: 'id = ?',
        whereArgs: [productId],
      )).single;
      expect(product['category_id'], category.id);
    },
  );
}
