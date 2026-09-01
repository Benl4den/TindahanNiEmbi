import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tindahan_ni_embi/database/app_database.dart';
import 'package:tindahan_ni_embi/services/backup_service.dart';

void main() {
  sqfliteFfiInit();
  late Directory temp;
  late AppDatabase app;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('backup_test_');
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

  Future<void> seed(File image) async {
    final now = DateTime.now().toUtc().toIso8601String(),
        db = await app.database;
    final category = await db.insert('categories', {
      'name': 'Original',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('products', {
      'category_id': category,
      'name': 'Paninda',
      'photo_path': image.path,
      'purchase_price_centavos': 1,
      'selling_price_centavos': 2,
      'current_quantity': 0,
      'minimum_stock_level': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  test('creates and validates database plus image backup', () async {
    final image = File('${temp.path}/photo.jpg');
    await image.writeAsBytes([1, 2, 3]);
    await seed(image);
    final target = '${temp.path}/backup.zip',
        service = BackupService(app, documentsDirectory: temp);
    await service.create(outputPath: target);
    final manifest = await service.validate(target);
    expect(manifest.schemaVersion, AppDatabase.schemaVersion);
    expect(manifest.imageCount, 1);
    final archive = ZipDecoder().decodeBytes(await File(target).readAsBytes());
    expect(archive.any((f) => f.name == 'database/tindahan.db'), isTrue);
    expect(archive.any((f) => f.name == 'images/photo.jpg'), isTrue);
  });

  test('rejects missing manifest, database and unsupported format', () async {
    Future<String> zip(Map<String, List<int>> files, String name) async {
      final d = Directory('${temp.path}/$name')..createSync();
      for (final e in files.entries) {
        final f = File('${d.path}/${e.key}');
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(e.value);
      }
      final z = '${temp.path}/$name.zip';
      await ZipFileEncoder().zipDirectory(d, filename: z);
      return z;
    }

    final service = BackupService(app, documentsDirectory: temp);
    await expectLater(
      service.validate(
        await zip({
          'database/tindahan.db': [1],
        }, 'missing'),
      ),
      throwsA(isA<InvalidBackupException>()),
    );
    final base = {
      'created_at': DateTime.now().toIso8601String(),
      'image_count': 0,
      'schema_version': 3,
    };
    await expectLater(
      service.validate(
        await zip({
          'manifest.json': utf8.encode(
            jsonEncode({'format_version': 1, ...base}),
          ),
        }, 'nodb'),
      ),
      throwsA(isA<InvalidBackupException>()),
    );
    await expectLater(
      service.validate(
        await zip({
          'manifest.json': utf8.encode(
            jsonEncode({'format_version': 99, ...base}),
          ),
          'database/tindahan.db': [1],
        }, 'badformat'),
      ),
      throwsA(isA<InvalidBackupException>()),
    );
  });

  test('restore coordinates database and product images', () async {
    final imageDir = Directory('${temp.path}/product_images')..createSync(),
        image = File('${temp.path}/product_images/photo.jpg');
    await image.writeAsBytes([7, 8, 9]);
    await seed(image);
    final service = BackupService(app, documentsDirectory: temp),
        backup = await service.create(outputPath: '${temp.path}/restore.zip'),
        db = await app.database;
    await db.update('categories', {'name': 'Changed'});
    await image.writeAsBytes([0]);
    await service.restore(backup);
    final restored = await app.database;
    expect((await restored.query('categories')).single['name'], 'Original');
    final restoredPath =
        (await restored.query('products')).single['photo_path']! as String;
    expect(await File(restoredPath).readAsBytes(), [7, 8, 9]);
    expect(imageDir.existsSync(), isTrue);
  });

  test('rejects archive path traversal', () async {
    final archive = Archive()
      ..add(ArchiveFile('../escape.txt', 1, [1]))
      ..add(ArchiveFile('manifest.json', 2, [123, 125]))
      ..add(ArchiveFile('database/tindahan.db', 1, [1]));
    final file = File('${temp.path}/unsafe.zip');
    await file.writeAsBytes(ZipEncoder().encode(archive));
    await expectLater(
      BackupService(app, documentsDirectory: temp).validate(file.path),
      throwsA(isA<InvalidBackupException>()),
    );
  });
}
