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
    final rows = await db.query(
      'activity_logs',
      where:
          'created_at>=? AND created_at<?${category == null ? '' : ' AND event_type LIKE ?'}${q.isEmpty ? '' : ' AND description LIKE ? COLLATE NOCASE'}',
      whereArgs: [
        start,
        end,
        if (category != null) '$category%',
        if (q.isNotEmpty) '%$q%',
      ],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(ActivityLog.fromMap).toList(growable: false);
  }
}
