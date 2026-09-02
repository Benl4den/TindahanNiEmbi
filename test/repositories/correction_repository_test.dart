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
import 'package:tindahan_ni_embi/repositories/correction_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/reversal_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late Product product;
  late Customer first, second;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    final category = await SqliteCategoryRepository(db).create('C');
    product = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category.id,
        name: 'P',
        photoPath: '/p',
        purchasePriceCentavos: 100,
        sellingPriceCentavos: 200,
        startingQuantity: 20,
        minimumStockLevel: 1,
      ),
    );
    first = await SqliteCustomerRepository(db)
        .create(const CustomerDraft(fullName: 'First'));
    second = await SqliteCustomerRepository(db)
        .create(const CustomerDraft(fullName: 'Second'));
  });
  tearDown(() => app.close());

  test(
    'cash correction preserves original and applies corrected stock once',
    () async {
      final original = await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 5)]);
      final result = await CorrectionRepository(db).correctCashSale(
        originalId: original,
        correctedItems: [UtangItemDraft(productId: product.id, quantity: 2)],
        reason: 'Wrong quantity',
        ownerPinAuthorized: true,
      );
      expect(
        (await db.query(
          'cash_sales',
          where: 'id=?',
          whereArgs: [original],
        )).single['status'],
        'REVERSED',
      );
      expect(
        (await db.query(
          'cash_sales',
          where: 'id=?',
          whereArgs: [result.replacementId],
        )).single['status'],
        'POSTED',
      );
      expect((await db.query('products')).single['current_quantity'], 18);
      expect(await db.query('transaction_corrections'), hasLength(1));
      await expectLater(
        CorrectionRepository(db).correctCashSale(
          originalId: original,
          correctedItems: [UtangItemDraft(productId: product.id, quantity: 1)],
          reason: 'Again',
          ownerPinAuthorized: true,
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'UTANG correction can move customer and compensates both ledgers',
    () async {
      final original = await UtangRepository(db).save(
        UtangDraft(
          customerId: first.id,
          items: [UtangItemDraft(productId: product.id, quantity: 3)],
        ),
      );
      await CorrectionRepository(db).correctUtang(
        originalId: original,
        corrected: UtangDraft(
          customerId: second.id,
          items: [UtangItemDraft(productId: product.id, quantity: 1)],
        ),
        reason: 'Wrong customer',
        ownerPinAuthorized: true,
      );
      expect(await PaymentRepository(db).balanceFor(first.id), 0);
      expect(await PaymentRepository(db).balanceFor(second.id), 200);
      expect((await db.query('products')).single['current_quantity'], 19);
    },
  );

  test(
    'payment correction preserves original and derives correct balance',
    () async {
      await UtangRepository(db).save(
        UtangDraft(
          customerId: first.id,
          items: [UtangItemDraft(productId: product.id, quantity: 5)],
        ),
      );
      final payment = await PaymentRepository(db)
          .record(customerId: first.id, amountCentavos: 500);
      await CorrectionRepository(db).correctPayment(
        originalId: payment,
        correctedAmountCentavos: 50,
        reason: 'Wrong amount',
        ownerPinAuthorized: true,
      );
      expect(await PaymentRepository(db).balanceFor(first.id), 950);
      expect(
        (await db.query(
          'utang_payments',
          where: 'id=?',
          whereArgs: [payment],
        )).single['status'],
        'REVERSED',
      );
      expect(await db.query('utang_payments'), hasLength(2));
    },
  );

  test(
    'consignment cash correction preserves FIFO cost and net payable',
    () async {
      final consignments = ConsignmentRepository(db),
          consignor = await consignments.createConsignor('Supplier');
      await consignments.receive(
        ConsignmentReceiptDraft(
          consignorId: consignor,
          productId: product.id,
          boxes: 1,
          unitsPerBox: 5,
          unitCostCentavos: 125,
          sellingPriceCentavos: 200,
        ),
      );
      final original = await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 4)]);
      await CorrectionRepository(db).correctCashSale(
        originalId: original,
        correctedItems: [UtangItemDraft(productId: product.id, quantity: 2)],
        reason: 'Wrong quantity',
        ownerPinAuthorized: true,
      );
      final summary = await consignments.summary();
      expect(summary.payableCentavos, 250);
      expect(summary.marginCentavos, 150);
      final active = await db.rawQuery(
        '''SELECT a.unit_cost_centavos FROM consignment_allocations a WHERE NOT EXISTS(SELECT 1 FROM consignment_allocation_reversals r WHERE r.allocation_id=a.id)''',
      );
      expect(active.single['unit_cost_centavos'], 125);
    },
  );

  test(
    'owner PIN flag and role are mandatory for correction and reversal',
    () async {
      final sale = await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 1)]);
      await expectLater(
        CorrectionRepository(db).correctCashSale(
          originalId: sale,
          correctedItems: [UtangItemDraft(productId: product.id, quantity: 1)],
          reason: 'x',
          ownerPinAuthorized: false,
        ),
        throwsA(isA<CorrectionException>()),
      );
      await expectLater(
        ReversalRepository(db)
            .reverseCashSale(sale, 'x', ownerPinAuthorized: false),
        throwsA(isA<ReversalException>()),
      );
      await expectLater(
        CorrectionRepository(db, actorRole: 'STAFF').correctCashSale(
          originalId: sale,
          correctedItems: [UtangItemDraft(productId: product.id, quantity: 1)],
          reason: 'x',
          ownerPinAuthorized: true,
        ),
        throwsA(isA<CorrectionException>()),
      );
    },
  );

  test('Daily Closing uses corrected net transaction totals', () async {
    final cash = await CashSaleRepository(db)
        .save([UtangItemDraft(productId: product.id, quantity: 3)]);
    await CorrectionRepository(db).correctCashSale(
      originalId: cash,
      correctedItems: [UtangItemDraft(productId: product.id, quantity: 1)],
      reason: 'Wrong quantity',
      ownerPinAuthorized: true,
    );
    final utang = await UtangRepository(db).save(
      UtangDraft(
        customerId: first.id,
        items: [UtangItemDraft(productId: product.id, quantity: 2)],
      ),
    );
    await CorrectionRepository(db).correctUtang(
      originalId: utang,
      corrected: UtangDraft(
        customerId: first.id,
        items: [UtangItemDraft(productId: product.id, quantity: 1)],
      ),
      reason: 'Wrong quantity',
      ownerPinAuthorized: true,
    );
    final payment = await PaymentRepository(db)
        .record(customerId: first.id, amountCentavos: 150);
    await CorrectionRepository(db).correctPayment(
      originalId: payment,
      correctedAmountCentavos: 50,
      reason: 'Wrong amount',
      ownerPinAuthorized: true,
    );
    final closing = await OperationsRepository(db).daily(DateTime.now());
    expect(closing.cashSales, 200);
    expect(closing.newUtang, 200);
    expect(closing.payments, 50);
    expect(closing.recordedCashIn, 250);
  });
}
