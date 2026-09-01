class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.eventType,
    required this.description,
    required this.createdAt,
    this.actorRole,
    this.relatedEntityType,
    this.relatedEntityId,
  });
  final int id;
  final String eventType, description;
  final String? actorRole, relatedEntityType;
  final int? relatedEntityId;
  final DateTime createdAt;

  factory ActivityLog.fromMap(Map<String, Object?> row) => ActivityLog(
    id: row['id']! as int,
    eventType: row['event_type']! as String,
    description: row['description']! as String,
    actorRole: row['actor_role'] as String?,
    relatedEntityType: row['related_entity_type'] as String?,
    relatedEntityId: row['related_entity_id'] as int?,
    createdAt: DateTime.parse(row['created_at']! as String),
  );
}
