import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/core/formatters/number_format.dart';
import 'package:tindahan_ni_embi/repositories/gcash_service_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_accounting_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/services/data_integrity_service.dart';

void main() {
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late GCashServiceRepository services;
  late PaymentAccountingRepository wallet;
  setUp(() async {
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    db = await app.database;
    services = GCashServiceRepository(db);
    wallet = PaymentAccountingRepository(db, actorRole: 'OWNER');
    await wallet.addManual(
      type: 'OPENING_BALANCE',
      amountCentavos: 200000,
      reason: 'Test',
      ownerPinAuthorized: true,
    );
  });
  tearDown(() => app.close());

  test('strict exact money parsing rejects malformed/non-finite inputs', () {
    expect(parseMoneyCentavos('1,234.56'), 123456);
    expect(parseMoneyCentavos('0'), 0);
    expect(parseMoneyCentavos('80.8'), 8080);
    for (final value in [
      'NaN',
      'Infinity',
      '1e8',
      '1,23',
      '1.234',
      '-2',
      '',
      '99999999999999999999',
    ]) {
      expect(parseMoneyCentavos(value), isNull, reason: value);
    }
  });

  test(
    'retry/concurrent request posts one service, zero fee allowed',
    () async {
      Future<GCashServiceTransaction> post() => services.record(
        type: 'CASH_IN',
        principalCentavos: 10000,
        feeCentavos: 0,
        requestId: 'same-request',
      );
      final rows = await Future.wait([post(), post()]);
      expect(rows[0].id, rows[1].id);
      expect((await wallet.summary()).balance, 190000);
      expect(await services.recent(), hasLength(1));
      await expectLater(
        services.record(
          type: 'CASH_IN',
          principalCentavos: 20000,
          feeCentavos: 0,
          requestId: 'same-request',
        ),
        throwsA(isA<GCashServiceException>()),
      );
      expect((await DataIntegrityService(db).check()).healthy, isTrue);
    },
  );

  test('opening balance and reversal cannot be repeated', () async {
    expect(await wallet.hasOpeningBalance(), isTrue);
    await expectLater(
      wallet.addManual(
        type: 'OPENING_BALANCE',
        amountCentavos: 100,
        reason: 'Again',
        ownerPinAuthorized: true,
      ),
      throwsA(isA<PaymentAccountingException>()),
    );
    final sale = await services.record(
      type: 'CASH_OUT',
      principalCentavos: 10000,
      feeCentavos: 0,
      physicalCashAvailabilityAcknowledged: true,
    );
    await services.reverse(sale.id, reason: 'Test', ownerPinAuthorized: true);
    await expectLater(
      services.reverse(sale.id, reason: 'Again', ownerPinAuthorized: true),
      throwsA(isA<GCashServiceException>()),
    );
    expect(
      (await services.recent()).firstWhere((x) => x.id == sale.id).status,
      'REVERSED',
    );
    expect((await wallet.summary()).balance, 200000);
    expect((await DataIntegrityService(db).check()).healthy, isTrue);
  });

  test('integrity check detects a wrongly signed service ledger', () async {
    final date = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('gcash_service_transactions', {
      'reference': 'bad-fixture',
      'service_type': 'CASH_IN',
      'status': 'POSTED',
      'principal_centavos': 10000,
      'fee_centavos': 500,
      'customer_total_centavos': 10500,
      'physical_cash_change_centavos': 10500,
      'gcash_change_centavos': -10000,
      'created_at': date,
    });
    await PaymentAccountingRepository.postGCashService(
      db,
      serviceId: id,
      serviceType: 'CASH_IN',
      amountChangeCentavos: 10000,
      occurredAt: date,
    );
    expect(
      (await DataIntegrityService(
        db,
      ).check()).problems.any((p) => p.contains('GCash service accounting')),
      isTrue,
    );
  });

  test(
    'cross-day reversal leaves original day unchanged and offsets today',
    () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final occurred = yesterday.toUtc().toIso8601String();
      final id = await db.insert('gcash_service_transactions', {
        'reference': 'historical-fixture',
        'service_type': 'CASH_IN',
        'status': 'POSTED',
        'principal_centavos': 10000,
        'fee_centavos': 500,
        'customer_total_centavos': 10500,
        'physical_cash_change_centavos': 10500,
        'gcash_change_centavos': -10000,
        'created_at': occurred,
      });
      await PaymentAccountingRepository.postGCashService(
        db,
        serviceId: id,
        serviceType: 'CASH_IN',
        amountChangeCentavos: -10000,
        occurredAt: occurred,
      );
      final before = await db.query(
        'gcash_service_transactions',
        where: 'id=?',
        whereArgs: [id],
      );
      await services.reverse(
        id,
        reason: 'Reverse today',
        ownerPinAuthorized: true,
      );
      expect((await services.summary(yesterday)).totalFeeIncome, 500);
      expect((await services.summary(DateTime.now())).totalFeeIncome, -500);
      expect(
        (await OperationsRepository(db).daily(yesterday)).serviceFeeIncome,
        500,
      );
      expect(
        (await OperationsRepository(db).daily(DateTime.now())).serviceFeeIncome,
        -500,
      );
      expect(await services.totalFeeIncome(), 0);
      expect(
        await db.query(
          'gcash_service_transactions',
          where: 'id=?',
          whereArgs: [id],
        ),
        before,
      );
    },
  );
}
