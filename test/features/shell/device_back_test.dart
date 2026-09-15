import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/shell/presentation/app_shell.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';

Future<void> settleDatabase(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 12; i++) {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();

  testWidgets('device Back returns a main section to Sales before exiting', (
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
    final db = await tester.runAsync(() => app.database);
    addTearDown(app.close);
    var exits = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') exits++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          database: db!,
          appDatabase: app,
          role: UserRole.owner,
          lock: () {},
          onThemePreferenceChanged: (_) async {},
        ),
      ),
    );
    await settleDatabase(tester);
    await tester.tap(find.text('Inventory').first);
    await settleDatabase(tester);
    expect(find.text('Search inventory'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await settleDatabase(tester);
    expect(exits, 0);
    expect(find.text('Current Sale'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(tester.takeException(), isNull);
  });
}
