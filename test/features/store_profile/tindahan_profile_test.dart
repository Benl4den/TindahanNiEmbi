import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/core/theme/app_theme.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/features/dashboard/presentation/dashboard_screen.dart';
import 'package:tindahan_ni_embi/features/store_profile/presentation/tindahan_profile_screen.dart';
import 'package:tindahan_ni_embi/services/settings_service.dart';
import 'package:tindahan_ni_embi/services/store_photo_service.dart';

class _FakePhotos implements StorePhotoService {
  _FakePhotos(this.path);
  final String path;
  @override
  Future<String?> chooseFromGallery() async => path;
  @override
  Future<void> delete(String photoPath) async {}
}

void main() {
  sqfliteFfiInit();

  test(
    'profile values use the existing store name and persist atomically',
    () async {
      final app = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(app.close);
      final settings = SettingsService(await app.database);
      await settings.setStoreName('Original Store');
      final saved = await settings.saveStoreProfile(
        const StoreProfile(
          storeName: '  New Store  ',
          ownerName: '  Juan  ',
          contactNumber: ' 0917 123 4567 ',
          address: '  Barangay Uno ',
          storePhotoPath: '/local/photo.jpg',
        ),
      );
      expect(saved.storeName, 'New Store');
      expect(await settings.storeName, 'New Store');
      final loaded = await settings.storeProfile;
      expect(loaded.ownerName, 'Juan');
      expect(loaded.contactNumber, '0917 123 4567');
      expect(loaded.address, 'Barangay Uno');
      expect(loaded.storePhotoPath, '/local/photo.jpg');
      await expectLater(
        settings.saveStoreProfile(
          const StoreProfile(storeName: '   ', ownerName: 'Wrong'),
        ),
        throwsArgumentError,
      );
      expect((await settings.storeProfile).ownerName, 'Juan');
    },
  );

  testWidgets(
    'view, edit, cancel, validation, photo and Dashboard name stay in sync',
    (tester) async {
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
      final settings = SettingsService(db);
      await tester.runAsync(() => settings.setStoreName('Original Store'));
      final photo = File('assets/branding/tindasari_storefront_clean.png')
          .absolute
          .path;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: TindahanProfileScreen(
            settings: settings,
            photos: _FakePhotos(photo),
          ),
        ),
      );
      await _flush(tester);
      expect(find.text('Original Store'), findsWidgets);
      expect(find.text('Not set'), findsNWidgets(3));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/branding/tindasari_storefront_clean.png',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Edit Tindahan Profile'));
      await tester.pumpAndSettle();
      final name = find.byKey(const ValueKey('profile-store-name'));
      await tester.enterText(name, 'Unsaved');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => settings.storeName), 'Original Store');

      await tester.tap(find.text('Edit Tindahan Profile'));
      await tester.pumpAndSettle();
      await tester.enterText(name, '  ');
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      expect(find.text('Enter your store name.'), findsOneWidget);
      await tester.enterText(name, 'a' * 61);
      await tester.pump();
      expect(tester.widget<TextField>(name).controller!.text.length, 60);
      await tester.enterText(name, 'Updated Store');
      await tester.enterText(
        find.byKey(const ValueKey('profile-owner-name')),
        'Maria',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-contact-number')),
        '0917 123 4567',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('profile-address')));
      await tester.enterText(
        find.byKey(const ValueKey('profile-address')),
        'Purok 1, Barangay Uno, City',
      );
      await tester.tap(find.byKey(const ValueKey('change-store-photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await _flush(tester);
      expect(find.text('Updated Store'), findsWidgets);
      expect(find.text('Maria'), findsOneWidget);
      expect(find.text('0917 123 4567'), findsOneWidget);
      expect(find.text('Purok 1, Barangay Uno, City'), findsOneWidget);
      expect(await tester.runAsync(() => settings.storeName), 'Updated Store');
      expect(
        (await tester.runAsync(() => settings.storeProfile))!.storePhotoPath,
        photo,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DashboardScreen(database: db, navigate: (_) {}),
        ),
      );
      await _flush(tester);
      expect(find.text('Updated Store'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('edit form fits narrow phones, dark theme and an open keyboard', (
    tester,
  ) async {
    final app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    addTearDown(app.close);
    final db = (await tester.runAsync(() => app.database))!;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    for (final width in [280.0, 320.0, 360.0, 390.0]) {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: EditTindahanProfileScreen(
            key: ValueKey('width-$width'),
            settings: SettingsService(db),
            initial: const StoreProfile(
              storeName: 'A long store name with many words',
            ),
          ),
        ),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(find.text('Save Changes'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });
}

Future<void> _flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}
