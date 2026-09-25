import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/consignment.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/models/expense.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/consignment_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/expense_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/reversal_repository.dart';
import 'package:tindahan_ni_embi/repositories/gcash_service_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_accounting_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';
import 'package:tindahan_ni_embi/services/data_integrity_service.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late Product p;
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
        startingQuantity: 5,
        minimumStockLevel: 5,
      ),
    );
  });
  tearDown(() => app.close());
  test(
    'period aggregates use local inclusive start and exclusive end',
    () async {
      final start = DateTime(2026, 3, 2);
      final end = DateTime(2026, 3, 9);
      final dates = [
        DateTime(2026, 3, 1, 23, 59),
        start,
        DateTime(2026, 3, 8, 23, 59),
        end,
      ];
      for (var i = 0; i < dates.length; i++) {
        final stamp = dates[i].toUtc().toIso8601String();
        await db.insert('cash_sales', {
          'reference': 'BOUNDARY-$i',
          'total_centavos': (i + 1) * 100,
          'status': 'POSTED',
          'occurred_at': stamp,
          'created_at': stamp,
        });
      }
      final repo = OperationsRepository(db);
      final week = await repo.daily(start, endDate: end);
      expect(week.cashSales, 500);
      expect(week.cashSaleCount, 2);
      final today = await repo.daily(start);
      expect(today.cashSales, 200);
      final month = await repo.daily(
        DateTime(2026, 3),
        endDate: DateTime(2026, 4),
      );
      expect(month.cashSales, 1000);
      expect(month.cashSaleCount, 4);
    },
  );
  test(
    'restock suggestion and daily totals keep cash UTANG and payable separate',
    () async {
      final customer = await SqliteCustomerRepository(db)
          .create(const CustomerDraft(fullName: 'A'));
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: p.id, quantity: 1)]);
      await UtangRepository(db).save(
        UtangDraft(
          customerId: customer.id,
          items: [UtangItemDraft(productId: p.id, quantity: 1)],
        ),
      );
      await PaymentRepository(db)
          .record(customerId: customer.id, amountCentavos: 100);
      final restock = (await OperationsRepository(db).restock()).single;
      expect(restock.suggested, 2);
      final d = await OperationsRepository(db).daily(DateTime.now());
      expect(d.cashSales, 200);
      expect(d.newUtang, 200);
      expect(d.payments, 100);
      expect(d.recordedCashIn, 300);
      expect(d.transactionCount, 3);
      final dates = await OperationsRepository(db).closingDates();
      expect(dates, hasLength(1));
    },
  );
  test('daily closing uses stored GCash service movements and counts only fees as earnings', () async {
    await PaymentAccountingRepository(db, actorRole: 'OWNER').addManual(
      type: 'OPENING_BALANCE',
      amountCentavos: 50000,
      reason: 'Start',
      ownerPinAuthorized: true,
    );
    final services = GCashServiceRepository(db);
    await services.record(
      type: 'CASH_IN',
      principalCentavos: 10000,
      feeCentavos: 500,
      feeOption: 'DEDUCTED',
    );
    await services.record(
      type: 'CASH_OUT',
      principalCentavos: 10000,
      feeCentavos: 500,
      feeOption: 'ADDED',
      physicalCashAvailabilityAcknowledged: true,
    );
    final daily = await OperationsRepository(db).daily(DateTime.now());
    expect(daily.cashReceived, 10000);
    expect(daily.cashPaid, 10000);
    expect(daily.gcashMoneyIn, 60500);
    expect(daily.gcashMoneyOut, 9500);
    expect(daily.serviceFeeIncome, 1000);
    expect(daily.totalEarnings, 1000);
  });
  test(
    'closed daily summary remains frozen after later transactions',
    () async {
      final operations = OperationsRepository(db);
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: p.id, quantity: 1)]);
      final snapshot = await operations.closeDay(DateTime.now());
      expect(snapshot.summary.totalSales, 200);

      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: p.id, quantity: 1)]);
      expect((await operations.daily(DateTime.now())).totalSales, 400);
      expect((await operations.summaryForDate(DateTime.now())).totalSales, 200);
      expect(await operations.snapshotFor(DateTime.now()), isNotNull);
    },
  );
  test('cross-day reversals keep original activity on its date', () async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayStamp = DateTime(
      yesterday.year,
      yesterday.month,
      yesterday.day,
      12,
    ).toUtc().toIso8601String();
    final saleId = await CashSaleRepository(db)
        .save([UtangItemDraft(productId: p.id, quantity: 1)]);
    await db.update(
      'cash_sales',
      {'occurred_at': yesterdayStamp},
      where: 'id=?',
      whereArgs: [saleId],
    );
    await ReversalRepository(db)
        .reverseCashSale(saleId, 'Wrong sale', ownerPinAuthorized: true);
    final category = (await ExpenseRepository(db).categories()).first.id;
    final expense = await ExpenseRepository(db).add(
      ExpenseDraft(
        categoryId: category,
        amountCentavos: 300,
        description: 'Correction test',
        expenseDateTime: yesterday,
      ),
    );
    await ExpenseRepository(db)
        .reverse(expense.id, reason: 'Wrong expense', ownerPinAuthorized: true);
    await db.update('products', {'name': 'Renamed later'},
        where: 'id=?', whereArgs: [p.id]);
    final operations = OperationsRepository(db);
    final oldDay = await operations.daily(yesterday);
    final today = await operations.daily(DateTime.now());
    expect(oldDay.cashSales, 200);
    expect(oldDay.operatingExpenses, 300);
    expect(oldDay.topProducts.single['name'], 'P');
    expect(today.cashSales, -200);
    expect(today.operatingExpenses, -300);
    final dates = await operations.closingDates();
    expect(
      dates,
      contains(DateTime(yesterday.year, yesterday.month, yesterday.day)),
    );
    expect(
      dates,
      contains(
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
      ),
    );
  });

  test('closing rejects stale displayed totals without saving', () async {
    final operations = OperationsRepository(db);
    final day = DateTime.now();
    final displayed = await operations.daily(day);
    await CashSaleRepository(db)
        .save([UtangItemDraft(productId: p.id, quantity: 1)]);
    await expectLater(
      operations.closeDay(day, expectedSummary: displayed),
      throwsA(isA<StateError>()),
    );
    expect(await operations.snapshotFor(day), isNull);
    final current = await operations.daily(day);
    final saved = await operations.closeDay(day, expectedSummary: current);
    expect(saved.summary.cashSales, 200);
  });
  test(
    'UTANG and payment reversals stay dated; consignment nets out',
    () async {
      final previous = DateTime.now().subtract(const Duration(days: 1));
      final stamp = DateTime(
        previous.year,
        previous.month,
        previous.day,
        12,
      ).toUtc().toIso8601String();
      final customer = await SqliteCustomerRepository(db)
          .create(const CustomerDraft(fullName: 'Closing customer'));
      final utangId = await UtangRepository(db).save(
        UtangDraft(
          customerId: customer.id,
          items: [UtangItemDraft(productId: p.id, quantity: 1)],
        ),
      );
      final paymentId = await PaymentRepository(db)
          .record(customerId: customer.id, amountCentavos: 100);
      await db.update(
        'utang_transactions',
        {'occurred_at': stamp},
        where: 'id=?',
        whereArgs: [utangId],
      );
      await db.update(
        'utang_payments',
        {'paid_at': stamp},
        where: 'id=?',
        whereArgs: [paymentId],
      );
      final reversal = ReversalRepository(db);
      await reversal.reversePayment(
        paymentId,
        'Wrong payment',
        ownerPinAuthorized: true,
      );
      await reversal.reverseUtang(
        utangId,
        'Wrong credit',
        ownerPinAuthorized: true,
      );

      final consignments = ConsignmentRepository(db);
      final supplier = await consignments.createConsignor('Closing supplier');
      await consignments.receive(
        ConsignmentReceiptDraft(
          consignorId: supplier,
          productId: p.id,
          boxes: 1,
          unitsPerBox: 1,
          unitCostCentavos: 150,
          sellingPriceCentavos: 200,
        ),
      );
      final saleId = await CashSaleRepository(db)
          .save([UtangItemDraft(productId: p.id, quantity: 1)]);
      await reversal.reverseCashSale(
        saleId,
        'Wrong supplier sale',
        ownerPinAuthorized: true,
      );

      final operations = OperationsRepository(db);
      final oldDay = await operations.daily(previous);
      final today = await operations.daily(DateTime.now());
      expect(oldDay.newUtang, 200);
      expect(oldDay.payments, 100);
      expect(today.newUtang, -200);
      expect(today.payments, -100);
      expect(today.consignmentSales, 0);
      expect(today.supplierPayable, 0);
      expect(today.consignmentMargin, 0);
    },
  );
  test(
    'daily summary reports consignment payable and margin independently',
    () async {
      final cr = ConsignmentRepository(db),
          cid = await cr.createConsignor('ABC');
      await cr.receive(
        ConsignmentReceiptDraft(
          consignorId: cid,
          productId: p.id,
          boxes: 1,
          unitsPerBox: 2,
          unitCostCentavos: 150,
          sellingPriceCentavos: 200,
        ),
      );
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: p.id, quantity: 1)]);
      final d = await OperationsRepository(db).daily(DateTime.now());
      expect(d.consignmentSales, 200);
      expect(d.supplierPayable, 150);
      expect(d.consignmentMargin, 50);
    },
  );
  test(
    'restock exposes connected consignor for consignment products',
    () async {
      final cr = ConsignmentRepository(db),
          cid = await cr.createConsignor('ABC');
      await cr.receive(
        ConsignmentReceiptDraft(
          consignorId: cid,
          productId: p.id,
          boxes: 1,
          unitsPerBox: 1,
          unitCostCentavos: 150,
          sellingPriceCentavos: 200,
        ),
      );

      final item = (await OperationsRepository(db).restock(filter: 'ALL'))
          .where((x) => x.product.id == p.id)
          .single;
      expect(item.isConsignment, isTrue);
      expect(item.consignorId, cid);
      expect(item.consignorName, 'ABC');
    },
  );
  test(
    'restock default and statuses use one authoritative boundary rule',
    () async {
      final category = (await SqliteCategoryRepository(db).getActive()).first;
      final products = SqliteProductRepository(db);
      final above = await products.create(
        ProductDraft(
          categoryId: category.id,
          name: 'Above',
          photoPath: '/above',
          purchasePriceCentavos: 1,
          sellingPriceCentavos: 1,
          startingQuantity: 6,
          minimumStockLevel: 5,
        ),
      );
      final zeroMinimum = await products.create(
        ProductDraft(
          categoryId: category.id,
          name: 'Zero minimum',
          photoPath: '/zero-min',
          purchasePriceCentavos: 1,
          sellingPriceCentavos: 1,
          startingQuantity: 2,
          minimumStockLevel: 0,
        ),
      );
      final out = await products.create(
        ProductDraft(
          categoryId: category.id,
          name: 'Out',
          photoPath: '/out',
          purchasePriceCentavos: 1,
          sellingPriceCentavos: 1,
          startingQuantity: 0,
          minimumStockLevel: 5,
        ),
      );
      final repository = OperationsRepository(db);
      final needs = await repository.restock();
      expect(needs.map((x) => x.product.id), containsAll([p.id, out.id]));
      expect(needs.map((x) => x.product.id), isNot(contains(above.id)));
      expect(needs.map((x) => x.product.id), isNot(contains(zeroMinimum.id)));
      expect(
        (await repository.restock(filter: 'LOW')).map((x) => x.product.id),
        contains(p.id),
      );
      expect(
        (await repository.restock(filter: 'OUT')).map((x) => x.product.id),
        contains(out.id),
      );
      expect(
        (await repository.restock(filter: 'ALL'))
            .firstWhere((x) => x.product.id == above.id)
            .suggested,
        0,
      );
    },
  );
  test(
    'integrity check passes healthy DB and detects deliberate mismatch',
    () async {
      expect((await DataIntegrityService(db).check()).healthy, isTrue);
      await db.execute('DROP TRIGGER products_quantity_matches_ledger');
      await db.update(
        'products',
        {'current_quantity': 99},
        where: 'id=?',
        whereArgs: [p.id],
      );
      final result = await DataIntegrityService(db).check();
      expect(result.healthy, isFalse);
      expect(result.problems.join(), contains('stock balance'));
    },
  );
}
