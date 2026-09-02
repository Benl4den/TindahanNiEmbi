import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import 'backup_service.dart';

class StorageSummary {
  const StorageSummary({
    this.freeBytes,
    required this.databaseBytes,
    required this.imageBytes,
    required this.backupBytes,
    required this.backupCount,
    required this.orphanImageCount,
  });
  final int? freeBytes;
  final int databaseBytes,
      imageBytes,
      backupBytes,
      backupCount,
      orphanImageCount;
  String get status => freeBytes == null
      ? 'Unavailable'
      : freeBytes! < 5 * 1024 * 1024 * 1024
      ? 'Critical'
      : freeBytes! < 10 * 1024 * 1024 * 1024
      ? 'Low Storage'
      : freeBytes! < 20 * 1024 * 1024 * 1024
      ? 'Warning'
      : 'Healthy';
}

class StorageManagementService {
  StorageManagementService(
    this.appDatabase, {
    this.documentsDirectory,
    MethodChannel? channel,
  }) : channel = channel ?? const MethodChannel('tindahan_ni_embi/storage');
  final AppDatabase appDatabase;
  final Directory? documentsDirectory;
  final MethodChannel channel;
  Future<Directory> get _documents async =>
      documentsDirectory ?? getApplicationDocumentsDirectory();

  Future<StorageSummary> summary() async {
    final docs = await _documents, dbPath = await appDatabase.resolvedPath;
    final db = File(dbPath),
        imageDir = Directory(path.join(docs.path, 'product_images'));
    final backups = await BackupService(
      appDatabase,
      documentsDirectory: docs,
    ).localBackups();
    final referenced = (await (await appDatabase.database).query(
      'products',
      columns: ['photo_path'],
    )).map((x) => path.normalize(x['photo_path']! as String)).toSet();
    final images = await _files(imageDir);
    int? free;
    try {
      free = await channel.invokeMethod<int>('freeBytes');
    } catch (_) {
      free = null;
    }
    return StorageSummary(
      freeBytes: free,
      databaseBytes: await db.exists() ? await db.length() : 0,
      imageBytes: await _size(images),
      backupBytes: await _size(backups),
      backupCount: backups.length,
      orphanImageCount: images
          .where((f) => !referenced.contains(path.normalize(f.path)))
          .length,
    );
  }

  Future<int> cleanOrphanedImages() async {
    final docs = await _documents,
        imageDir = Directory(path.join(docs.path, 'product_images'));
    final referenced = (await (await appDatabase.database).query(
      'products',
      columns: ['photo_path'],
    )).map((x) => path.normalize(x['photo_path']! as String)).toSet();
    var removed = 0;
    for (final file in await _files(imageDir)) {
      if (!referenced.contains(path.normalize(file.path))) {
        await file.delete();
        removed++;
      }
    }
    return removed;
  }

  Future<void> deleteOldBackup(File file) async {
    final docs = await _documents, normalized = path.normalize(file.path);
    if (!path.isWithin(docs.path, normalized) ||
        !path.basename(normalized).startsWith('TindahanNiEmbi_') ||
        !normalized.endsWith('.tnebackup.zip')) {
      throw ArgumentError('Only local TindahanNiEmbi backups can be deleted.');
    }
    if (await file.exists()) await file.delete();
  }

  Future<List<File>> _files(Directory directory) async =>
      await directory.exists()
      ? directory
            .list(recursive: false)
            .where((x) => x is File)
            .cast<File>()
            .toList()
      : [];
  Future<int> _size(Iterable<File> files) async {
    var total = 0;
    for (final f in files) {
      total += await f.length();
    }
    return total;
  }
}
