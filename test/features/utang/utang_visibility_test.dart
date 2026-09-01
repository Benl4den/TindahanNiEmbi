import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/utang/presentation/utang_customer_card.dart';
import 'package:tindahan_ni_embi/features/utang/presentation/utang_flow.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';

void main() {
  Customer customer(int balance) => Customer(
    id: 1,
    fullName: 'Erwin Cruz',
    isArchived: false,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    balanceCentavos: balance,
  );
  testWidgets('UTANGAN cards expose outstanding and zero balance states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              UtangCustomerCard(customer: customer(30000), onTap: () {}),
              UtangCustomerCard(
                customer: Customer(
                  id: 2,
                  fullName: 'Zero Customer',
                  isArchived: false,
                  createdAt: DateTime.utc(2026),
                  updatedAt: DateTime.utc(2026),
                ),
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('₱300.00'), findsOneWidget);
    expect(find.text('₱0.00'), findsOneWidget);
    expect(find.bySemanticsLabel('Outstanding UTANG'), findsOneWidget);
    expect(find.bySemanticsLabel('Zero UTANG'), findsOneWidget);
  });

  testWidgets(
    'UTANG details modal uses historical snapshots and closes in place',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => UtangDetailsDialog(
                    repository: _Customers(),
                    transactionId: 9,
                    previousCentavos: 0,
                    resultingCentavos: 30000,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('UTANG DETAILS'), findsOneWidget);
      expect(find.text('UTG-000009'), findsOneWidget);
      expect(find.text('Historical Coke'), findsOneWidget);
      expect(find.text('2 × ₱150.00'), findsOneWidget);
      expect(find.text('₱300.00'), findsWidgets);
      expect(find.textContaining('2 total pieces'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('UTANG DETAILS'), findsNothing);
    },
  );
}

class _Customers implements CustomerRepository {
  @override
  Future<Map<String, Object?>> utangDetails(int id) async => {
    'id': id,
    'reference': 'UTG-000009',
    'full_name': 'Erwin Cruz',
    'occurred_at': '2026-09-02T04:30:00Z',
    'total_centavos': 30000,
    'items': <Map<String, Object?>>[
      {
        'product_name_snapshot': 'Historical Coke',
        'unit_price_centavos': 15000,
        'quantity': 2,
        'line_total_centavos': 30000,
      },
    ],
  };
  @override
  Future<void> archive(int id) => throw UnimplementedError();
  @override
  Future<Customer> create(CustomerDraft draft) => throw UnimplementedError();
  @override
  Future<CustomerDetails> details(int id) => throw UnimplementedError();
  @override
  Future<List<Customer>> searchActive([String query = '']) =>
      throw UnimplementedError();
  @override
  Future<Customer> update(int id, CustomerDraft draft) =>
      throw UnimplementedError();
}
