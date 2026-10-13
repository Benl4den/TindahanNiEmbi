import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/cash_sales/presentation/cash_sale_screen.dart';
import 'package:tindahan_ni_embi/features/cash_sales/presentation/cash_services_shortcut.dart';
import 'package:tindahan_ni_embi/features/gcash/presentation/gcash_screen.dart';
import 'package:tindahan_ni_embi/models/payment_method.dart';
import 'package:tindahan_ni_embi/models/product.dart';
import 'package:tindahan_ni_embi/repositories/gcash_service_repository.dart';
import 'package:tindahan_ni_embi/repositories/payment_accounting_repository.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';
import 'package:tindahan_ni_embi/services/feature_access_service.dart';

class _PlanSource extends AppPlanSource {
  _PlanSource(this.current);
  AppPlan current;
  @override
  AppPlan get plan => current;
  @override
  Future<AppPlan> load() async => current;
  void change(AppPlan value) {
    current = value;
    notifyListeners();
  }
}

Product _coffee() {
  final now = DateTime.utc(2026);
  return Product(
    id: 1,
    categoryId: 1,
    name: 'Coffee',
    photoPath: '/missing',
    purchasePriceCentavos: 1000,
    sellingPriceCentavos: 1500,
    currentQuantity: 10,
    minimumStockLevel: 1,
    isArchived: false,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  sqfliteFfiInit();

  testWidgets('Pro shortcut reads both balances and preserves an active cart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    final gcash = PaymentAccountingRepository(db, actorRole: 'OWNER');
    final maya = PaymentAccountingRepository(
      db,
      actorRole: 'OWNER',
      provider: PaymentMethod.maya,
    );
    await tester.runAsync(() async {
      await gcash.addManual(
        type: 'OPENING_BALANCE',
        amountCentavos: 350000,
        reason: 'Test opening balance',
        ownerPinAuthorized: true,
      );
      await maya.addManual(
        type: 'OPENING_BALANCE',
        amountCentavos: 185000,
        reason: 'Test opening balance',
        ownerPinAuthorized: true,
      );
    });
    final controller = AppPlanController(_PlanSource(AppPlan.pro));
    addTearDown(controller.dispose);
    final access = FeatureAccessService(db, planController: controller);
    final chosen = <(PaymentMethod, String)>[];
    var productSales = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CashSaleScreen(
            embedded: true,
            products: [_coffee()],
            saveSale: (_) async => ++productSales,
            cashServicesLauncher: CashServicesShortcut(
              access: access,
              gcash: gcash,
              maya: maya,
              onService: (provider, type) async {
                chosen.add((provider, type));
                if (chosen.length == 1) {
                  await GCashServiceRepository(db, actorRole: 'OWNER').record(
                    type: type,
                    principalCentavos: 1000,
                    feeCentavos: 0,
                    requestId: 'sales-shortcut-test',
                  );
                }
                return true;
              },
              onHistory: (_) async {},
            ),
          ),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.sell), label: 'Sales'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final launcher = find.byKey(const ValueKey('cash-services-launcher'));
    expect(launcher, findsOneWidget);
    expect(
      tester.getBottomLeft(launcher).dy,
      lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );

    await tester.tap(find.text('Coffee').first);
    await tester.pump();
    expect(find.text('1 item'), findsOneWidget);
    expect(
      tester.getBottomLeft(launcher).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('phone-current-sale-bar')))
            .dy,
      ),
    );
    await tester.tap(launcher);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
    expect(find.text('Balance: ₱3,500.00'), findsOneWidget);
    expect(find.text('Balance: ₱1,850.00'), findsOneWidget);
    for (final provider in [PaymentMethod.gcash, PaymentMethod.maya]) {
      for (final type in ['CASH_IN', 'CASH_OUT']) {
        expect(
          find.byKey(ValueKey('cash-services-${provider.dbValue}-$type')),
          findsOneWidget,
        );
      }
    }
    await tester.tap(find.byKey(const ValueKey('cash-services-GCASH-CASH_IN')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    expect(chosen, [(PaymentMethod.gcash, 'CASH_IN')]);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('₱15.00'), findsWidgets);
    expect(productSales, 0);
    final sales = await tester.runAsync(() => db.query('cash_sales'));
    expect(sales, isEmpty);

    await tester.tap(launcher);
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('Balance: ₱3,490.00'), findsOneWidget);
    await tester.tap(find.byTooltip('Close Cash Services'));
    await tester.pumpAndSettle();
    for (final choice in const [
      (PaymentMethod.gcash, 'CASH_OUT'),
      (PaymentMethod.maya, 'CASH_IN'),
      (PaymentMethod.maya, 'CASH_OUT'),
    ]) {
      await tester.tap(launcher);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('cash-services-${choice.$1.dbValue}-${choice.$2}')),
      );
      await tester.pumpAndSettle();
    }
    expect(chosen.length, 4);
    expect(chosen.last, (PaymentMethod.maya, 'CASH_OUT'));
    expect(find.text('1 item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Free shortcut is locked; sheet fits narrow dark phones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    final source = _PlanSource(AppPlan.free);
    final controller = AppPlanController(source);
    addTearDown(controller.dispose);
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: CashSaleScreen(
            embedded: true,
            products: [_coffee()],
            saveSale: (_) async => 1,
            cashServicesLauncher: CashServicesShortcut(
              access: FeatureAccessService(db, planController: controller),
              gcash: PaymentAccountingRepository(db),
              maya: PaymentAccountingRepository(
                db,
                provider: PaymentMethod.maya,
              ),
              onService: (_, _) async {
                actions++;
                return true;
              },
              onHistory: (_) async {},
            ),
          ),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.sell), label: 'Sales'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cash-services-launcher')));
    await tester.pumpAndSettle();
    expect(
      find.text('Use GCash and Maya for Cash-In and Cash-Out transactions.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cash-services-GCASH-CASH_IN')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('cash-services-MAYA-CASH_OUT')),
      findsNothing,
    );
    expect(actions, 0);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Close Cash Services'));
    await tester.pumpAndSettle();
    source.change(AppPlan.pro);
    await tester.pump();
    expect(find.text('PRO'), findsNothing);
    for (final width in [280.0, 320.0, 360.0, 390.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const ValueKey('cash-services-launcher')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('cash-services-GCASH-CASH_IN')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cash-services-MAYA-CASH_OUT')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close Cash Services'));
      await tester.pumpAndSettle();
    }
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cash-services-launcher')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('cash-services-card-GCASH')))
          .dy,
      tester
          .getTopLeft(find.byKey(const ValueKey('cash-services-card-MAYA')))
          .dy,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close Cash Services'));
    await tester.pumpAndSettle();
  });

  testWidgets('quick wallet entry opens each existing service form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    final controller = AppPlanController(_PlanSource(AppPlan.pro));
    addTearDown(controller.dispose);
    var provider = PaymentMethod.gcash;
    var type = 'CASH_IN';
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GCashScreen(
                      repository: PaymentAccountingRepository(
                        db,
                        actorRole: 'STAFF',
                        provider: provider,
                      ),
                      services: GCashServiceRepository(
                        db,
                        actorRole: 'STAFF',
                        provider: provider,
                      ),
                      auth: AuthService(db),
                      access: FeatureAccessService(
                        db,
                        planController: controller,
                      ),
                      initialServiceType: type,
                    ),
                  ),
                ),
                child: const Text('Open quick service'),
              ),
            ),
          ),
        ),
      ),
    );
    for (final wallet in [PaymentMethod.gcash, PaymentMethod.maya]) {
      for (final serviceType in ['CASH_IN', 'CASH_OUT']) {
        provider = wallet;
        type = serviceType;
        await tester.tap(find.text('Open quick service'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          find.text(
            '${wallet == PaymentMethod.maya ? 'Maya' : 'GCash'} ${serviceType == 'CASH_IN' ? 'Cash-In' : 'Cash-Out'}',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Open quick service'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
    provider = PaymentMethod.gcash;
    type = 'CASH_OUT';
    await tester.tap(find.text('Open quick service'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '100');
    await tester.tap(find.text('Review'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Review GCash Service'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    for (var i = 0;
        i < 10 && find.text('Open quick service').evaluate().isEmpty;
        i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 350));
    }
    expect(find.text('Open quick service'), findsOneWidget);
    final services = await tester.runAsync(
      () => db.query('gcash_service_transactions'),
    );
    expect(services, hasLength(1));
    expect(await tester.runAsync(() => db.query('cash_sales')), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
