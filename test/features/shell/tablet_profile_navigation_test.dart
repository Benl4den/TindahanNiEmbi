import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/shell/presentation/app_shell.dart';
import 'package:tindahan_ni_embi/features/store_profile/presentation/tindahan_profile_screen.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';
import 'package:tindahan_ni_embi/services/settings_service.dart';

void main() {
  sqfliteFfiInit();

  testWidgets(
    'tablet profile supports editing and collapsed navigation with owner access',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final db = (await tester.runAsync(() => app.database))!;
      final settings = SettingsService(db);
      await tester.runAsync(() => settings.setStoreName('Original Store'));

      Widget shell(UserRole role, ThemeData theme) => MaterialApp(
        theme: theme,
        home: AppShell(
          database: db,
          appDatabase: app,
          role: role,
          lock: () {},
          onThemePreferenceChanged: (_) async {},
          onDatabaseRestored: () {},
        ),
      );

      await tester.pumpWidget(shell(UserRole.owner, AppTheme.light));
      await _flush(tester);
      expect(find.byType(NavigationBar), findsNothing);
      final sidebar = find.byType(Scrollable).first;
      final profileEntry = find.descendant(
        of: sidebar,
        matching: find.text('Tindahan Profile'),
      );
      await tester.scrollUntilVisible(profileEntry, 260, scrollable: sidebar);
      await tester.pumpAndSettle();
      await tester.tap(profileEntry);
      await _flush(tester);
      expect(find.byType(TindahanProfileScreen), findsOneWidget);
      expect(find.text('Store Information'), findsOneWidget);
      expect(find.text('Original Store'), findsWidgets);
      expect(tester.takeException(), isNull);

      final editButton = find.text('Edit Tindahan Profile');
      await tester.scrollUntilVisible(
        editButton,
        200,
        scrollable: find.descendant(
          of: find.byType(TindahanProfileScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(editButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-store-name')),
        'Updated Tablet Store',
      );
      await tester.tap(find.text('Save Changes'));
      await _flush(tester);
      expect(find.byType(EditTindahanProfileScreen), findsNothing);
      expect(find.text('Updated Tablet Store'), findsWidgets);
      expect(
        await tester.runAsync(() => settings.storeName),
        'Updated Tablet Store',
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpWidget(shell(UserRole.owner, AppTheme.dark));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Collapse navigation'));
      await tester.pumpAndSettle();
      final collapsedProfileEntry = find.byTooltip('Tindahan Profile');
      await tester.scrollUntilVisible(
        collapsedProfileEntry,
        260,
        scrollable: sidebar,
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await _flush(tester);
      expect(find.byType(TindahanProfileScreen), findsNothing);
      await tester.tap(collapsedProfileEntry);
      await _flush(tester);
      expect(find.byType(TindahanProfileScreen), findsOneWidget);
      expect(find.text('Updated Tablet Store'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Check the role guard as well as hiding the sidebar entry.
      await tester.pumpWidget(shell(UserRole.staff, AppTheme.dark));
      await _flush(tester);
      expect(find.byTooltip('Tindahan Profile'), findsNothing);
      expect(find.byType(TindahanProfileScreen), findsNothing);
      expect(find.text('Owner permission required'), findsOneWidget);
      await tester.tap(find.byTooltip('Expand navigation'));
      await tester.pumpAndSettle();
      expect(find.text('Tindahan Profile'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _flush(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 12; i++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  await tester.pumpAndSettle();
}
