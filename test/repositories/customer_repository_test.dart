import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late SqliteCustomerRepository repo;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    repo = SqliteCustomerRepository(db);
  });
  tearDown(() => app.close());
  test('create, normalize, edit and search customer', () async {
    final c = await repo.create(
      const CustomerDraft(fullName: '  Juan   Dela Cruz ', nickname: ' Jun '),
    );
    expect(c.fullName, 'Juan Dela Cruz');
    expect((await repo.searchActive('jun')).single.id, c.id);
    final u = await repo.update(
      c.id,
      const CustomerDraft(fullName: 'Juan Cruz', mobileNumber: '0912'),
    );
    expect(u.fullName, 'Juan Cruz');
    expect(u.mobileNumber, '0912');
  });
  test('archive excludes active without deleting', () async {
    final c = await repo.create(const CustomerDraft(fullName: 'Maria'));
    await repo.archive(c.id);
    expect(await repo.searchActive(), isEmpty);
    expect(
      (await db.query(
        'customers',
        where: 'id=?',
        whereArgs: [c.id],
      )).single['is_archived'],
      1,
    );
  });
  test(
    'details derives balance and chronological histories from ledger',
    () async {
      final c = await repo.create(const CustomerDraft(fullName: 'Pedro'));
      final cat = (await SqliteCategoryRepository(db).create('Inom')).id;
      final p = await SqliteProductRepository(db).create(
        ProductDraft(
          categoryId: cat,
          name: 'Kape',
          photoPath: '/k.jpg',
          purchasePriceCentavos: 500,
          sellingPriceCentavos: 1000,
          startingQuantity: 5,
          minimumStockLevel: 1,
        ),
      );
      await UtangRepository(db).save(
        UtangDraft(
          customerId: c.id,
          items: [UtangItemDraft(productId: p.id, quantity: 2)],
        ),
      );
      await PaymentRepository(db).record(customerId: c.id, amountCentavos: 500);
      final zero = await repo.create(
        const CustomerDraft(fullName: 'Aaron Zero'),
      );
      final ordered = await repo.searchActive();
      expect(ordered.map((x) => x.id), [c.id, zero.id]);
      expect((await repo.searchActive('Aaron')).single.balanceCentavos, 0);
      final d = await repo.details(c.id);
      expect(d.customer.balanceCentavos, 1500);
      expect(d.ledger.length, 2);
      expect(d.utangHistory.length, 1);
      expect(d.paymentHistory.length, 1);
      await repo.archive(c.id);
      expect((await repo.details(c.id)).ledger.length, 2);
    },
  );
  test(
    'blank name rejected',
    () => expect(
      () => repo.create(const CustomerDraft(fullName: ' ')),
      throwsA(isA<InvalidCustomerException>()),
    ),
  );
}
