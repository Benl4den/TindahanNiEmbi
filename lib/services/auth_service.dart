import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

enum UserRole { owner, staff }

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

  Future<UserRole?> verify(String pin) async {
    if (_lockedUntil?.isAfter(DateTime.now()) ?? false) {
      throw StateError('Too many attempts. Try again later.');
    }
    for (final row in await db.query('security_profiles')) {
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
    _failedAttempts++;
    if (_failedAttempts >= 5) {
      _lockedUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    return null;
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
