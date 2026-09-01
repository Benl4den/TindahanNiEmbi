import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'database_migration.dart';
import 'migrations/migration_v1.dart';
import 'migrations/migration_v2.dart';
import 'migrations/migration_v3.dart';
import 'migrations/migration_v4.dart';
import 'migrations/migration_v5.dart';

class AppDatabase {
  AppDatabase({this.factory, this.databasePath});

  static const databaseName = 'tindahan_ni_embi.db';
  static const schemaVersion = 5;

  final DatabaseFactory? factory;
  final String? databasePath;
  Database? _database;
  String? _resolvedPath;

  static final List<DatabaseMigration> _migrations = [
    MigrationV1(),
    MigrationV2(),
    MigrationV3(),
    MigrationV4(),
    MigrationV5(),
  ];

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final selectedFactory = factory ?? databaseFactory;
    final dbPath =
        databasePath ??
        path.join(await selectedFactory.getDatabasesPath(), databaseName);
    _resolvedPath = dbPath;
    return selectedFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => _applyMigrations(db, 0, version),
        onUpgrade: _applyMigrations,
      ),
    );
  }

  Future<void> _applyMigrations(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (final migration in _migrations) {
      if (migration.version > oldVersion && migration.version <= newVersion) {
        await migration.migrate(db);
      }
    }
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }

  Future<String> get resolvedPath async {
    if (_resolvedPath == null) await database;
    return _resolvedPath!;
  }

  Future<void> replaceWith(String sourcePath) async {
    final target = await resolvedPath;
    await close();
    await File(sourcePath).copy(target);
    await database;
  }
}
