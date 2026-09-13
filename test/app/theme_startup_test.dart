import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/app/app.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/services/settings_service.dart';

void main() {
  sqfliteFfiInit();

  for (final preference in AppThemePreference.values) {
    testWidgets('restores ${preference.name} at startup and after hot reload', (
      tester,
    ) async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      await tester.runAsync(() async {
        await SettingsService(await database.database)
            .setThemePreference(preference);
      });
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.runAsync(() async {
        await tester.pumpWidget(TindahanNiEmbiApp(database: database));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });

      void verifyTheme() {
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.themeMode, switch (preference) {
          AppThemePreference.system => ThemeMode.system,
          AppThemePreference.light => ThemeMode.light,
          AppThemePreference.dark => ThemeMode.dark,
        });
        final context = tester.element(find.byType(Scaffold).first);
        expect(
          Theme.of(context).brightness,
          preference == AppThemePreference.dark
              ? Brightness.dark
              : Brightness.light,
        );
      }

      verifyTheme();
      // Exercise widget reassembly directly without the test binding's frame wait.
      // ignore: invalid_use_of_protected_member
      tester.element(find.byType(TindahanNiEmbiApp)).reassemble();
      await tester.pump();
      verifyTheme();
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await database.close();
      });
    });
  }
}
