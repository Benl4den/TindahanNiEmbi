import 'dart:async';

import 'package:sqflite/sqflite.dart';

class SettingsService {
  const SettingsService(this.db);
  final Database db;
  static final _autoLockChanges = StreamController<int>.broadcast();
  Stream<int> get autoLockChanges => _autoLockChanges.stream;
  Future<int> get autoLockMinutes async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: "key='auto_lock_minutes'",
      limit: 1,
    );
    return rows.isEmpty
        ? 0
        : int.tryParse(rows.single['value']! as String) ?? 0;
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    if (![0, 5, 10, 15, 30].contains(minutes)) {
      throw ArgumentError.value(minutes);
    }
    await db.insert('app_settings', {
      'key': 'auto_lock_minutes',
      'value': '$minutes',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _autoLockChanges.add(minutes);
  }
}
