import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/security/presentation/auth_gate.dart';
import 'package:tindahan_ni_embi/features/security/presentation/security_screen.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('login fits a landscape tablet without overflow', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final database = await tester.runAsync(() => app.database);
    final auth = _LayoutAuth(database!);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthGate(auth: auth, builder: (_, _) => const SizedBox()),
      ),
    );
    await _flushSqlite(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Owner'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login fits portrait phones and keeps the full PIN pad usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final database = await tester.runAsync(() => app.database);
    final auth = _LayoutAuth(database!);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthGate(auth: auth, builder: (_, _) => const SizedBox()),
      ),
    );
    await _flushSqlite(tester);
    await tester.pumpAndSettle();

    for (final size in const [Size(390, 844), Size(320, 640)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.text('Welcome back!'), findsOneWidget);
      expect(find.text('Ready  •  Data saved on this device'), findsOneWidget);
      await tester.ensureVisible(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await tester.ensureVisible(find.text('1'));
    await tester.tap(find.text('1'));
    await tester.pump();
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any((widget) => widget.properties.label == '1 PIN digits entered'),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff controls and staff form fit compact Android phones', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(280, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final database = (await tester.runAsync(() => app.database))!;
    await tester.pumpWidget(
      MaterialApp(home: SecurityScreen(auth: _SecurityLayoutAuth(database))),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    for (final width in [280.0, 320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 640);
      await tester.pumpAndSettle();
      expect(find.text('Phone Cashier'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Security at ${width}dp');
    }

    tester.view.physicalSize = const Size(280, 640);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Staff').first);
    await tester.pumpAndSettle();
    expect(find.text('Staff name'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('first PIN setup locks back to login without app restart', (
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
    final database = await tester.runAsync(() => app.database);
    final auth = _FirstSetupAuth(database!);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AuthGate(
          auth: auth,
          builder: (_, lock) =>
              FilledButton(onPressed: lock, child: const Text('Lock Test App')),
        ),
      ),
    );
    await _flushSqlite(tester);
    await tester.pumpAndSettle();
    await _completeFirstSetup(tester);
    await tester.tap(find.text('Lock Test App'));
    await _flushSqlite(tester);
    await tester.pumpAndSettle();

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Set Owner PIN'), findsNothing);
  });

  testWidgets('locking from a pushed screen removes it above the PIN screen', (
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
    final database = await tester.runAsync(() => app.database);
    final auth = _FirstSetupAuth(database!);
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          auth: auth,
          builder: (_, lock) => Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    body: TextButton(
                      onPressed: lock,
                      child: const Text('Lock From Details'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open Details'),
            ),
          ),
        ),
      ),
    );
    await _flushSqlite(tester);
    await tester.pumpAndSettle();
    await _completeFirstSetup(tester);
    await tester.tap(find.text('Open Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock From Details'));
    await _flushSqlite(tester);
    await tester.pumpAndSettle();
    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Lock From Details'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _LayoutAuth extends AuthService {
  _LayoutAuth(super.db);

  @override
  Future<bool> get hasOwner async => true;

  @override
  Future<List<StaffAccount>> staffAccounts({bool activeOnly = false}) async =>
      const [];
}

class _FirstSetupAuth extends AuthService {
  _FirstSetupAuth(super.db);
  bool configured = false;

  @override
  Future<bool> get hasOwner async => configured;

  @override
  Future<void> setPin(UserRole role, String pin) async {
    await super.setPin(role, pin);
    configured = true;
  }

  @override
  Future<List<StaffAccount>> staffAccounts({bool activeOnly = false}) async =>
      const [];
}

Future<void> _completeFirstSetup(WidgetTester tester) async {
  await tester.tap(find.text('Get Started'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('first-run-store-name')),
    "Embi's Store",
  );
  await tester.tap(find.text('Continue'));
  await _flushSqlite(tester);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('first-run-owner-pin')),
    '1234',
  );
  await tester.enterText(
    find.byKey(const ValueKey('first-run-confirm-pin')),
    '1234',
  );
  await tester.pump();
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('first-run-owner-pin')))
        .controller!
        .text,
    '1234',
  );
  expect(
    tester
        .widget<TextField>(find.byKey(const ValueKey('first-run-confirm-pin')))
        .controller!
        .text,
    '1234',
  );
  expect(
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create PIN'))
        .onPressed,
    isNotNull,
  );
  await tester.tap(find.text('Create PIN'));
  await _flushSqlite(tester);
  await tester.pumpAndSettle();
  expect(
    find.text('All Set!'),
    findsOneWidget,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .join(' | '),
  );
  await tester.tap(find.text('Go to Dashboard'));
  await _flushSqlite(tester);
  await tester.pumpAndSettle();
}

Future<void> _flushSqlite(WidgetTester tester) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
}

class _SecurityLayoutAuth extends AuthService {
  _SecurityLayoutAuth(super.db);

  @override
  Future<List<StaffAccount>> staffAccounts({
    bool activeOnly = false,
  }) async => const [
    StaffAccount(id: 1, name: 'Phone Cashier', active: true, lastLoginAt: null),
  ];
}
