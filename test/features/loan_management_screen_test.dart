import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/loans/presentation/loan_management_screen.dart';
import 'package:tindahan_ni_embi/repositories/loan_repository.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';

void main() {
  sqfliteFfiInit();

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
          access: FeatureAccessService(db),
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
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '100');
    await tester.enterText(fields.at(1), '120');
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
