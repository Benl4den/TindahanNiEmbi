import 'package:sqflite/sqflite.dart';

abstract interface class DatabaseMigration {
  int get version;
  Future<void> migrate(DatabaseExecutor db);
}
