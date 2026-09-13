import 'dart:async';

import 'package:sqflite/sqflite.dart';

enum AppThemePreference { system, light, dark }

extension AppThemePreferenceX on AppThemePreference {
  String get storageValue => name;
}

class SettingsService {
  const SettingsService(this.db);
  final Database db;
  static final _autoLockChanges = StreamController<int>.broadcast();
  static final _themeChanges = StreamController<AppThemePreference>.broadcast();
  Stream<int> get autoLockChanges => _autoLockChanges.stream;
  Stream<AppThemePreference> get themeChanges => _themeChanges.stream;

  Future<AppThemePreference> get themePreference async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: "key='theme_preference'",
      limit: 1,
    );
    final value = rows.isEmpty ? null : rows.single['value'] as String?;
    return AppThemePreference.values.cast<AppThemePreference?>().firstWhere(
          (x) => x?.storageValue == value,
          orElse: () => AppThemePreference.system,
        ) ??
        AppThemePreference.system;
  }

  Future<void> setThemePreference(AppThemePreference preference) async {
    await db.insert('app_settings', {
      'key': 'theme_preference',
      'value': preference.storageValue,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _themeChanges.add(preference);
  }

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
