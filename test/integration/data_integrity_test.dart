import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/models/utang_draft.dart';
import 'package:tindahan_ni_embi/repositories/cash_sale_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();
  test('realistic transactions persist and all ledgers reconcile', () async {
    final dir = await Directory.systemTemp.createTemp('integrity_'),
        path = '${dir.path}/store.db';
    var app = AppDatabase(factory: databaseFactoryFfi, databasePath: path),
        db = await app.database;
    final cat = (await SqliteCategoryRepository(db).create('Pagkaon')).id,
        products = SqliteProductRepository(db);
    final a = await products.create(
          ProductDraft(
            categoryId: cat,
            name: 'A',
            photoPath: '/a',
            purchasePriceCentavos: 400,
            sellingPriceCentavos: 700,
            startingQuantity: 20,
            minimumStockLevel: 3,
          ),
        ),
        b = await products.create(
          ProductDraft(
            categoryId: cat,
            name: 'B',
            photoPath: '/b',
            purchasePriceCentavos: 500,
            sellingPriceCentavos: 900,
            startingQuantity: 10,
            minimumStockLevel: 2,
          ),
        );
    await InventoryRepository(db).stockIn(productId: a.id, quantity: 5);
    final customer = await SqliteCustomerRepository(db)
        .create(const CustomerDraft(fullName: 'Juan'));
    await UtangRepository(db).save(
      UtangDraft(
        customerId: customer.id,
        items: [
          UtangItemDraft(productId: a.id, quantity: 3),
          UtangItemDraft(productId: b.id, quantity: 2),
        ],
      ),
    );
    await PaymentRepository(db)
        .record(customerId: customer.id, amountCentavos: 1000);
    await CashSaleRepository(db).save([
      UtangItemDraft(productId: a.id, quantity: 4),
      UtangItemDraft(productId: b.id, quantity: 1),
    ]);
    final stockMismatch = await db.rawQuery(
      '''SELECT p.id FROM products p WHERE p.current_quantity != COALESCE((SELECT SUM(m.quantity_change) FROM inventory_movements m WHERE m.product_id=p.id),0)''',
    );
    expect(stockMismatch, isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(
      await db.rawQuery(
        'SELECT id FROM utang_transactions u WHERE total_centavos != (SELECT SUM(line_total_centavos) FROM utang_transaction_items i WHERE i.utang_transaction_id=u.id)',
      ),
      isEmpty,
    );
    expect(
      await db.rawQuery(
        'SELECT id FROM cash_sales s WHERE total_centavos != (SELECT SUM(line_total_centavos) FROM cash_sale_items i WHERE i.cash_sale_id=s.id)',
      ),
      isEmpty,
    );
    expect(
      (await SqliteCustomerRepository(db).details(customer.id))
          .customer
          .balanceCentavos,
      2900,
    );
    final events = (await db.query('activity_logs'))
        .map((x) => x['event_type']);
    expect(
      events,
      containsAll([
        'INVENTORY_STOCK_IN',
        'UTANG_CREATED',
        'UTANG_PAYMENT',
        'SALES_CASH_SALE',
      ]),
    );
    await app.close();
    app = AppDatabase(factory: databaseFactoryFfi, databasePath: path);
    db = await app.database;
    expect((await db.query('products')).length, 2);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await app.close();
    await dir.delete(recursive: true);
  });
}
