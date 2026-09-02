import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tindahan_ni_embi/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tindahan_ni_embi/repositories/dashboard_repository.dart';

void main() {
  testWidgets('dashboard has critical actions without tablet overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    void action() {}
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          loadSummary: () async => const DashboardSummary(
            products: 2,
            lowStock: 1,
            outOfStock: 0,
            outstandingCentavos: 500,
            stockOutToday: 3,
            inventoryValueCentavos: 1000,
          ),
          onCategoriesTap: action,
          onProductsTap: action,
          onInventoryTap: action,
          onStockInTap: action,
          onCustomersTap: action,
          onUtangTap: action,
          onCashSaleTap: action,
          onReportsTap: action,
          onBackupTap: action,
          onSecurityTap: action,
          onLockTap: action,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TindahanNiEmbi'), findsOneWidget);
    expect(find.text('Inventory'), findsWidgets);
    expect(find.text('Credit'), findsWidgets);
    expect(find.text('Sales'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          loadSummary: () async => const DashboardSummary(
            products: 2,
            lowStock: 1,
            outOfStock: 0,
            outstandingCentavos: 500,
            stockOutToday: 3,
            inventoryValueCentavos: 1000,
          ),
          onCategoriesTap: action,
          onProductsTap: action,
          onInventoryTap: action,
          onStockInTap: action,
          onCustomersTap: action,
          onUtangTap: action,
          onCashSaleTap: action,
          onReportsTap: action,
          onBackupTap: action,
          onSecurityTap: action,
          onLockTap: action,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
