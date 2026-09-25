import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/services/app_refresh_controller.dart';
import 'package:tindahan_ni_embi/features/operations/presentation/daily_closing_screen.dart';
import 'package:tindahan_ni_embi/features/operations/presentation/daily_closing_overview.dart';
import 'package:tindahan_ni_embi/features/reports/presentation/reports_screen.dart';
import 'package:tindahan_ni_embi/repositories/reports_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_accounting_repository.dart';
import 'package:tindahan_ni_embi/repositories/gcash_service_repository.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';
import 'package:tindahan_ni_embi/models/payment_method.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

class _MutablePlanSource extends AppPlanSource {
  AppPlan _plan = AppPlan.free;

  @override
  AppPlan get plan => _plan;

  @override
  Future<AppPlan> load() async => _plan;

  void update(AppPlan plan) {
    _plan = plan;
    notifyListeners();
  }
}

void main() {
  sqfliteFfiInit();
  testWidgets('Free locks service analytics but keeps full Daily Closing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final source = _MutablePlanSource();
    final controller = AppPlanController(source);
    addTearDown(controller.dispose);
    final db = await tester.runAsync(() async {
      final database = await app.database;
      source.update(AppPlan.pro);
      for (final method in [PaymentMethod.gcash, PaymentMethod.maya]) {
        await PaymentAccountingRepository(
          database,
          provider: method,
          actorRole: 'OWNER',
        ).addManual(
          type: 'OPENING_BALANCE',
          amountCentavos: method == PaymentMethod.gcash ? 123400 : 567800,
          reason: 'Free visibility test',
          ownerPinAuthorized: true,
        );
        await GCashServiceRepository(
          database,
          provider: method,
        ).record(type: 'CASH_IN', principalCentavos: 10000, feeCentavos: 500);
      }
      return database;
    });
    final access = FeatureAccessService(db!, planController: controller);
    expect(access.allowsCurrent(ProFeature.gcashServices), isTrue);
    expect(access.allowsCurrent(ProFeature.mayaServices), isTrue);
    final before = await tester.runAsync(
      () => OperationsRepository(db).daily(DateTime.now()),
    );
    source.update(AppPlan.free);
    expect(access.allowsCurrent(ProFeature.gcashServices), isFalse);
    expect(access.allowsCurrent(ProFeature.mayaServices), isFalse);
    final after = await tester.runAsync(
      () => OperationsRepository(db).daily(DateTime.now()),
    );
    expect(after!.toJson(), before!.toJson());
    expect(after.cashReceived, 21000);
    expect(after.cashDifference, 21000);
    expect(after.serviceFeeIncome + after.mayaServiceFeeIncome, 1000);
    expect(after.totalEarnings, 1000);
    expect(after.gcashEndingBalance, 113400);
    expect(after.mayaEndingBalance, 557800);
    source.update(AppPlan.pro);
    final restored = await tester.runAsync(
      () => OperationsRepository(db).daily(DateTime.now()),
    );
    expect(restored!.toJson(), before.toJson());
    source.update(AppPlan.free);
    final serviceRows = await tester.runAsync(
      () async => [
        await db.query('gcash_service_transactions'),
        await db.query('maya_service_transactions'),
      ],
    );
    expect(serviceRows![0], hasLength(1));
    expect(serviceRows[1], hasLength(1));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DashboardScreen(
            database: db,
            navigate: (_) {},
            walletServicesAllowed: false,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.text('Current GCash Balance'), findsNothing);
    expect(find.text('Current Maya Balance'), findsNothing);
    expect(find.text('₱1,234.00'), findsNothing);
    expect(find.text('₱5,678.00'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DailyClosingOverview(
              summary: after,
              walletServicesAllowed: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Payment Summary'), findsOneWidget);
    expect(find.text('GCash Wallet'), findsOneWidget);
    expect(find.text('Maya Wallet'), findsOneWidget);
    expect(find.text('E-Wallet Fees Earned'), findsOneWidget);
    expect(find.text('E-Wallet Services — Cash Received'), findsOneWidget);
    expect(find.text('₱210.00'), findsWidgets);
    expect(find.text('₱10.00'), findsWidgets);
    expect(find.textContaining('Partial Free view'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReportsScreen(
            repository: ReportsRepository(db),
            walletServicesAllowed: false,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.tap(find.text('Sales').last);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    expect(find.text('GCash Services • All Time'), findsNothing);
    expect(find.text('Maya Services • All Time'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'dashboard preserves product names when labeling brand activity',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final db = await tester.runAsync(() async {
        final database = await app.database;
        final stamp = DateTime.now().toUtc().toIso8601String();
        await database.insert('activity_logs', {
          'event_type': 'SPECIAL_INVENTORY_ASSIGNED',
          'description': 'SELECTA Flour assigned to SELECTA',
          'created_at': stamp,
        });
        await database.insert('activity_logs', {
          'event_type': 'INVENTORY_STOCK_IN',
          'description': 'Stock In — SELECTA Flour +2',
          'created_at': stamp,
        });
        return database;
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: DashboardScreen(database: db!, navigate: (_) {}),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Recent Activity'), 400);
      expect(
        find.text('SELECTA Flour assigned to Selecta Products'),
        findsOneWidget,
      );
      expect(find.text('Stock In — SELECTA Flour +2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dashboard supports periods, quick actions and both tablet orientations',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final db = await tester.runAsync(() => app.database);
      addTearDown(app.close);
      int? target;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: DashboardScreen(
              database: db!,
              navigate: (value) => target = value,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('Total Sales • Today'), findsOneWidget);
      expect(find.textContaining('Updated at '), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('dashboard-period-date')))
            .data,
        isNot(contains(' – ')),
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final database = db!;
        final stamp = DateTime.now().toUtc().toIso8601String();
        final mayaSaleId = await database.insert('cash_sales', {
          'reference': 'DASHBOARD-MAYA',
          'total_centavos': 2000,
          'status': 'POSTED',
          'occurred_at': stamp,
          'created_at': stamp,
        });
        await database.insert('sale_payments', {
          'cash_sale_id': mayaSaleId,
          'payment_method': 'GCASH',
          'payment_method_display': 'MAYA',
          'amount_centavos': 2000,
          'created_at': stamp,
        });
        final customer = await SqliteCustomerRepository(database)
            .create(const CustomerDraft(fullName: 'Opening Balance'));
        await UtangRepository(database)
            .addExistingBalance(customerId: customer.id, amountCentavos: 1000);
        await database.insert('cash_sales', {
          'reference': 'DASHBOARD-REFRESH',
          'total_centavos': 12345,
          'status': 'POSTED',
          'occurred_at': stamp,
          'created_at': stamp,
        });
        AppRefreshController.instance.dataChanged();
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Total Sales • Today'), findsNothing);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.text('₱143.45'), findsOneWidget);
      expect(find.textContaining('Maya ₱20.00'), findsOneWidget);
      expect(find.text('2 transactions today'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: DashboardScreen(
              database: db!,
              navigate: (value) => target = value,
              refreshRevision: 1,
            ),
          ),
        );
        expect(find.text('Updating…'), findsOneWidget);
        expect(find.textContaining('Updated at '), findsNothing);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Updated at '), findsOneWidget);
      for (final label in ['This Week', 'This Month']) {
        await tester.runAsync(() async {
          await tester.tap(find.text(label));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        expect(find.text('Total Sales • $label'), findsOneWidget);
        expect(
          find.text('2 transactions ${label.toLowerCase()}'),
          findsOneWidget,
        );
      }
      tester.view.physicalSize = const Size(800, 1280);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: DashboardScreen(
            database: db!,
            refreshRevision: 1,
            navigate: (value) => target = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Start Sale'), 500);
      await tester.tap(find.text('Start Sale'));
      expect(target, 0);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(600, 800);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        tester
            .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
            .onSelectionChanged!({0});
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('dashboard-period-date')))
            .data,
        isNot(contains(' – ')),
      );
      expect(tester.takeException(), isNull);
      for (final size in [const Size(800, 1280), const Size(1280, 800)]) {
        tester.view.physicalSize = size;
        await tester.runAsync(() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark,
              home: DailyClosingScreen(repository: OperationsRepository(db)),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await tester.scrollUntilVisible(
            find.text('DAILY CLOSING HISTORY'),
            400,
          );
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        expect(
          find.text('No completed product sales for this day.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
