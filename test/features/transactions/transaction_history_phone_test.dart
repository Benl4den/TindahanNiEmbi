import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/transactions/transaction_history_screen.dart';
import 'package:tindahan_ni_embi/repositories/transaction_history_repository.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('transaction detail product rows fit a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await tester.runAsync(() => app.database);
    if (db == null) throw StateError('Test database did not open.');
    final repository = _HistoryRepository(db);
    final controller = AppPlanController(OpenAccessPlanSource());

    await tester.pumpWidget(
      MaterialApp(
        home: TransactionHistoryScreen(
          repository: repository,
          access: FeatureAccessService(db, planController: controller),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open full details'));
    await tester.tap(find.text('Open full details'));
    await tester.pumpAndSettle();
    expect(
      find.text('A very long product name for narrow phone layouts'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _HistoryRepository extends TransactionHistoryRepository {
  _HistoryRepository(super.db);

  static final _entry = TransactionHistoryEntry(
    id: 1,
    type: 'CASH',
    title: 'Sale • Cash',
    amountCentavos: 123456789,
    occurredAt: DateTime(2026, 10, 6, 12),
    status: 'POSTED',
    actor: 'Owner',
  );

  @override
  Future<List<TransactionHistoryEntry>> recent({
    String type = 'ALL',
    int limit = 500,
    String search = '',
    DateTime? day,
    bool includeWalletServices = true,
  }) async => [_entry];

  @override
  Future<Map<String, Object?>> details(TransactionHistoryEntry entry) async => {
    'items': [
      {
        'product_name_snapshot':
            'A very long product name for narrow phone layouts',
        'line_total_centavos': 123456789,
        'selling_quantity_value': 1000000,
        'selling_quantity_scale': 1000000,
        'selling_option_name_snapshot': 'piece',
        'selling_unit_price_centavos': 123456789,
      },
    ],
  };
}
