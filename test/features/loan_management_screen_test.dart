import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/loans/presentation/loan_management_screen.dart';
import 'package:tindahan_ni_embi/repositories/loan_repository.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';

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
      '100',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Total to repay'),
      '120',
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
    expect(find.text('₱120.00'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(app.close);
  });
}
