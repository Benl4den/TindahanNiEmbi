import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/consignment.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/consignment_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/reversal_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late Product p;
  late Customer customer;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    final c = await SqliteCategoryRepository(db).create('C');
    p = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: c.id,
        name: 'P',
        photoPath: '/p',
        purchasePriceCentavos: 100,
        sellingPriceCentavos: 200,
        startingQuantity: 10,
        minimumStockLevel: 1,
      ),
    );
    customer = await SqliteCustomerRepository(db)
        .create(const CustomerDraft(fullName: 'Juan'));
  });
  tearDown(() => app.close());
  test('Cash Sale reversal restores stock and duplicate is blocked', () async {
    final sale = await CashSaleRepository(db)
        .save([UtangItemDraft(productId: p.id, quantity: 2)]);
    await ReversalRepository(db)
        .reverseCashSale(sale, 'Wrong quantity', ownerPinAuthorized: true);
    expect((await db.query('products')).single['current_quantity'], 10);
    expect((await db.query('cash_sales')).single['status'], 'REVERSED');
    await expectLater(
      ReversalRepository(db)
          .reverseCashSale(sale, 'Again', ownerPinAuthorized: true),
      throwsA(isA<ReversalException>()),
    );
  });
  test(
    'UTANG and Payment reversals restore stock and customer balance',
    () async {
      final utang = await UtangRepository(db).save(
        UtangDraft(
          customerId: customer.id,
          items: [UtangItemDraft(productId: p.id, quantity: 2)],
        ),
      );
      final payment = await PaymentRepository(db)
          .record(customerId: customer.id, amountCentavos: 100);
      await ReversalRepository(db)
          .reversePayment(payment, 'Wrong payment', ownerPinAuthorized: true);
      expect(await PaymentRepository(db).balanceFor(customer.id), 400);
      await ReversalRepository(db)
          .reverseUtang(utang, 'Wrong customer', ownerPinAuthorized: true);
      expect(await PaymentRepository(db).balanceFor(customer.id), 0);
      expect((await db.query('products')).single['current_quantity'], 10);
    },
  );
  test('consignment liability and margin reverse atomically', () async {
    final cr = ConsignmentRepository(db),
        consignor = await cr.createConsignor('ABC');
    await cr.receive(
      ConsignmentReceiptDraft(
        consignorId: consignor,
        productId: p.id,
        boxes: 1,
        unitsPerBox: 2,
        unitCostCentavos: 150,
        sellingPriceCentavos: 200,
      ),
    );
    final sale = await CashSaleRepository(db)
        .save([UtangItemDraft(productId: p.id, quantity: 2)]);
    expect((await cr.summary()).payableCentavos, 300);
    await ReversalRepository(db)
        .reverseCashSale(sale, 'Returned', ownerPinAuthorized: true);
    final s = await cr.summary();
    expect(s.payableCentavos, 0);
    expect(s.marginCentavos, 0);
    expect((await db.query('consignment_allocation_reversals')).length, 1);
  });
  test('staff and blank reason are rejected before writes', () async {
    final sale = await CashSaleRepository(db)
        .save([UtangItemDraft(productId: p.id, quantity: 1)]);
    await expectLater(
      ReversalRepository(
        db,
        actorRole: 'STAFF',
      ).reverseCashSale(sale, 'x', ownerPinAuthorized: true),
      throwsA(isA<ReversalException>()),
    );
    await expectLater(
      ReversalRepository(db)
          .reverseCashSale(sale, ' ', ownerPinAuthorized: true),
      throwsA(isA<ReversalException>()),
    );
    expect(await db.query('transaction_reversals'), isEmpty);
  });
  test(
    'failed UTANG reversal rolls back restored stock and reversal rows',
    () async {
      final utang = await UtangRepository(db).save(
        UtangDraft(
          customerId: customer.id,
          items: [UtangItemDraft(productId: p.id, quantity: 2)],
        ),
      );
      await PaymentRepository(db)
          .record(customerId: customer.id, amountCentavos: 100);
      await expectLater(
        ReversalRepository(db)
            .reverseUtang(utang, 'Invalid', ownerPinAuthorized: true),
        throwsA(anything),
      );
      expect((await db.query('products')).single['current_quantity'], 8);
      expect((await db.query('utang_transactions')).single['status'], 'POSTED');
      expect(await db.query('transaction_reversals'), isEmpty);
    },
  );
}
