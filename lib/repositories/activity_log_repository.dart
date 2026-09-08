import 'package:sqflite/sqflite.dart';

import '../models/activity_log.dart';

class ActivityLogRepository {
  const ActivityLogRepository(this.db);
  final Database db;

  Future<int> add({
    required String eventType,
    required String description,
    String? actorRole,
    String? entityType,
    int? entityId,
    DateTime? at,
  }) => db.insert('activity_logs', {
    'event_type': eventType,
    'description': description,
    'actor_role': actorRole,
    'related_entity_type': entityType,
    'related_entity_id': entityId,
    'created_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
  });

  Future<List<ActivityLog>> forDate(
    DateTime date, {
    String? category,
    String query = '',
  }) async {
    final localStart = DateTime(date.year, date.month, date.day);
    final start = localStart.toUtc().toIso8601String();
    final end = localStart
        .add(const Duration(days: 1))
        .toUtc()
        .toIso8601String();
    final q = query.trim();
    final conditions = ['created_at>=?', 'created_at<?'];
    final args = <Object?>[start, end];
    switch (category) {
      case 'SECURITY':
        conditions.add(
          "(event_type LIKE 'SECURITY%' OR event_type LIKE 'AUTH%' OR event_type LIKE 'STAFF%')",
        );
        break;
      case 'SALES':
        conditions.add("event_type LIKE 'SALES%'");
        break;
      case 'UTANG':
        conditions.add(
          "(event_type LIKE 'UTANG%' OR event_type LIKE '%PAYMENT%')",
        );
        break;
      case 'INVENTORY':
        conditions.add(
          "(event_type LIKE 'INVENTORY%' OR event_type LIKE 'PRODUCT%' OR event_type LIKE 'SPECIAL_INVENTORY%')",
        );
        break;
      case 'BACKUP':
        conditions.add("event_type LIKE 'BACKUP%'");
        break;
      case final value?:
        conditions.add('event_type LIKE ?');
        args.add('$value%');
        break;
    }
    if (q.isNotEmpty) {
      conditions.add(
        '(description LIKE ? COLLATE NOCASE OR actor_role LIKE ? COLLATE NOCASE)',
      );
      args.addAll(['%$q%', '%$q%']);
    }
    final rows = await db.query(
      'activity_logs',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(ActivityLog.fromMap).toList(growable: false);
  }
}
