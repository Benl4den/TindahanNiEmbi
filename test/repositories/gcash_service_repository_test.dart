import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/repositories/gcash_service_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_accounting_repository.dart';

void main() {
  sqfliteFfiInit();

  test(
    'Cash-In and Cash-Out post only their correct GCash movements',
    () async {
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final db = await app.database;
      addTearDown(app.close);
      final wallet = PaymentAccountingRepository(db, actorRole: 'OWNER');
      await wallet.addManual(
        type: 'OPENING_BALANCE',
        amountCentavos: 200000,
        reason: 'Start',
        ownerPinAuthorized: true,
      );
      final services = GCashServiceRepository(db);
      final cashIn = await services.record(
        type: 'CASH_IN',
        principalCentavos: 100000,
        feeCentavos: 1500,
      );
      final cashOut = await services.record(
        type: 'CASH_OUT',
        principalCentavos: 50000,
        feeCentavos: 1000,
        physicalCashAvailabilityAcknowledged: true,
      );
      expect(cashIn.gcashChangeCentavos, -100000);
      expect(cashIn.physicalCashChangeCentavos, 101500);
      expect(cashOut.gcashChangeCentavos, 51000);
      expect(cashOut.physicalCashChangeCentavos, -50000);
      expect((await wallet.summary()).balance, 151000);
      final daily = await services.summary(DateTime.now());
      expect(daily.totalFeeIncome, 2500);
      await services.reverse(
        cashIn.id,
        reason: 'Mistake',
        ownerPinAuthorized: true,
      );
      expect((await wallet.summary()).balance, 251000);
      expect((await services.summary(DateTime.now())).totalFeeIncome, 1000);
    },
  );
}
