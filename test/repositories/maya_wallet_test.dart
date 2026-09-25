import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/models/payment_method.dart';
import 'package:tindahan_ni_embi/repositories/gcash_service_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_accounting_repository.dart';

void main() {
  sqfliteFfiInit();

  test(
    'Maya services, reversal, and daily cash stay separate from GCash',
    () async {
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final db = await app.database;
      addTearDown(app.close);
      final maya = PaymentAccountingRepository(
        db,
        actorRole: 'OWNER',
        provider: PaymentMethod.maya,
      );
      final gcash = PaymentAccountingRepository(db, actorRole: 'OWNER');
      await maya.addManual(
        type: 'OPENING_BALANCE',
        amountCentavos: 100000,
        reason: 'Opening',
        ownerPinAuthorized: true,
      );
      final services = GCashServiceRepository(db, provider: PaymentMethod.maya);
      final cashIn = await services.record(
        type: 'CASH_IN',
        principalCentavos: 10000,
        feeCentavos: 500,
      );
      final cashOut = await services.record(
        type: 'CASH_OUT',
        principalCentavos: 20000,
        feeCentavos: 1000,
        physicalCashAvailabilityAcknowledged: true,
      );
      expect(cashIn.gcashChangeCentavos, -10000);
      expect(cashOut.gcashChangeCentavos, 21000);
      expect((await maya.summary()).balance, 111000);
      expect((await gcash.summary()).balance, 0);
      var closing = await OperationsRepository(db).daily(DateTime.now());
      expect(closing.mayaEndingBalance, 111000);
      expect(closing.mayaServiceFeeIncome, 1500);
      expect(closing.cashDifference, -9500);
      await services.reverse(
        cashOut.id,
        reason: 'Cancelled',
        ownerPinAuthorized: true,
      );
      closing = await OperationsRepository(db).daily(DateTime.now());
      expect(closing.mayaEndingBalance, 90000);
      expect(closing.mayaServiceFeeIncome, 500);
      expect(closing.cashDifference, 10500);
      expect((await gcash.summary()).balance, 0);
    },
  );
}
