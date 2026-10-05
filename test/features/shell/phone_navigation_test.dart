import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/shell/presentation/app_shell.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('phone navigation uses role-aware Home and a real More hub', (
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
    final db = await tester.runAsync(() => app.database);

    Widget shell(UserRole role) => MaterialApp(
      home: AppShell(
        database: db!,
        appDatabase: app,
        role: role,
        lock: () {},
        onThemePreferenceChanged: (_) async {},
        onDatabaseRestored: () {},
      ),
    );

    await tester.pumpWidget(shell(UserRole.owner));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('Supplier Contacts'), findsOneWidget);
    expect(find.text('Managed Brands / Selecta'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );

    await tester.pumpWidget(shell(UserRole.staff));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Managed Brands / Selecta'), findsNothing);
    expect(find.text('5/6 Loan Management'), findsNothing);
    await tester.tap(find.text('Home').last);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.text('Sales'), findsWidgets);
    await tester.tap(find.text('Sales').last);
    await tester.pump();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });
}
