import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/expenses/presentation/expenses_screen.dart';
import 'package:tindahan_ni_embi/features/gcash/presentation/gcash_screen.dart';
import 'package:tindahan_ni_embi/features/activity_logs/presentation/activity_logs_screen.dart';
import 'package:tindahan_ni_embi/features/inventory/presentation/inventory_screen.dart';
import 'package:tindahan_ni_embi/features/operations/presentation/daily_closing_screen.dart';
import 'package:tindahan_ni_embi/features/operations/presentation/restock_screen.dart';
import 'package:tindahan_ni_embi/features/reports/presentation/reports_screen.dart';
import 'package:tindahan_ni_embi/features/suppliers/presentation/supplier_contacts_screen.dart';
import 'package:tindahan_ni_embi/repositories/expense_repository.dart';
import 'package:tindahan_ni_embi/repositories/activity_log_repository.dart';
import 'package:tindahan_ni_embi/repositories/gcash_service_repository.dart';
import 'package:tindahan_ni_embi/repositories/inventory_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/repositories/category_repository.dart';
import 'package:tindahan_ni_embi/repositories/product_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_accounting_repository.dart';
import 'package:tindahan_ni_embi/repositories/reports_repository.dart';
import 'package:tindahan_ni_embi/repositories/supplier_contacts_repository.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';
import 'package:tindahan_ni_embi/models/payment_method.dart';
import 'package:tindahan_ni_embi/models/product.dart';

class _FreePlanSource extends AppPlanSource {
  @override
  AppPlan get plan => AppPlan.free;
  @override
  Future<AppPlan> load() async => AppPlan.free;
}

class _SwitchablePlanSource extends AppPlanSource {
  AppPlan current = AppPlan.free;
  @override
  AppPlan get plan => current;
  @override
  Future<AppPlan> load() async => current;
  void change(AppPlan value) {
    current = value;
    notifyListeners();
  }
}

class _WalletLayoutRepository extends PaymentAccountingRepository {
  _WalletLayoutRepository(super.db, PaymentMethod provider)
    : super(provider: provider);
  @override
  Future<GCashSummary> summary([DateTime? selectedDay]) async =>
      const GCashSummary(balance: 1052400, todayIn: 2400, todayOut: 0);
  @override
  Future<List<GCashLedgerEntry>> history({int limit = 100}) async => [];
}

class _WalletLayoutServices extends GCashServiceRepository {
  _WalletLayoutServices(super.db, PaymentMethod provider)
    : super(provider: provider);
  @override
  Future<int> totalFeeIncome() async => 0;
  @override
  Future<List<GCashServiceTransaction>> recent({int limit = 50}) async => [];
  @override
  Future<int> availableGCashBalance() async => 1000000;
}

void main() {
  sqfliteFfiInit();

  testWidgets(
    'store sections fit 280–390dp phones and their compact controls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(280, 640);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final db = (await tester.runAsync(() => app.database))!;
      final expenses = ExpenseRepository(db);
      final inventory = InventoryRepository(db);
      final operations = OperationsRepository(db);
      final access = FeatureAccessService(
        db,
        planController: AppPlanController(_FreePlanSource()),
      );
      final activityLogs = ActivityLogRepository(db);
      await tester.runAsync(
        () => activityLogs.add(
          eventType: 'SALES_CORRECTED',
          description: 'Cash sale correction recorded for an unusually long product description.',
          actorRole: 'OWNER',
          entityType: 'CASH_SALE',
          at: DateTime.now(),
        ),
      );

      final screens = <String, Widget>{
        'Activity Log': ActivityLogsScreen(repository: activityLogs),
        'Inventory': InventoryScreen(repository: inventory, access: access),
        'Restock': RestockScreen(
          operations: operations,
          inventory: inventory,
          openConsignment: (_, _) {},
        ),
        'Expenses': ExpensesScreen(repository: expenses, auth: AuthService(db)),
        'Daily Closing': DailyClosingScreen(repository: operations),
        'Reports': ReportsScreen(repository: ReportsRepository(db)),
        'Suppliers': SupplierContactsScreen(
          repository: SupplierContactsRepository(db),
        ),
      };
      for (final entry in screens.entries) {
        for (final width in [280.0, 320.0, 390.0]) {
          tester.view.physicalSize = Size(width, 640);
          await tester.pumpWidget(MaterialApp(home: entry.value));
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} at ${width}dp',
          );
        }
      }

      tester.view.physicalSize = const Size(280, 640);
      await tester.pumpWidget(
        MaterialApp(
          home: SupplierContactsScreen(
            repository: SupplierContactsRepository(db),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add Supplier'));
      await tester.pumpAndSettle();
      expect(find.text('Supplier name'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.pumpWidget(
        MaterialApp(
          home: ExpensesScreen(repository: expenses, auth: AuthService(db)),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect((await tester.runAsync(() => expenses.categories()))!, isNotEmpty);
      final expensesList = tester.widget<ListView>(find.byType(ListView).first);
      expect(
        (expensesList.padding as EdgeInsets).bottom,
        greaterThanOrEqualTo(96),
      );
      await tester.tap(find.text('Add Expense'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Paid via'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Inventory History opens on a 280dp phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryScreen(
          repository: InventoryRepository(db),
          access: FeatureAccessService(
            db,
            planController: AppPlanController(_FreePlanSource()),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Inventory History'));
    await tester.pumpAndSettle();
    expect(find.text('Stock Movement History'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Correct Stock controls fit on a 280dp phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    final category = (await tester.runAsync(
      () => SqliteCategoryRepository(db).create('Test Category'),
    ))!;
    await tester.runAsync(
      () => SqliteProductRepository(db).create(
        ProductDraft(
          categoryId: category.id,
          name: 'Test Product',
          photoPath: '/test-product.png',
          purchasePriceCentavos: 100,
          sellingPriceCentavos: 200,
          startingQuantity: 5,
          minimumStockLevel: 1,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryScreen(
          repository: InventoryRepository(db),
          access: FeatureAccessService(
            db,
            planController: AppPlanController(_FreePlanSource()),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    final actions = find.byTooltip('Inventory actions for Test Product');
    await tester.drag(find.byType(ListView).first, const Offset(0, -1600));
    await tester.pumpAndSettle();
    await tester.tap(actions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correct Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Stock correction'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<bool>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add stock').last);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('GCash and Maya Free/Pro dashboards fit compact widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    final source = _SwitchablePlanSource();
    final controller = AppPlanController(source);
    for (final provider in [PaymentMethod.gcash, PaymentMethod.maya]) {
      final wallet = provider == PaymentMethod.gcash ? 'GCash' : 'Maya';
      await tester.pumpWidget(
        MaterialApp(
          home: GCashScreen(
            repository: _WalletLayoutRepository(db, provider),
            services: _WalletLayoutServices(db, provider),
            auth: AuthService(db),
            access: FeatureAccessService(db, planController: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PRO FEATURE'), findsOneWidget);
      expect(tester.takeException(), isNull);
      source.change(AppPlan.pro);
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('$wallet Services'), findsWidgets);
      expect(find.text('PRO FEATURE'), findsNothing);
      for (final width in [280.0, 320.0, 390.0]) {
        tester.view.physicalSize = Size(width, 640);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$wallet Pro at ${width}dp',
        );
      }
      tester.view.physicalSize = const Size(280, 640);
      await tester.pumpAndSettle();
      final walletList = tester.widget<ListView>(find.byType(ListView).first);
      expect(
        (walletList.padding as EdgeInsets).bottom,
        greaterThanOrEqualTo(96),
      );
      await tester.scrollUntilVisible(
        find.text('Cash-In'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Cash-In'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash-In'));
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('$wallet Cash-In'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      source.change(AppPlan.free);
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
