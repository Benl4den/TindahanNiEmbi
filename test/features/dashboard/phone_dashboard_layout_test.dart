import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/dashboard/presentation/dashboard_screen.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('phone dashboard header stays below Android status bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(database: db, navigate: (_) {}),
      ),
    );
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Dashboard')).dy,
      greaterThanOrEqualTo(32),
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(280, 640);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Receive Consignment'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.getSize(find.text('Receive Consignment')).width,
      greaterThan(100),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
