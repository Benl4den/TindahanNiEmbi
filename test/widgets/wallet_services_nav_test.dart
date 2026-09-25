import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/shell/presentation/app_shell.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';

void main() {
  sqfliteFfiInit();
  testWidgets(
    'Free sidebar names both wallet service modules and opens locked previews',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final db = await tester.runAsync(() => app.database);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: AppShell(
              database: db!,
              appDatabase: app,
              role: UserRole.owner,
              lock: () {},
              onThemePreferenceChanged: (_) async {},
              onDatabaseRestored: () {},
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 180));
      });
      await tester.pumpAndSettle();
      expect(find.text('GCash Services'), findsOneWidget);
      expect(find.text('Maya Services'), findsOneWidget);
      expect(find.text('PRO'), findsWidgets);
      await tester.tap(find.text('GCash Services'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 180)),
      );
      await tester.pump();
      expect(find.text('Manage GCash services in one place'), findsOneWidget);
      expect(find.text('PRO FEATURE'), findsOneWidget);
      await tester.tap(find.text('Maya Services').first);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 180)),
      );
      await tester.pump();
      expect(find.text('Manage Maya services in one place'), findsOneWidget);
      expect(find.text('PRO FEATURE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
