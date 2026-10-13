import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/features/activity_logs/presentation/activity_logs_screen.dart';
import 'package:tindahan_ni_embi/features/activity_logs/presentation/staff_activity_screen.dart';
import 'package:tindahan_ni_embi/features/categories/presentation/categories_screen.dart';
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
    expect(find.text('SELECTA Products'), findsNothing);
    expect(find.text('Tindahan Profile'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('more-tindahan-profile')));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Store Information'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Tindahan Profile'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Managed Brands'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Managed Brands'), findsOneWidget);
    await tester.tap(find.text('Managed Brands'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
    expect(find.text('PRO FEATURE'), findsOneWidget);
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
    expect(find.text('Managed Brands'), findsNothing);
    expect(find.text('Tindahan Profile'), findsNothing);
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

  testWidgets('owner More fits a 280dp dark phone', (tester) async {
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
    await tester.runAsync(() async {
      await db.insert('products', {
        'name': 'Active product',
        'created_at': '2026-10-14T00:00:00',
        'updated_at': '2026-10-14T00:00:00',
      });
      await db.insert('products', {
        'name': 'Archived product',
        'is_archived': 1,
        'created_at': '2026-10-14T00:00:00',
        'updated_at': '2026-10-14T00:00:00',
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AppShell(
          database: db,
          appDatabase: app,
          role: UserRole.owner,
          lock: () {},
          onThemePreferenceChanged: (_) async {},
          onDatabaseRestored: () {},
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('YOUR TINDAHAN'), findsOneWidget);
    expect(find.byKey(const ValueKey('more-tindahan-profile')), findsOneWidget);
    final productLabel = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.textSpan?.toPlainText().startsWith('Products  (') ?? false),
    );
    await tester.scrollUntilVisible(
      productLabel,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(productLabel, findsOneWidget);
    final productText = tester.widget<Text>(productLabel);
    expect(productText.textSpan!.toPlainText(), 'Products  (1)');
    final countSpan =
        (productText.textSpan! as TextSpan).children!.last as TextSpan;
    expect(countSpan.style?.color, AppTheme.dark.colorScheme.onSurfaceVariant);
    final lockButton = find.byKey(const ValueKey('more-lock-app'));
    expect(lockButton, findsOneWidget);
    expect(
      tester.getBottomLeft(lockButton).dy,
      lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(find.text('Help & Guide'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Help & Guide')).dy,
      lessThan(tester.getTopLeft(lockButton).dy),
    );
    expect(lockButton, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More holds operations and Settings holds only configuration', (
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

    Widget shell(UserRole role) => MaterialApp(
      home: AppShell(
        database: db,
        appDatabase: app,
        role: role,
        lock: () {},
        onThemePreferenceChanged: (_) async {},
        onDatabaseRestored: () {},
      ),
    );

    await tester.pumpWidget(shell(UserRole.owner));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Backup & Restore'), findsNothing);

    await tester.ensureVisible(find.text('Categories'));
    await tester.tap(find.text('Categories'));
    await tester.pump();
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CategoriesScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Activity Logs'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Activity Logs'), findsOneWidget);
    expect(find.text('Staff Activity Summary'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Settings'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('APP PREFERENCES'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('MANAGEMENT'), findsNothing);
    expect(find.text('SYSTEM & TOOLS'), findsNothing);
    expect(find.text('Products'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Lock App'), findsNothing);
    expect(find.text('Low Stock (0)'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Backup & Restore'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Security & Staff'), findsOneWidget);
    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(find.text('Storage Management'), findsOneWidget);
    expect(find.text('Check Data Integrity'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(shell(UserRole.staff));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump();
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    expect(find.text('Categories'), findsNothing);
    expect(find.text('Activity Logs'), findsNothing);
    expect(find.text('Staff Activity Summary'), findsNothing);
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('About TindaSari PH'), findsOneWidget);
    expect(find.text('Security & Staff'), findsNothing);
    expect(find.text('Backup & Restore'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet sidebar keeps relocated owner pages reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;

    Widget shell(UserRole role) => MaterialApp(
      home: AppShell(
        database: db,
        appDatabase: app,
        role: role,
        lock: () {},
        onThemePreferenceChanged: (_) async {},
        onDatabaseRestored: () {},
      ),
    );

    await tester.pumpWidget(shell(UserRole.owner));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pump(const Duration(milliseconds: 350));
    final sidebar = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Categories'),
      260,
      scrollable: sidebar,
    );
    await tester.tap(find.text('Categories'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.byType(CategoriesScreen), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Activity Logs'),
      260,
      scrollable: sidebar,
    );
    await tester.tap(find.text('Activity Logs'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.byType(ActivityLogsScreen), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Staff Activity Summary'),
      260,
      scrollable: sidebar,
    );
    await tester.tap(find.text('Staff Activity Summary').first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.byType(StaffActivityScreen), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Help & Guide'),
      260,
      scrollable: sidebar,
    );
    await tester.tap(find.text('Help & Guide').first);
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      find.text('Simple guides for using your store app.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(shell(UserRole.staff));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Settings'),
      -260,
      scrollable: sidebar,
    );
    await tester.tap(find.text('Settings').first);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('About TindaSari PH'), findsOneWidget);
    expect(find.text('Categories'), findsNothing);
    expect(find.text('Activity Logs'), findsNothing);
    expect(find.text('Staff Activity Summary'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
