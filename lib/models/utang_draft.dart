class UtangItemDraft {
  const UtangItemDraft({required this.productId, required this.quantity});
  final int productId;
  final int quantity;
}

class UtangDraft {
  const UtangDraft({
    required this.customerId,
    required this.items,
    this.notes,
    this.occurredAt,
  });
  final int customerId;
  final List<UtangItemDraft> items;
  final String? notes;
  final DateTime? occurredAt;
}
