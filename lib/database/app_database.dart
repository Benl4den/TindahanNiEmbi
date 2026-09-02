import 'dart:io';
import 'dart:developer' as developer;

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'database_migration.dart';
import 'migrations/migration_v1.dart';
import 'migrations/migration_v2.dart';
import 'migrations/migration_v3.dart';
import 'migrations/migration_v4.dart';
import 'migrations/migration_v5.dart';
import 'migrations/migration_v6.dart';
import 'migrations/migration_v7.dart';
import 'migrations/migration_v8.dart';
import 'migrations/migration_v9.dart';

class AppDatabase {
  AppDatabase({this.factory, this.databasePath});

  static const databaseName = 'tindahan_ni_embi.db';
  static const schemaVersion = 9;

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
    MigrationV6(),
    MigrationV7(),
    MigrationV8(),
    MigrationV9(),
  ];

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    developer.log('Opening application database', name: 'TindahanStartup');
    final selectedFactory = factory ?? databaseFactory;
    final dbPath =
        databasePath ??
        path.join(await selectedFactory.getDatabasesPath(), databaseName);
    _resolvedPath = dbPath;
    try {
      final opened = await selectedFactory.openDatabase(
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
      developer.log(
        'Database ready at schema V$schemaVersion',
        name: 'TindahanStartup',
      );
      return opened;
    } catch (error, stackTrace) {
      developer.log(
        'Database startup failed',
        name: 'TindahanStartup',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _applyMigrations(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (final migration in _migrations) {
      if (migration.version > oldVersion && migration.version <= newVersion) {
        developer.log(
          'Applying migration V${migration.version}',
          name: 'TindahanStartup',
        );
        await migration.migrate(db);
        developer.log(
          'Applied migration V${migration.version}',
          name: 'TindahanStartup',
        );
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
