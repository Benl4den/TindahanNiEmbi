import 'dart:async';

import 'package:sqflite/sqflite.dart';

enum AppThemePreference { system, light, dark }

enum OwnerSetupStage { storeNameEntered, ownerPinCreated, complete }

class StoreProfile {
  const StoreProfile({
    required this.storeName,
    this.ownerName = '',
    this.contactNumber = '',
    this.address = '',
    this.storePhotoPath = '',
  });

  final String storeName;
  final String ownerName;
  final String contactNumber;
  final String address;
  final String storePhotoPath;
}

extension AppThemePreferenceX on AppThemePreference {
  String get storageValue => name;
}

class SettingsService {
  const SettingsService(this.db);
  final Database db;
  static const fallbackStoreName = 'My Tindahan';
  static final _autoLockChanges = StreamController<int>.broadcast();
  static final _themeChanges = StreamController<AppThemePreference>.broadcast();
  Stream<int> get autoLockChanges => _autoLockChanges.stream;
  Stream<AppThemePreference> get themeChanges => _themeChanges.stream;

  static String? validateStoreName(String value) {
    final name = value.trim();
    if (name.isEmpty) return 'Enter your store name.';
    if (name.runes.length > 60) {
      return 'Store name must be 60 characters or less.';
    }
    return null;
  }

  Future<String?> get savedStoreName async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['store_name'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final name = (rows.single['value'] as String? ?? '').trim();
    return validateStoreName(name) == null ? name : null;
  }

  Future<String> get storeName async =>
      await savedStoreName ?? fallbackStoreName;

  Future<StoreProfile> get storeProfile async {
    final rows = await db.query(
      'app_settings',
      columns: ['key', 'value'],
      where: 'key IN (?, ?, ?, ?, ?)',
      whereArgs: [
        'store_name',
        'store_owner_name',
        'store_contact_number',
        'store_address',
        'store_photo_path',
      ],
    );
    final values = {
      for (final row in rows)
        row['key'] as String: (row['value'] as String? ?? '').trim(),
    };
    final savedName = values['store_name'] ?? '';
    return StoreProfile(
      storeName: validateStoreName(savedName) == null
          ? savedName
          : fallbackStoreName,
      ownerName: values['store_owner_name'] ?? '',
      contactNumber: values['store_contact_number'] ?? '',
      address: values['store_address'] ?? '',
      storePhotoPath: values['store_photo_path'] ?? '',
    );
  }

  Future<StoreProfile> saveStoreProfile(StoreProfile profile) async {
    final problem = validateStoreName(profile.storeName);
    if (problem != null) {
      throw ArgumentError.value(profile.storeName, 'storeName', problem);
    }
    final saved = StoreProfile(
      storeName: profile.storeName.trim(),
      ownerName: profile.ownerName.trim(),
      contactNumber: profile.contactNumber.trim(),
      address: profile.address.trim(),
      storePhotoPath: profile.storePhotoPath.trim(),
    );
    await db.transaction((txn) async {
      await _writeSetting(txn, 'store_name', saved.storeName);
      await _writeSetting(txn, 'store_owner_name', saved.ownerName);
      await _writeSetting(txn, 'store_contact_number', saved.contactNumber);
      await _writeSetting(txn, 'store_address', saved.address);
      await _writeSetting(txn, 'store_photo_path', saved.storePhotoPath);
    });
    return saved;
  }

  Future<OwnerSetupStage?> get ownerSetupStage async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['owner_setup_stage'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.single['value'] as String?;
    for (final stage in OwnerSetupStage.values) {
      if (stage.name == value) return stage;
    }
    return null;
  }

  Future<void> _writeSetting(
    DatabaseExecutor executor,
    String key,
    String value,
  ) async {
    await executor.insert('app_settings', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Used later by Tindahan Profile without changing onboarding state.
  Future<String> setStoreName(String value) async {
    final problem = validateStoreName(value);
    if (problem != null) throw ArgumentError.value(value, 'value', problem);
    final name = value.trim();
    await _writeSetting(db, 'store_name', name);
    return name;
  }

  Future<String> saveInitialStoreName(String value) async {
    final problem = validateStoreName(value);
    if (problem != null) throw ArgumentError.value(value, 'value', problem);
    final name = value.trim();
    await db.transaction((txn) async {
      final owner = await txn.query(
        'security_profiles',
        columns: ['id'],
        where: 'role = ?',
        whereArgs: ['OWNER'],
        limit: 1,
      );
      if (owner.isNotEmpty) {
        throw StateError('Owner PIN already exists.');
      }
      await _writeSetting(txn, 'store_name', name);
      await _writeSetting(
        txn,
        'owner_setup_stage',
        OwnerSetupStage.storeNameEntered.name,
      );
    });
    return name;
  }

  Future<void> markOwnerPinCreated() async {
    await db.transaction((txn) async {
      final name = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['store_name'],
        limit: 1,
      );
      final owner = await txn.query(
        'security_profiles',
        columns: ['id'],
        where: 'role = ?',
        whereArgs: ['OWNER'],
        limit: 1,
      );
      if (name.isEmpty ||
          validateStoreName(name.single['value'] as String? ?? '') != null ||
          owner.isEmpty) {
        throw StateError('Store name and Owner PIN are required.');
      }
      await _writeSetting(
        txn,
        'owner_setup_stage',
        OwnerSetupStage.ownerPinCreated.name,
      );
    });
  }

  Future<void> completeOwnerSetup() async {
    await db.transaction((txn) async {
      final name = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['store_name'],
        limit: 1,
      );
      final owner = await txn.query(
        'security_profiles',
        columns: ['id'],
        where: 'role = ?',
        whereArgs: ['OWNER'],
        limit: 1,
      );
      if (name.isEmpty ||
          validateStoreName(name.single['value'] as String? ?? '') != null ||
          owner.isEmpty) {
        throw StateError('Store name and Owner PIN are required.');
      }
      await _writeSetting(
        txn,
        'owner_setup_stage',
        OwnerSetupStage.complete.name,
      );
    });
  }

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
