class Category {
  const Category({
    required this.id,
    required this.name,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Category.fromMap(Map<String, Object?> map) => Category(
    id: map['id']! as int,
    name: map['name']! as String,
    isArchived: map['is_archived'] == 1,
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
  );
}
