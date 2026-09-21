import 'package:sqflite/sqflite.dart';

import '../services/app_refresh_controller.dart';

class SupplierContact {
  const SupplierContact({
    required this.id,
    required this.name,
    this.contactNumber,
    required this.isArchived,
  });
  final int id;
  final String name;
  final String? contactNumber;
  final bool isArchived;
  factory SupplierContact.fromMap(Map<String, Object?> row) => SupplierContact(
    id: row['id']! as int,
    name: row['name']! as String,
    contactNumber: row['contact_number'] as String?,
    isArchived: row['is_archived'] == 1,
  );
}

class SupplierContactsRepository {
  const SupplierContactsRepository(this.db);
  final Database db;
  Future<List<SupplierContact>> list({
    String query = '',
    bool archived = false,
  }) async {
    final q = query.trim();
    final rows = await db.query(
      'supplier_contacts',
      where: q.isEmpty
          ? 'is_archived=?'
          : 'is_archived=? AND name LIKE ? COLLATE NOCASE',
      whereArgs: q.isEmpty ? [archived ? 1 : 0] : [archived ? 1 : 0, '%$q%'],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(SupplierContact.fromMap).toList();
  }

  Future<int> save({
    int? id,
    required String name,
    String? contactNumber,
  }) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) throw ArgumentError('Supplier name is required.');
    final now = DateTime.now().toUtc().toIso8601String();
    final values = {
      'name': clean,
      'contact_number': _optional(contactNumber),
      'updated_at': now,
    };
    final result = id == null
        ? await db.insert('supplier_contacts', {
            ...values,
            'is_archived': 0,
            'created_at': now,
          })
        : await db.update(
            'supplier_contacts',
            values,
            where: 'id=?',
            whereArgs: [id],
          );
    AppRefreshController.instance.dataChanged();
    return result;
  }

  Future<void> archive(int id, {bool archived = true}) async {
    await db.update(
      'supplier_contacts',
      {
        'is_archived': archived ? 1 : 0,
        'archived_at': archived
            ? DateTime.now().toUtc().toIso8601String()
            : null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=?',
      whereArgs: [id],
    );
    AppRefreshController.instance.dataChanged();
  }

  String? _optional(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}
