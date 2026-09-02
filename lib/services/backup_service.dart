import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';

class InvalidBackupException implements Exception {
  const InvalidBackupException(this.message);
  final String message;
}

class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.imageCount,
  });
  final int formatVersion, schemaVersion, imageCount;
  final DateTime createdAt;
  Map<String, Object> toJson() => {
    'format_version': formatVersion,
    'schema_version': schemaVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
    'database': 'database/tindahan.db',
    'images': 'images',
    'image_count': imageCount,
  };
  factory BackupManifest.fromJson(Map<String, Object?> j) {
    if (j['format_version'] != 1) {
      throw const InvalidBackupException('Unsupported backup format');
    }
    return BackupManifest(
      formatVersion: j['format_version']! as int,
      schemaVersion: j['schema_version']! as int,
      createdAt: DateTime.parse(j['created_at']! as String),
      imageCount: j['image_count']! as int,
    );
  }
}

class BackupService {
  BackupService(
    this.appDatabase, {
    this.documentsDirectory,
    this.keepLocalBackups = 5,
  });
  final AppDatabase appDatabase;
  final Directory? documentsDirectory;
  final int keepLocalBackups;
  Future<Directory> get _documents async =>
      documentsDirectory ?? await getApplicationDocumentsDirectory();
  Future<String> create({String? outputPath}) async {
    final temp = await Directory.systemTemp.createTemp('tindahan_backup_');
    try {
      final dbDir = Directory(path.join(temp.path, 'database'));
      final images = Directory(path.join(temp.path, 'images'));
      await dbDir.create();
      await images.create();
      final db = await appDatabase.database;
      final snapshot = path.join(dbDir.path, 'tindahan.db');
      final escaped = snapshot.replaceAll("'", "''");
      await db.execute("VACUUM INTO '$escaped'");
      var count = 0;
      final products = await db.query('products', columns: ['photo_path']);
      for (final row in products) {
        final source = File(row['photo_path']! as String);
        if (await source.exists()) {
          await source.copy(path.join(images.path, path.basename(source.path)));
          count++;
        }
      }
      final manifest = BackupManifest(
        formatVersion: 1,
        schemaVersion: AppDatabase.schemaVersion,
        createdAt: DateTime.now().toUtc(),
        imageCount: count,
      );
      await File(path.join(temp.path, 'manifest.json'))
          .writeAsString(jsonEncode(manifest.toJson()));
      final localTarget = outputPath == null;
      final target =
          outputPath ??
          path.join(
            (await _documents).path,
            'TindahanNiEmbi_${DateTime.now().millisecondsSinceEpoch}.tnebackup.zip',
          );
      await ZipFileEncoder().zipDirectory(temp, filename: target);
      await validate(target);
      if (localTarget) await rotateLocalBackups();
      await db.insert('activity_logs', {
        'event_type': 'BACKUP_CREATED',
        'description': 'Backup created',
        'actor_role': 'OWNER',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return target;
    } finally {
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  Future<DateTime?> lastSuccessfulBackup() async {
    final db = await appDatabase.database;
    final rows = await db.query(
      'activity_logs',
      columns: ['created_at'],
      where: "event_type='BACKUP_CREATED'",
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : DateTime.parse(rows.single['created_at']! as String).toLocal();
  }

  Future<List<File>> localBackups() async {
    final directory = await _documents;
    if (!await directory.exists()) return [];
    final files = await directory
        .list()
        .where(
          (e) =>
              e is File &&
              path.basename(e.path).startsWith('TindahanNiEmbi_') &&
              e.path.endsWith('.tnebackup.zip'),
        )
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> rotateLocalBackups() async {
    if (keepLocalBackups < 1) return;
    final files = await localBackups();
    for (final old in files.skip(keepLocalBackups)) {
      await old.delete();
    }
  }

  Future<BackupHealth> health() async {
    final files = await localBackups();
    if (files.isEmpty) return const BackupHealth(status: 'Backup Recommended');
    final file = files.first;
    try {
      final manifest = await validate(file.path);
      final modified = await file.lastModified();
      final age = DateTime.now().difference(modified).inDays;
      return BackupHealth(
        status: age > 14
            ? 'Backup Overdue'
            : age > 7
            ? 'Backup Recommended'
            : 'Recent',
        createdAt: manifest.createdAt.toLocal(),
        filePath: file.path,
        fileSizeBytes: await file.length(),
        imageCount: manifest.imageCount,
        schemaVersion: manifest.schemaVersion,
        valid: true,
      );
    } catch (_) {
      return BackupHealth(
        status: 'Backup Recommended',
        filePath: file.path,
        fileSizeBytes: await file.length(),
        valid: false,
      );
    }
  }

  Future<BackupManifest> validate(String archivePath) async {
    final archive = ZipDecoder().decodeBytes(
      await File(archivePath).readAsBytes(),
    );
    for (final f in archive) {
      final normalized = path.posix.normalize(f.name);
      if (path.posix.isAbsolute(normalized) ||
          normalized == '..' ||
          normalized.startsWith('../')) {
        throw const InvalidBackupException('Unsafe archive path');
      }
    }
    ArchiveFile? manifestFile, dbFile;
    var hasImages = false;
    var imageFiles = 0;
    for (final f in archive) {
      if (f.name == 'manifest.json') manifestFile = f;
      if (f.name == 'database/tindahan.db') dbFile = f;
      if (f.name == 'images' ||
          f.name == 'images/' ||
          f.name.startsWith('images/')) {
        hasImages = true;
        if (f.isFile) imageFiles++;
      }
    }
    if (manifestFile == null) {
      throw const InvalidBackupException('Missing manifest');
    }
    if (dbFile == null) throw const InvalidBackupException('Missing database');
    if (!hasImages) {
      throw const InvalidBackupException('Missing image structure');
    }
    final manifest = BackupManifest.fromJson(
      jsonDecode(utf8.decode(manifestFile.content as List<int>))
          as Map<String, Object?>,
    );
    if (manifest.schemaVersion > AppDatabase.schemaVersion) {
      throw const InvalidBackupException('Incompatible schema');
    }
    if (manifest.imageCount != imageFiles) {
      throw const InvalidBackupException('Backup image manifest mismatch');
    }
    final databaseBytes = dbFile.content as List<int>;
    if (databaseBytes.length < 16 ||
        utf8.decode(databaseBytes.take(15).toList()) != 'SQLite format 3') {
      throw const InvalidBackupException('Invalid SQLite snapshot');
    }
    return manifest;
  }

  Future<void> restore(String archivePath) async {
    await validate(archivePath);
    final temp = await Directory.systemTemp.createTemp('tindahan_restore_');
    final safety = await Directory.systemTemp.createTemp('tindahan_safety_');
    final dbPath = await appDatabase.resolvedPath;
    final docs = await _documents;
    final imageDir = Directory(path.join(docs.path, 'product_images'));
    try {
      final current = await appDatabase.database;
      await current.execute('PRAGMA wal_checkpoint(FULL)');
      await appDatabase.close();
      await File(dbPath).copy(path.join(safety.path, 'database.db'));
      if (await imageDir.exists()) {
        await _copyDirectory(
          imageDir,
          Directory(path.join(safety.path, 'images')),
        );
      }
      final archive = ZipDecoder().decodeBytes(
        await File(archivePath).readAsBytes(),
      );
      for (final f in archive.where((x) => x.isFile)) {
        final target = path.joinAll([temp.path, ...path.posix.split(f.name)]);
        if (!path.isWithin(temp.path, target)) {
          throw const InvalidBackupException('Unsafe archive path');
        }
        await File(target).parent.create(recursive: true);
        await File(target).writeAsBytes(f.content as List<int>);
      }
      await appDatabase.replaceWith(
        path.join(temp.path, 'database', 'tindahan.db'),
      );
      if (await imageDir.exists()) await imageDir.delete(recursive: true);
      final restoredImages = Directory(path.join(temp.path, 'images'));
      if (await restoredImages.exists()) {
        await _copyDirectory(restoredImages, imageDir);
      }
      final db = await appDatabase.database;
      final rows = await db.query('products', columns: ['id', 'photo_path']);
      for (final row in rows) {
        await db.update(
          'products',
          {
            'photo_path': path.join(
              imageDir.path,
              path.basename(row['photo_path']! as String),
            ),
          },
          where: 'id=?',
          whereArgs: [row['id']],
        );
      }
      await db.insert('activity_logs', {
        'event_type': 'BACKUP_RESTORED',
        'description': 'Backup restored',
        'actor_role': 'OWNER',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      await appDatabase.replaceWith(path.join(safety.path, 'database.db'));
      if (await imageDir.exists()) await imageDir.delete(recursive: true);
      final old = Directory(path.join(safety.path, 'images'));
      if (await old.exists()) await _copyDirectory(old, imageDir);
      rethrow;
    } finally {
      await temp.delete(recursive: true);
      await safety.delete(recursive: true);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list()) {
      if (entity is File) {
        await entity.copy(path.join(target.path, path.basename(entity.path)));
      }
    }
  }
}

class BackupHealth {
  const BackupHealth({
    required this.status,
    this.createdAt,
    this.filePath,
    this.fileSizeBytes = 0,
    this.imageCount = 0,
    this.schemaVersion,
    this.valid = false,
  });
  final String status;
  final DateTime? createdAt;
  final String? filePath;
  final int fileSizeBytes, imageCount;
  final int? schemaVersion;
  final bool valid;
}
