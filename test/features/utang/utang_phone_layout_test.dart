import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/utang/presentation/utang_flow.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('UTANG summary fits narrow Android widths without split words', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewInsets);

    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: UtangCustomerScreen(
          customers: SqliteCustomerRepository(db),
          products: SqliteProductRepository(db),
          utang: UtangRepository(db),
          payments: PaymentRepository(db),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    for (final size in const [
      Size(280, 600),
      Size(320, 700),
      Size(390, 844),
      Size(800, 600),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.text('Outstanding UTANG'), findsOneWidget);
      expect(find.text('Customers with balance'), findsOneWidget);
      expect(find.text('Paid in last 7 days'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.enterText(find.byType(TextField).first, 'nobody');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No matching customers'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(320, 600);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed UTANG summary does not show a misleading zero', (
    tester,
  ) async {
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    await tester.pumpWidget(
      MaterialApp(
        home: UtangCustomerScreen(
          customers: _FailingCustomers(db),
          products: SqliteProductRepository(db),
          utang: UtangRepository(db),
          payments: PaymentRepository(db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load UTANG summary.'), findsOneWidget);
    expect(find.text('₱0.00'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FailingCustomers extends SqliteCustomerRepository {
  const _FailingCustomers(super.db);

  @override
  Future<List<Customer>> searchActive([String query = '']) async =>
      throw StateError('Simulated database error');
}
