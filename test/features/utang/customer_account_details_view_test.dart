import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/features/utang/presentation/customer_account_details_view.dart';
import 'package:tindahan_ni_embi/models/customer.dart';

void main() {
  CustomerDetails details({bool contact = true}) => CustomerDetails(
    customer: Customer(
      id: 1,
      fullName: 'Paksiw Santos',
      mobileNumber: contact ? '0912 345 6789' : null,
      address: 'Brgy. San Isidro, Tanza, Cavite',
      isArchived: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      balanceCentavos: 82500,
    ),
    ledger: [
      CustomerLedgerEntry(
        id: 2,
        type: 'PAYMENT',
        amountCentavos: -20000,
        occurredAt: DateTime(2026, 9, 30, 4),
        paymentId: 7,
        paymentMethod: 'GCASH',
        paymentReference: 'GC-123',
      ),
      CustomerLedgerEntry(
        id: 1,
        type: 'UTANG',
        amountCentavos: 102500,
        occurredAt: DateTime(2026, 9, 29, 1, 50),
        utangTransactionId: 14,
        itemCount: 2,
      ),
    ],
  );

  testWidgets(
    'landscape dark view shows profile, actions and ledger balances',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var edited = false, paid = false, newSale = false, existing = false;
      CustomerLedgerEntry? viewed;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CustomerAccountDetailsView(
              details: details(),
              currentBalanceCentavos: 82500,
              outstandingCount: 1,
              filter: 'All',
              onFilterChanged: (_) {},
              onEditProfile: () => edited = true,
              onRecordPayment: () => paid = true,
              onNewUtang: () => newSale = true,
              onAddExisting: () => existing = true,
              onViewEntry: (entry) => viewed = entry,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paksiw Santos'), findsOneWidget);
      expect(find.text('0912 345 6789'), findsOneWidget);
      expect(find.text('Brgy. San Isidro, Tanza, Cavite'), findsOneWidget);
      expect(find.text('₱825.00'), findsWidgets);
      expect(find.text('1 transaction'), findsWidgets);
      expect(find.text('UTANG Sale'), findsOneWidget);
      expect(find.text('Payment Received'), findsOneWidget);
      expect(find.text('+₱1,025.00'), findsOneWidget);
      expect(find.text('-₱200.00'), findsOneWidget);
      expect(find.text('₱1,025.00'), findsOneWidget);
      expect(find.textContaining('GCash'), findsWidgets);
      expect(find.textContaining('GC-123'), findsOneWidget);
      expect(find.text('Balance after'), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Edit Profile'));
      await tester.tap(find.text('Record Payment'));
      await tester.tap(find.text('New UTANG Sale'));
      await tester.tap(find.text('Add Existing UTANG Amount'));
      expect([edited, paid, newSale, existing], everyElement(isTrue));
      await tester.ensureVisible(find.text('View Details').first);
      await tester.tap(find.text('View Details').first);
      expect(viewed, isNotNull);
      await tester.ensureVisible(find.text('Tue, Sep 29'));
      await tester.tap(find.text('Tue, Sep 29'));
      await tester.pumpAndSettle();
      expect(find.text('UTANG Sale'), findsNothing);
      await tester.tap(find.text('Tue, Sep 29'));
      await tester.pumpAndSettle();
      expect(find.text('UTANG Sale'), findsOneWidget);
    },
  );

  testWidgets('portrait light view wraps and shows missing-contact fallback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var selected = 'All';
    Widget screen() => MaterialApp(
      theme: AppTheme.light,
      home: StatefulBuilder(
        builder: (context, set) => Scaffold(
          body: CustomerAccountDetailsView(
            details: details(contact: false),
            currentBalanceCentavos: 82500,
            outstandingCount: 1,
            filter: selected,
            onFilterChanged: (value) => set(() => selected = value),
            onEditProfile: () {},
            onRecordPayment: () {},
            onNewUtang: () {},
            onAddExisting: () {},
            onViewEntry: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('No contact number'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Payments').first);
    await tester.tap(find.text('Payments').first);
    await tester.pumpAndSettle();
    expect(selected, 'Payments');
    expect(find.text('UTANG Sale'), findsNothing);
    expect(find.text('Payment Received'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Products on UTANG'));
    await tester.tap(find.text('Products on UTANG'));
    await tester.pumpAndSettle();
    expect(find.text('No products on UTANG yet.'), findsOneWidget);
  });
}
