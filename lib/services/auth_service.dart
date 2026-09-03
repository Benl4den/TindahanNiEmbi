import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'app_refresh_controller.dart';

enum UserRole { owner, staff }

class StaffAccount {
  const StaffAccount({
    required this.id,
    required this.name,
    required this.active,
    this.lastLoginAt,
  });
  final int id;
  final String name;
  final bool active;
  final DateTime? lastLoginAt;
  factory StaffAccount.fromMap(Map<String, Object?> row) => StaffAccount(
    id: row['id']! as int,
    name: row['name']! as String,
    active: row['is_active'] == 1,
    lastLoginAt: row['last_login_at'] == null
        ? null
        : DateTime.parse(row['last_login_at']! as String),
  );
}

enum AppPermission {
  manageProducts,
  manageCategories,
  adjustInventory,
  reports,
  backupRestore,
  security,
  activityLogs,
  archiveRecords,
  stockIn,
  utang,
  payment,
  cashSale,
  viewInventory,
}

class PermissionService {
  const PermissionService();
  bool allows(UserRole role, AppPermission p) =>
      role == UserRole.owner ||
      const {
        AppPermission.stockIn,
        AppPermission.utang,
        AppPermission.payment,
        AppPermission.cashSale,
        AppPermission.viewInventory,
      }.contains(p);
  void require(UserRole role, AppPermission p) {
    if (!allows(role, p)) throw StateError('Permission denied.');
  }
}

class AuthService {
  AuthService(this.db);
  final Database db;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  static const iterations = 50000;
  Future<bool> get hasOwner async => (await db.query(
    'security_profiles',
    where: "role='OWNER'",
    limit: 1,
  )).isNotEmpty;
  Future<void> setPin(UserRole role, String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ArgumentError('PIN must be exactly 4 digits');
    }
    final random = Random.secure(),
        salt = Uint8List.fromList(
          List.generate(16, (_) => random.nextInt(256)),
        ),
        hash = _pbkdf2(utf8.encode(pin), salt, iterations, 32),
        now = DateTime.now().toUtc().toIso8601String();
    await db.insert('security_profiles', {
      'role': role == UserRole.owner ? 'OWNER' : 'STAFF',
      'pin_hash': base64Encode(hash),
      'salt': base64Encode(salt),
      'iterations': iterations,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('activity_logs', {
      'event_type': 'SECURITY_PIN_CHANGED',
      'description':
          '${role == UserRole.owner ? 'Owner' : 'Staff'} PIN changed',
      'actor_role': role == UserRole.owner ? 'OWNER' : 'STAFF',
      'created_at': now,
    });
  }

  Future<List<StaffAccount>> staffAccounts({bool activeOnly = false}) async {
    final rows = await db.query(
      'staff_accounts',
      where: activeOnly ? 'is_active=1' : null,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(StaffAccount.fromMap).toList(growable: false);
  }

  Future<int> addStaff(String name, String pin) async {
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName.isEmpty) throw ArgumentError('Staff name is required.');
    final values = _credentials(pin);
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.transaction((txn) async {
      final id = await txn.insert('staff_accounts', {
        'name': cleanName,
        ...values,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      await txn.insert('activity_logs', {
        'event_type': 'STAFF_CREATED',
        'description': 'Staff account created — $cleanName',
        'actor_role': 'OWNER',
        'related_entity_type': 'STAFF',
        'related_entity_id': id,
        'created_at': now,
      });
      return id;
    });
    AppRefreshController.instance.dataChanged();
    return id;
  }

  Future<void> resetStaffPin(int id, String pin) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final count = await db.update(
      'staff_accounts',
      {..._credentials(pin), 'updated_at': now},
      where: 'id=?',
      whereArgs: [id],
    );
    if (count != 1) throw StateError('Staff account not found.');
    AppRefreshController.instance.dataChanged();
  }

  Future<void> setStaffActive(int id, bool active) async {
    await db.update(
      'staff_accounts',
      {
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [id],
    );
    AppRefreshController.instance.dataChanged();
  }

  Map<String, Object> _credentials(String pin) {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ArgumentError('PIN must be exactly 4 digits');
    }
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    return {
      'pin_hash': base64Encode(_pbkdf2(utf8.encode(pin), salt, iterations, 32)),
      'salt': base64Encode(salt),
      'iterations': iterations,
    };
  }

  Future<UserRole?> verify(String pin, {int? staffId}) async {
    if (_lockedUntil?.isAfter(DateTime.now()) ?? false) {
      throw StateError('Too many attempts. Try again later.');
    }
    final profiles = staffId == null
        ? await db.query('security_profiles')
        : const <Map<String, Object?>>[];
    for (final row in profiles) {
      final salt = base64Decode(row['salt']! as String),
          expected = base64Decode(row['pin_hash']! as String),
          actual = _pbkdf2(
            utf8.encode(pin),
            salt,
            row['iterations']! as int,
            expected.length,
          );
      var diff = 0;
      for (var i = 0; i < expected.length; i++) {
        diff |= expected[i] ^ actual[i];
      }
      if (diff == 0) {
        _failedAttempts = 0;
        _lockedUntil = null;
        final role = row['role'] == 'OWNER' ? UserRole.owner : UserRole.staff;
        await db.insert('activity_logs', {
          'event_type': 'AUTH_LOGIN',
          'description':
              '${role == UserRole.owner ? 'Owner' : 'Staff'} logged in',
          'actor_role': role == UserRole.owner ? 'OWNER' : 'STAFF',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
        return role;
      }
    }
    if (staffId != null) {
      final rows = await db.query(
        'staff_accounts',
        where: 'id=? AND is_active=1',
        whereArgs: [staffId],
        limit: 1,
      );
      if (rows.isNotEmpty && _matches(pin, rows.single)) {
        _failedAttempts = 0;
        final now = DateTime.now().toUtc().toIso8601String();
        await db.update(
          'staff_accounts',
          {'last_login_at': now},
          where: 'id=?',
          whereArgs: [staffId],
        );
        await db.insert('activity_logs', {
          'event_type': 'AUTH_LOGIN',
          'description': '${rows.single['name']} logged in',
          'actor_role': 'STAFF',
          'related_entity_type': 'STAFF',
          'related_entity_id': staffId,
          'created_at': now,
        });
        return UserRole.staff;
      }
    }
    _failedAttempts++;
    if (_failedAttempts >= 5) {
      _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return null;
  }

  bool _matches(String pin, Map<String, Object?> row) {
    final salt = base64Decode(row['salt']! as String);
    final expected = base64Decode(row['pin_hash']! as String);
    final actual = _pbkdf2(
      utf8.encode(pin),
      salt,
      row['iterations']! as int,
      expected.length,
    );
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected[i] ^ actual[i];
    }
    return diff == 0;
  }

  Uint8List _pbkdf2(
    List<int> password,
    List<int> salt,
    int rounds,
    int length,
  ) {
    final h = Hmac(sha256, password), out = <int>[];
    for (var block = 1; out.length < length; block++) {
      final b = ByteData(4)..setUint32(0, block, Endian.big);
      var u = h.convert([...salt, ...b.buffer.asUint8List()]).bytes,
          t = List<int>.from(u);
      for (var i = 1; i < rounds; i++) {
        u = h.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.addAll(t);
    }
    return Uint8List.fromList(out.take(length).toList());
  }
}
