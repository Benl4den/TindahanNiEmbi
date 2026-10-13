import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/security/presentation/auth_gate.dart';
import 'package:tindahan_ni_embi/features/security/presentation/first_run_setup.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';
import 'package:tindahan_ni_embi/services/settings_service.dart';

void main() {
  sqfliteFfiInit();

  test('store identity and setup stage persist independently', () async {
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await app.database;
    final settings = SettingsService(db);
    final auth = AuthService(db);
    expect(await settings.storeName, SettingsService.fallbackStoreName);
    expect(await settings.ownerSetupStage, isNull);
    expect(
      await settings.saveInitialStoreName("  Embi's Store  "),
      "Embi's Store",
    );
    expect(await settings.savedStoreName, "Embi's Store");
    expect(await settings.ownerSetupStage, OwnerSetupStage.storeNameEntered);
    expect(await auth.hasOwner, isFalse);
    await expectLater(settings.completeOwnerSetup(), throwsStateError);
    await auth.setPin(UserRole.owner, '1234');
    await settings.markOwnerPinCreated();
    expect(await settings.ownerSetupStage, OwnerSetupStage.ownerPinCreated);
    await settings.completeOwnerSetup();
    expect(await settings.ownerSetupStage, OwnerSetupStage.complete);
    expect(
      await settings.setStoreName('Tindahan ni Maria'),
      'Tindahan ni Maria',
    );
    expect(await settings.ownerSetupStage, OwnerSetupStage.complete);
    expect(await auth.verify('1234'), UserRole.owner);
  });

  test('store name validation trims, accepts punctuation and rejects invalid input', () {
    expect(SettingsService.validateStoreName('  '), 'Enter your store name.');
    expect(
      SettingsService.validateStoreName('a' * 61),
      'Store name must be 60 characters or less.',
    );
    expect(
      SettingsService.validateStoreName("  Juan's Sari-Sari & Co. 2  "),
      isNull,
    );
  });

  testWidgets('first-run validation, PIN cells and completion preserve name', (
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
    final settings = SettingsService(db!);
    await _launch(tester, AuthService(db));
    expect(find.text('Get Started'), findsOneWidget);
    expect(
      _assetImage('assets/branding/tindasari_storefront_clean.png'),
      findsOneWidget,
    );
    expect(find.text('Welcome back!'), findsNothing);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();
    expect(find.text('Set up your tindahan'), findsOneWidget);
    expect(
      _assetImage('assets/branding/tindasari_storefront_clean.png'),
      findsOneWidget,
    );
    expect(
      _assetImage('assets/branding/tindasari_lightbulb_clean.png'),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue'));
    await _flushSqlite(tester);
    await tester.pumpAndSettle();
    expect(find.text('Enter your store name.'), findsOneWidget);
    final nameField = find.byKey(const ValueKey('first-run-store-name'));
    await tester.enterText(nameField, '    ');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your store name.'), findsOneWidget);
    await tester.enterText(nameField, 'a' * 61);
    await tester.pump();
    expect(
      find.text('Store name must be 60 characters or less.'),
      findsOneWidget,
    );
    await tester.enterText(nameField, "  Embi's Store  ");
    await tester.pump();
    expect(find.text('16/60'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await _flushSqlite(tester);
    await tester.pumpAndSettle();
    expect(find.text('Create Owner PIN'), findsOneWidget);
    expect(
      await tester.runAsync(() => settings.savedStoreName),
      "Embi's Store",
    );
    expect(await tester.runAsync(() => AuthService(db).hasOwner), isFalse);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(nameField).controller!.text,
      "Embi's Store",
    );
    await tester.tap(find.text('Continue'));
    await _flushSqlite(tester);
    await tester.pumpAndSettle();

    final pin = find.byKey(const ValueKey('first-run-owner-pin'));
    final confirm = find.byKey(const ValueKey('first-run-confirm-pin'));
    expect(tester.widget<TextField>(pin).obscureText, isTrue);
    expect(tester.widget<TextField>(pin).keyboardType, TextInputType.number);
    expect(tester.widget<TextField>(pin).decoration!.filled, isFalse);
    expect(tester.widget<TextField>(confirm).decoration!.filled, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create PIN'))
          .onPressed,
      isNull,
    );
    await tester.enterText(pin, '12ab34');
    await tester.pump();
    expect(tester.widget<TextField>(pin).controller!.text, '1234');
    await tester.enterText(confirm, '4321');
    await tester.pump();
    expect(find.text('PINs do not match'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Create PIN'))
          .onPressed,
      isNull,
    );
    await tester.enterText(confirm, '1234');
    await tester.pump();
    await tester.tap(find.text('Create PIN'));
    await _flushSqlite(tester);
    await tester.pumpAndSettle();
    expect(find.text('All Set!'), findsOneWidget);
    expect(find.text("Embi's Store"), findsOneWidget);
    expect(
      _assetImage('assets/branding/tindasari_storefront_clean.png'),
      findsOneWidget,
    );
    expect(
      await tester.runAsync(() => settings.ownerSetupStage),
      OwnerSetupStage.ownerPinCreated,
    );
    await tester.tap(find.text('Go to Dashboard'));
    await _flushSqlite(tester);
    await tester.pumpAndSettle();
    expect(find.text('Test Dashboard'), findsOneWidget);
    expect(
      await tester.runAsync(() => settings.ownerSetupStage),
      OwnerSetupStage.complete,
    );

    await _launch(tester, AuthService(db), key: const ValueKey('restarted'));
    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interrupted setup resumes safely and requires Owner PIN', (
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
    final db = await tester.runAsync(() => app.database);
    final auth = AuthService(db!);
    final settings = SettingsService(db);
    await tester.runAsync(() => settings.saveInitialStoreName('Resume Store'));
    await _launch(tester, auth);
    expect(find.text('Create Owner PIN'), findsOneWidget);
    expect(find.text('Test Dashboard'), findsNothing);
    await tester.runAsync(() => auth.setPin(UserRole.owner, '2468'));
    await _launch(tester, auth, key: const ValueKey('pin-saved-restart'));
    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Test Dashboard'), findsNothing);
    for (final digit in ['2', '4', '6', '8']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    // PBKDF verification and the FFI database worker run in real time while
    // widget tests use a fake clock. Poll the actual result under load.
    for (
      var attempt = 0;
      attempt < 50 && find.text('All Set!').evaluate().isEmpty;
      attempt++
    ) {
      await _flushSqlite(tester);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('All Set!'), findsOneWidget);
    expect(find.text('Resume Store'), findsOneWidget);
    await tester.tap(find.text('Go to Dashboard'));
    await _flushSqlite(tester);
    await tester.pumpAndSettle();
    expect(find.text('Test Dashboard'), findsOneWidget);
  });

  testWidgets('existing Owner without store name retains login and data', (
    tester,
  ) async {
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = await tester.runAsync(() => app.database);
    final auth = AuthService(db!);
    await tester.runAsync(() => auth.setPin(UserRole.owner, '1111'));
    await _launch(tester, auth);
    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Get Started'), findsNothing);
    expect(
      await tester.runAsync(() => SettingsService(db).storeName),
      'My Tindahan',
    );
    expect(await tester.runAsync(() => auth.verify('1111')), UserRole.owner);
  });

  testWidgets(
    'setup reflows on compact phones, tablets, dark theme and keyboard',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final db = (await tester.runAsync(() => app.database))!;
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        for (final width in [280.0, 320.0, 360.0, 390.0, 1024.0]) {
          tester.view.physicalSize = Size(width, width == 1024 ? 768 : 640);
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: AuthGate(
                key: ValueKey('$width-${theme.brightness}'),
                auth: AuthService(db),
                builder: (_, _) => const Text('Test Dashboard'),
              ),
            ),
          );
          await _flushSqlite(tester);
          await tester.pumpAndSettle();
          expect(find.text('Get Started'), findsOneWidget);
          await tester.ensureVisible(find.text('Get Started'));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$width ${theme.brightness} welcome',
          );
          await tester.tap(find.text('Get Started'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Continue'));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$width ${theme.brightness} name',
          );
          for (final step in [FirstRunStep.ownerPin, FirstRunStep.complete]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: FirstRunSetup(
                  key: ValueKey('$width-${theme.brightness}-$step'),
                  auth: AuthService(db),
                  settings: SettingsService(db),
                  initialName: 'Phone Test Store',
                  initialStep: step,
                  onComplete: () {},
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.text(
                step == FirstRunStep.ownerPin
                    ? 'Create PIN'
                    : 'Go to Dashboard',
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$width ${theme.brightness} $step',
            );
          }
        }
      }
      tester.view.physicalSize = const Size(280, 640);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: FirstRunSetup(
            key: const ValueKey('keyboard-pin-step'),
            auth: AuthService(db),
            settings: SettingsService(db),
            initialName: 'Phone Test Store',
            initialStep: FirstRunStep.ownerPin,
            onComplete: () {},
          ),
        ),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create PIN'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _launch(WidgetTester tester, AuthService auth, {Key? key}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: AuthGate(
        key: key,
        auth: auth,
        builder: (_, _) => const Text('Test Dashboard'),
      ),
    ),
  );
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

Finder _assetImage(String asset) => find.byWidgetPredicate(
  (widget) =>
      widget is Image &&
      widget.image is AssetImage &&
      (widget.image as AssetImage).assetName == asset,
);
