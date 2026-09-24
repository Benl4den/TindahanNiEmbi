import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/services/app_refresh_controller.dart';
import 'package:tindahan_ni_embi/features/operations/presentation/daily_closing_screen.dart';
import 'package:tindahan_ni_embi/models/customer.dart';
import 'package:tindahan_ni_embi/repositories/customer_repository.dart';
import 'package:tindahan_ni_embi/repositories/operations_repository.dart';
import 'package:tindahan_ni_embi/repositories/utang_repository.dart';

void main() {
  sqfliteFfiInit();
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
      await tester.scrollUntilVisible(find.text('Today'), -500);
      await tester.runAsync(() async {
        await tester.tap(find.text('Today'));
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
