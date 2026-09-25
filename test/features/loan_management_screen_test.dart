import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/loans/presentation/loan_management_screen.dart';
import 'package:tindahan_ni_embi/models/payment_method.dart';
import 'package:tindahan_ni_embi/repositories/loan_repository.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('open loan screen reacts to development plan changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('loan_plan_test_'),
    );
    if (directory == null) {
      throw StateError('Test directory could not be created.');
    }
    addTearDown(() => directory.delete(recursive: true));
    final controller = AppPlanController(
      DevelopmentPlanSource(
        enabled: true,
        preferenceFile: () async => File('${directory.path}/plan.txt'),
      ),
    );
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await tester.runAsync(() => app.database);
    if (db == null) throw StateError('Test database did not open.');
    await tester.pumpWidget(
      MaterialApp(
        home: LoanManagementScreen(
          repository: LoanRepository(db, actorRole: 'OWNER'),
          access: FeatureAccessService(db, planController: controller),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('PRO FEATURE'), findsOneWidget);

    await tester.runAsync(() => controller.setDevelopmentPlan(AppPlan.pro));
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add Lender'), findsOneWidget);

    await tester.runAsync(() => controller.setDevelopmentPlan(AppPlan.free));
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('PRO FEATURE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('adding a lender and loan keeps the dialog flow usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await tester.runAsync(() => app.database);
    if (db == null) throw StateError('Test database did not open.');
    await tester.pumpWidget(
      MaterialApp(
        home: LoanManagementScreen(
          repository: LoanRepository(db, actorRole: 'OWNER'),
          access: FeatureAccessService(
            db,
            planController: AppPlanController(OpenAccessPlanSource()),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add Lender'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Bombay');
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Add Loan').first);
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bombay'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount borrowed'),
      '50',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Total to repay'),
      '55000',
    );
    await tester.tap(find.text('Save Loan'));
    await tester.pumpAndSettle();
    expect(find.text('Check these loan amounts'), findsOneWidget);
    await tester.tap(find.text('Edit Amounts'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(() => LoanRepository(db).loans()))!, isEmpty);
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount borrowed'),
      '50,000',
    );
    await tester.tap(find.text('Save Loan'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final loans = await tester.runAsync(() => LoanRepository(db).loans());
    expect(loans, hasLength(1));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bombay'), findsOneWidget);
    expect(find.text('₱55,000.00'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(app.close);
  });

  testWidgets('loan overview and card use the same centavo amounts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await tester.runAsync(() => app.database);
    if (db == null) throw StateError('Test database did not open.');
    final repository = LoanRepository(db, actorRole: 'OWNER');
    await tester.runAsync(() async {
      final lender = await repository.createLender('Rusi');
      final loanId = await repository.create(
        lenderId: lender,
        borrowed: 5000000,
        agreed: 5500000,
        sourceKind: 'EXISTING',
        start: DateTime.now(),
        frequency: 'DAILY',
      );
      await repository.pay(
        loanId: loanId,
        amount: 50000,
        method: PaymentMethod.cash,
      );
    });
    final rows = await tester.runAsync(() => repository.loans());
    expect(rows!.single['borrowed_amount_centavos'], 5000000);
    expect(rows.single['agreed_repayment_centavos'], 5500000);
    expect(rows.single['paid_centavos'], 50000);

    await tester.pumpWidget(
      MaterialApp(
        home: LoanManagementScreen(
          repository: repository,
          access: FeatureAccessService(
            db,
            planController: AppPlanController(OpenAccessPlanSource()),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('₱50,000.00'), findsNWidgets(2));
    expect(find.text('₱55,000.00'), findsOneWidget);
    expect(find.text('₱500.00'), findsOneWidget);
    expect(find.text('₱54,500.00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner can correct a paid cash loan through Edit Loan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await tester.runAsync(() => app.database);
    if (db == null) throw StateError('Test database did not open.');
    final repository = LoanRepository(db, actorRole: 'OWNER');
    await tester.runAsync(() async {
      await AuthService(db).setPin(UserRole.owner, '1234');
      final lender = await repository.createLender('Bombay');
      final loanId = await repository.create(
        lenderId: lender,
        borrowed: 5000,
        agreed: 5500000,
        sourceKind: 'NEW',
        start: DateTime.now(),
        frequency: 'DAILY',
        receivedMethod: PaymentMethod.cash,
      );
      await repository.pay(
        loanId: loanId,
        amount: 50000,
        method: PaymentMethod.cash,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: LoanManagementScreen(
          repository: repository,
          access: FeatureAccessService(
            db,
            planController: AppPlanController(OpenAccessPlanSource()),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bombay'));
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Loan'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Correct amount borrowed'),
      '50000',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for correction'),
      'Missing zeroes',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Owner PIN'), '1234');
    await tester.tap(find.text('Save Correction'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Save Correction'), findsNothing);
    expect(
      (await tester.runAsync(() => repository.loans()))!
          .single['borrowed_amount_centavos'],
      5000000,
    );
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('₱50,000.00'), findsNWidgets(2));
    expect(find.text('₱54,500.00'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
