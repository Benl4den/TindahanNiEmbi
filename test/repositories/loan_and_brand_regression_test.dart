import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/database/migrations/migration_v26.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/models/payment_method.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/brand_analytics_repository.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/loan_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/reports_repository.dart';
import 'package:tindahan_ni_embi/repositories/special_inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/transaction_history_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

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

  test('loan reversal requires owner authorization and preserves daily cash history', () async {
    final loans = LoanRepository(db, actorRole: 'OWNER');
    final lender = await loans.createLender('Test lender');
    final loanId = await loans.create(
      lenderId: lender,
      borrowed: 10000,
      agreed: 12000,
      sourceKind: 'NEW',
      start: DateTime.now(),
      frequency: 'DAILY',
      receivedMethod: PaymentMethod.cash,
    );
    await loans.pay(loanId: loanId, amount: 2000, method: PaymentMethod.cash);
    final paymentId = (await loans.paymentsFor(loanId)).single['id']! as int;
    final operations = OperationsRepository(db);
    final before = await operations.daily(DateTime.now());
    expect(before.loanCashReceived, 10000);
    expect(before.loanCashPayments, 2000);
    expect(before.cashDifference, 8000);
    await expectLater(
      loans.reversePayment(paymentId: paymentId, reason: 'Mistake'),
      throwsStateError,
    );
    await loans.reversePayment(
      paymentId: paymentId,
      reason: 'Mistake',
      ownerPinAuthorized: true,
    );
    final after = await operations.daily(DateTime.now());
    expect(after.loanCashPayments, 2000);
    expect(after.loanCashPaymentReversals, 2000);
    expect(after.cashDifference, 10000);
    expect((await loans.paymentsFor(loanId)).single['status'], 'REVERSED');
    expect(await operations.closingDates(), isNotEmpty);
  });

  test('GCash loan cancellation posts a linked reversal instead of a second adjustment', () async {
    final loans = LoanRepository(db, actorRole: 'OWNER');
    final lender = await loans.createLender('Lender');
    final loanId = await loans.create(
      lenderId: lender,
      borrowed: 10000,
      agreed: 12000,
      sourceKind: 'NEW',
      start: DateTime.now(),
      frequency: 'DAILY',
      receivedMethod: PaymentMethod.gcash,
    );
    await loans.pay(loanId: loanId, amount: 2000, method: PaymentMethod.gcash);
    final paymentId = (await loans.paymentsFor(loanId)).single['id']! as int;
    await loans.reversePayment(
      paymentId: paymentId,
      reason: 'Duplicate',
      ownerPinAuthorized: true,
    );
    final entries = await db.query(
      'gcash_ledger_entries',
      where: 'loan_payment_id=?',
      whereArgs: [paymentId],
      orderBy: 'id',
    );
    expect(entries.map((e) => e['entry_type']), ['ADJUSTMENT_OUT', 'REVERSAL']);
    expect(entries.last['reversal_of_entry_id'], entries.first['id']);
    expect(
      entries.fold<int>(
        0,
        (sum, e) => sum + (e['amount_change_centavos']! as int),
      ),
      0,
    );
  });

  test(
    'Maya loan movements appear in daily closing without changing cash',
    () async {
      final loans = LoanRepository(db, actorRole: 'OWNER');
      final lender = await loans.createLender('Maya lender');
      final loanId = await loans.create(
        lenderId: lender,
        borrowed: 10000,
        agreed: 12000,
        sourceKind: 'NEW',
        start: DateTime.now(),
        frequency: 'DAILY',
        receivedMethod: PaymentMethod.maya,
      );
      await loans.pay(loanId: loanId, amount: 2000, method: PaymentMethod.maya);
      final paymentId = (await loans.paymentsFor(loanId)).single['id']! as int;
      await loans.reversePayment(
        paymentId: paymentId,
        reason: 'Duplicate',
        ownerPinAuthorized: true,
      );
      final summary = await OperationsRepository(db).daily(DateTime.now());
      expect(summary.loanMayaReceived, 10000);
      expect(summary.loanMayaPayments, 2000);
      expect(summary.loanMayaPaymentReversals, 2000);
      expect(summary.cashDifference, 0);
    },
  );

  test(
    'brand analytics keeps sale-time price and attribution after edits',
    () async {
      final category = await SqliteCategoryRepository(db).create('Snacks');
      final product = await SqliteProductRepository(db).create(
        ProductDraft(
          categoryId: category.id,
          name: 'Snack',
          photoPath: '/snack',
          purchasePriceCentavos: 500,
          sellingPriceCentavos: 900,
          startingQuantity: 5,
          minimumStockLevel: 1,
        ),
      );
      final brands = SpecialInventoryRepository(db);
      final brand = await brands.createBrand('Brand A');
      await brands.assign(product.id, brand.code);
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 1)]);
      final analytics = BrandAnalyticsRepository(db);
      final original = await analytics.summary(brand.code);
      expect(original['sales'], 900);
      expect(original['cost'], 500);
      await db.update(
        'products',
        {'purchase_price_centavos': 2000},
        where: 'id=?',
        whereArgs: [product.id],
      );
      await brands.remove(product.id, brand.code);
      final after = await analytics.summary(brand.code);
      expect(after['sales'], original['sales']);
      expect(after['cost'], original['cost']);
    },
  );

  test(
    'adding a product to a brand includes its earlier posted sales',
    () async {
      final category = await SqliteCategoryRepository(db).create('Goods');
      final product = await SqliteProductRepository(db).create(
        ProductDraft(
          categoryId: category.id,
          name: 'Earlier sale',
          photoPath: '/earlier',
          purchasePriceCentavos: 400,
          sellingPriceCentavos: 700,
          startingQuantity: 5,
          minimumStockLevel: 1,
        ),
      );
      await CashSaleRepository(db)
          .save([UtangItemDraft(productId: product.id, quantity: 2)]);
      final brands = SpecialInventoryRepository(db);
      final brand = await brands.createBrand('New brand');
      expect(
        (await BrandAnalyticsRepository(db).summary(brand.code))['sales'],
        0,
      );
      await brands.assign(product.id, brand.code);
      final summary = await BrandAnalyticsRepository(db).summary(brand.code);
      expect(summary['sales'], 1400);
      expect(summary['units'], 2);
      expect(summary['estimatedItems'], 1);
      await brands.assign(product.id, brand.code);
      expect(
        (await BrandAnalyticsRepository(db).summary(brand.code))['sales'],
        1400,
      );
    },
  );

  test('upgrade fills older sales for an already assigned brand', () async {
    final category = await SqliteCategoryRepository(db).create('Goods');
    final product = await SqliteProductRepository(db).create(
      ProductDraft(
        categoryId: category.id,
        name: 'Previously assigned',
        photoPath: '/previous',
        purchasePriceCentavos: 300,
        sellingPriceCentavos: 500,
        startingQuantity: 3,
        minimumStockLevel: 1,
      ),
    );
    await CashSaleRepository(db)
        .save([UtangItemDraft(productId: product.id, quantity: 1)]);
    final brand = await SpecialInventoryRepository(db)
        .createBrand('Older brand');
    await db.insert('product_inventory_groups', {
      'product_id': product.id,
      'inventory_group_id': brand.id,
      'assigned_at': DateTime.now().toUtc().toIso8601String(),
    });
    expect(
      (await BrandAnalyticsRepository(db).summary(brand.code))['sales'],
      0,
    );
    await MigrationV26().migrate(db);
    expect(
      (await BrandAnalyticsRepository(db).summary(brand.code))['sales'],
      500,
    );
  });

  test(
    'Maya histories keep their payment label and opening UTANG is not a sale',
    () async {
      final category = await SqliteCategoryRepository(db).create('Goods');
      final product = await SqliteProductRepository(db).create(
        ProductDraft(
          categoryId: category.id,
          name: 'Item',
          photoPath: '/item',
          purchasePriceCentavos: 500,
          sellingPriceCentavos: 900,
          startingQuantity: 5,
          minimumStockLevel: 1,
        ),
      );
      await CashSaleRepository(db).save([
        UtangItemDraft(productId: product.id, quantity: 1),
      ], paymentMethod: PaymentMethod.maya);
      final saleHistory = await SpecialInventoryRepository(db)
          .productSalesHistory(product.id);
      expect(saleHistory.single['source'], 'Maya sale');
      final customer = await SqliteCustomerRepository(db)
          .create(const CustomerDraft(fullName: 'Customer'));
      await UtangRepository(db)
          .addExistingBalance(customerId: customer.id, amountCentavos: 1000);
      final history = await CashSaleRepository(db).history();
      expect(history, hasLength(1));
      expect(
        (await CashSaleRepository(db).history(type: 'MAYA'))
            .single
            .paymentMethod,
        PaymentMethod.maya,
      );
      expect(await CashSaleRepository(db).history(type: 'CASH'), isEmpty);
      final transactions = TransactionHistoryRepository(db);
      expect(
        (await transactions.recent(search: 'Existing UTANG')).single.title,
        contains('Existing UTANG'),
      );
      await PaymentRepository(db).record(
        customerId: customer.id,
        amountCentavos: 100,
        paymentMethod: PaymentMethod.maya,
      );
      expect(
        (await ReportsRepository(db).paymentHistory()).single['payment_method'],
        'MAYA',
      );
      final paymentEntry = (await transactions.recent(search: 'MAYA'))
          .singleWhere((entry) => entry.type == 'PAYMENT');
      expect(
        (await transactions.details(paymentEntry))['payment_method'],
        'MAYA',
      );
    },
  );
}
