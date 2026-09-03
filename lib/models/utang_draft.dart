class UtangItemDraft {
  const UtangItemDraft({
    required this.productId,
    required this.quantity,
    this.sellingOptionId,
    this.sellingOptionName,
    this.quantityValue,
    this.quantityScale = 1,
    this.baseQuantityPerUnit = 1,
    this.baseUnitLabel = 'piece',
    this.unitPriceCentavos,
  });
  final int productId;
  final int quantity;
  final int? sellingOptionId;
  final String? sellingOptionName;
  final int? quantityValue;
  final int quantityScale;
  final int baseQuantityPerUnit;
  final String baseUnitLabel;
  final int? unitPriceCentavos;

  int get effectiveQuantityValue => quantityValue ?? quantity;
  int get totalBaseQuantity {
    final multiplied = effectiveQuantityValue * baseQuantityPerUnit;
    if (quantityScale <= 0 || multiplied % quantityScale != 0) {
      throw ArgumentError('Quantity cannot be represented in the base unit.');
    }
    return multiplied ~/ quantityScale;
  }

  int lineTotalCentavos(int fallbackPrice) {
    final price = unitPriceCentavos ?? fallbackPrice;
    final numerator = price * effectiveQuantityValue;
    return (numerator + quantityScale ~/ 2) ~/ quantityScale;
  }
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
