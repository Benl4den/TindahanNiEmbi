import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/security/presentation/auth_gate.dart';
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Owner'), findsWidgets);
    expect(tester.takeException(), isNull);
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
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '1234');
    await tester.enterText(find.byType(TextField).at(1), '1234');
    await tester.tap(find.text('Save Owner PIN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock Test App'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Set Owner PIN'), findsNothing);
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
    configured = true;
  }

  @override
  Future<List<StaffAccount>> staffAccounts({bool activeOnly = false}) async =>
      const [];
}
