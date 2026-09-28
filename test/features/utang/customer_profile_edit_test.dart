import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/customers/presentation/customer_form_screen.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();
  testWidgets('Edit Customer modal saves contact without altering balance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await tester.runAsync(() => app.database);
    if (db == null) throw StateError('Database did not open.');
    final repository = SqliteCustomerRepository(db);
    final customer = await tester.runAsync(
      () => repository.create(
        const CustomerDraft(fullName: 'Paksiw', mobileNumber: '0912 345 6789'),
      ),
    );
    if (customer == null) throw StateError('Customer did not save.');
    await tester.runAsync(
      () => UtangRepository(db)
          .addExistingBalance(customerId: customer.id, amountCentavos: 82500),
    );
    final before = await tester.runAsync(() => repository.details(customer.id));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => CustomerFormScreen(
                  repository: repository,
                  customer: customer,
                  compact: true,
                ),
              ),
              child: const Text('Edit Profile'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Customer'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Full Name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Nickname'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Address'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone Number'),
      '0999 111 2222',
    );
    await tester.tap(find.text('Save Changes'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final after = await tester.runAsync(() => repository.details(customer.id));
    expect(after!.customer.mobileNumber, '0999 111 2222');
    expect(after.customer.balanceCentavos, before!.customer.balanceCentavos);
    expect(
      after.ledger.map((entry) => entry.id),
      before.ledger.map((entry) => entry.id),
    );
  });
}
