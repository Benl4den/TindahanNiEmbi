import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tindahan_ni_embi/features/gcash/presentation/gcash_screen.dart';
import 'package:tindahan_ni_embi/models/payment_method.dart';
import 'package:tindahan_ni_embi/repositories/gcash_service_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_accounting_repository.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';

class StubDb extends Fake implements Database {}

class Wallet extends PaymentAccountingRepository {
  Wallet() : super(StubDb());
  List<GCashLedgerEntry> rows = [];
  @override
  Future<GCashSummary> summary([DateTime? selectedDay]) async =>
      const GCashSummary(balance: 200000, todayIn: 0, todayOut: 0);
  @override
  Future<List<GCashLedgerEntry>> history({int limit = 100}) async => rows;
  @override
  Future<bool> hasOpeningBalance() async => true;
  @override
  Future<int> addManual({
    required String type,
    required int amountCentavos,
    required String reason,
    String? gcashReference,
    bool ownerPinAuthorized = false,
  }) async => 1;
}

class Auth extends AuthService {
  Auth() : super(StubDb());
  @override
  Future<UserRole?> verify(String pin, {int? staffId}) async => UserRole.owner;
}

class Services extends GCashServiceRepository {
  Services() : super(StubDb());
  int calls = 0;
  List<GCashServiceTransaction> rows = [];
  final result = Completer<GCashServiceTransaction>();
  @override
  Future<int> totalFeeIncome() async => 0;
  @override
  Future<int> availableGCashBalance() async => 200000;
  @override
  Future<List<GCashServiceTransaction>> recent({int limit = 50}) async => rows;
  @override
  Future<GCashServiceTransaction> reverse(
    int id, {
    required String reason,
    required bool ownerPinAuthorized,
  }) async => rows.single;
  @override
  Future<GCashServiceTransaction> record({
    required String type,
    required int principalCentavos,
    required int feeCentavos,
    String feeOption = 'ADDED',
    String? gcashReference,
    String? notes,
    bool physicalCashAvailabilityAcknowledged = false,
    String? requestId,
  }) {
    calls++;
    return result.future;
  }
}

class DistinctWallet extends PaymentAccountingRepository {
  DistinctWallet(PaymentMethod provider, this.balance)
    : super(StubDb(), provider: provider);
  final int balance;
  @override
  Future<GCashSummary> summary([DateTime? selectedDay]) async =>
      GCashSummary(balance: balance, todayIn: 0, todayOut: 0);
  @override
  Future<List<GCashLedgerEntry>> history({int limit = 100}) async => [];
}

class DistinctServices extends GCashServiceRepository {
  DistinctServices(PaymentMethod provider)
    : super(StubDb(), provider: provider);
  @override
  Future<int> totalFeeIncome() async => 0;
  @override
  Future<List<GCashServiceTransaction>> recent({int limit = 50}) async => [];
}

void main() {
  testWidgets('switching from GCash to Maya reloads the independent balance', (
    tester,
  ) async {
    Future<void> show(PaymentMethod provider, int balance) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GCashScreen(
            repository: DistinctWallet(provider, balance),
            services: DistinctServices(provider),
            auth: Auth(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(PaymentMethod.gcash, 123400);
    expect(find.text('₱1,234.00'), findsOneWidget);
    await show(PaymentMethod.maya, 567800);
    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('₱5,678.00'), findsOneWidget);
    expect(find.text('₱1,234.00'), findsNothing);
    await show(PaymentMethod.gcash, 123400);
    expect(find.text('₱1,234.00'), findsOneWidget);
  });

  final receipt = GCashServiceTransaction(
    id: 1,
    reference: 'GCS-test',
    type: 'CASH_IN',
    status: 'POSTED',
    principalCentavos: 10000,
    feeCentavos: 0,
    customerTotalCentavos: 10000,
    physicalCashChangeCentavos: 10000,
    gcashChangeCentavos: -10000,
    createdAt: DateTime.now(),
  );
  for (final label in ['Cash-In', 'Cash-Out']) {
    testWidgets('$label success closes the review without lifecycle errors', (
      tester,
    ) async {
      final services = Services();
      await tester.pumpWidget(
        MaterialApp(
          home: GCashScreen(
            repository: Wallet(),
            services: services,
            auth: Auth(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, label));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '100');
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      services.result.complete(receipt);
      await tester.pumpAndSettle();
      expect(find.text('Review GCash Service'), findsNothing);
      expect(services.calls, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'service reversal modal scrolls above keyboard and saves safely',
    (tester) async {
      final services = Services()..rows = [receipt];
      final wallet = Wallet()
        ..rows = [
          GCashLedgerEntry(
            id: 1,
            reference: 'internal',
            type: 'CASH_IN_SERVICE',
            amountChangeCentavos: receipt.gcashChangeCentavos,
            occurredAt: receipt.createdAt,
            gcashServiceTransactionId: receipt.id,
          ),
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: GCashScreen(
            repository: wallet,
            services: services,
            auth: Auth(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final date = receipt.createdAt.toLocal();
      final dayTile = find.byKey(
        PageStorageKey(
          'gcash-wallet-${DateTime(date.year, date.month, date.day)}',
        ),
      );
      await tester.scrollUntilVisible(
        dayTile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(dayTile);
      await tester.pumpAndSettle();
      expect(
        find.text('1 transaction • Tap to expand or collapse'),
        findsOneWidget,
      );
      final serviceTile = find.widgetWithText(ExpansionTile, 'Cash-In').last;
      await tester.ensureVisible(serviceTile);
      await tester.tap(serviceTile);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel service record'));
      await tester.tap(find.text('Cancel service record'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Mistake');
      await tester.enterText(find.byType(TextField).last, '1234');
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Cancellation'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel GCash Service Record'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'service confirm blocks double taps and shows failure on review',
    (tester) async {
      final services = Services();
      await tester.pumpWidget(
        MaterialApp(
          home: GCashScreen(
            repository: Wallet(),
            services: services,
            auth: Auth(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cash-In'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '1,000');
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Review GCash Service'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      expect(services.calls, 1);
      services.result.completeError(
        const GCashServiceException('Test save error'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test save error'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('adjustment opens with keyboard inset and closes safely', (
    tester,
  ) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: GCashScreen(
          repository: Wallet(),
          services: Services(),
          auth: Auth(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Adjustment'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
