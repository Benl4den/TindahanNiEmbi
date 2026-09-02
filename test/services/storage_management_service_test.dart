import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/services/storage_management_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory temp;
  late AppDatabase app;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('storage_test_');
    app = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: '${temp.path}/live.db',
    );
    await app.database;
  });
  tearDown(() async {
    await app.close();
    await temp.delete(recursive: true);
  });

  test(
    'orphan cleanup preserves referenced images and all business data',
    () async {
      final images = Directory('${temp.path}/product_images')..createSync();
      final kept = File('${images.path}/kept.jpg')..writeAsBytesSync([1]);
      final orphan = File('${images.path}/orphan.jpg')..writeAsBytesSync([2]);
      final db = await app.database,
          now = DateTime.now().toUtc().toIso8601String();
      final category = await db.insert('categories', {
        'name': 'C',
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('products', {
        'category_id': category,
        'name': 'P',
        'photo_path': kept.path,
        'purchase_price_centavos': 1,
        'selling_price_centavos': 2,
        'current_quantity': 0,
        'minimum_stock_level': 0,
        'created_at': now,
        'updated_at': now,
      });
      final service = StorageManagementService(
        app,
        documentsDirectory: temp,
        channel: const MethodChannel('unavailable-test'),
      );
      expect((await service.summary()).orphanImageCount, 1);
      expect(await service.cleanOrphanedImages(), 1);
      expect(await kept.exists(), isTrue);
      expect(await orphan.exists(), isFalse);
      expect(await db.query('products'), hasLength(1));
    },
  );

  test('backup deletion rejects files outside managed local backups', () async {
    final outside = File('${Directory.systemTemp.path}/business.db');
    final service = StorageManagementService(
      app,
      documentsDirectory: temp,
      channel: const MethodChannel('unavailable-test'),
    );
    await expectLater(service.deleteOldBackup(outside), throwsArgumentError);
  });
}
