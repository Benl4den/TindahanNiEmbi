import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/shell/presentation/app_shell.dart';
import 'package:tindahan_ni_embi/services/app_refresh_controller.dart';
import 'package:tindahan_ni_embi/services/auth_service.dart';
import 'package:tindahan_ni_embi/services/settings_service.dart';
import 'package:tindahan_ni_embi/widgets/brand_logo.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('tablet store card stays compact and follows profile edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
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
    final photoPath = File('assets/branding/tindasari_storefront_clean.png')
        .absolute
        .path;
    await tester.runAsync(
      () => settings.saveStoreProfile(
        StoreProfile(
          storeName: 'Embi Sira Sita Store',
          storePhotoPath: photoPath,
        ),
      ),
    );

    Widget shell(ThemeData theme) => MaterialApp(
      theme: theme,
      home: AppShell(
        database: db,
        appDatabase: app,
        role: UserRole.owner,
        lock: () {},
        onThemePreferenceChanged: (_) async {},
        onDatabaseRestored: () {},
      ),
    );

    await tester.pumpWidget(shell(AppTheme.light));
    await _flush(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('sidebar-store-card')), findsOneWidget);
    final storeName = tester.widget<Text>(
      find.byKey(const ValueKey('sidebar-store-name')),
    );
    expect(storeName.data, 'Embi Sira Sita Store');
    expect(storeName.maxLines, 2);
    final photo = tester.widget<Image>(
      find.byKey(const ValueKey('sidebar-store-photo')),
    );
    expect((photo.image as FileImage).file.path, photoPath);
    expect(
      tester
          .widget<BrandLogo>(find.byKey(const ValueKey('sidebar-brand-logo')))
          .size,
      34,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('sidebar-store-card'))).dy,
      lessThan(tester.getTopLeft(find.text('DAILY SELLING')).dy),
    );
    expect(tester.takeException(), isNull);

    final longName = 'Embi Sira Sita Store and Neighborhood Grocery';
    await tester.runAsync(
      () => settings.saveStoreProfile(StoreProfile(storeName: longName)),
    );
    AppRefreshController.instance.dataChanged();
    await _flush(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('sidebar-store-name')))
          .data,
      longName,
    );
    expect(
      find.byKey(const ValueKey('sidebar-store-photo-fallback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpWidget(shell(AppTheme.dark));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Collapse navigation'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sidebar-store-card')), findsNothing);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(shell(AppTheme.light));
    await _flush(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-store-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });
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
