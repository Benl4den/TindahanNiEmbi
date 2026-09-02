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
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
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
