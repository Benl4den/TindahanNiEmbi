class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productName,
    required this.type,
    required this.quantityChange,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.notes,
    required this.occurredAt,
  });
  final int id;
  final String productName;
  final String type;
  final int quantityChange;
  final int quantityBefore;
  final int quantityAfter;
  final String? notes;
  final DateTime occurredAt;

  factory InventoryMovement.fromMap(Map<String, Object?> map) =>
      InventoryMovement(
        id: map['id']! as int,
        productName: map['product_name']! as String,
        type: map['type']! as String,
        quantityChange: map['quantity_change']! as int,
        quantityBefore: map['quantity_before']! as int,
        quantityAfter: map['quantity_after']! as int,
        notes: map['notes'] as String?,
        occurredAt: DateTime.parse(map['occurred_at']! as String),
      );
}
