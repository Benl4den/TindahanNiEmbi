class Consignor {
  const Consignor({
    required this.id,
    required this.name,
    this.contactDetails,
    this.defaultCategoryId,
    required this.isArchived,
  });
  final int id;
  final String name;
  final String? contactDetails;
  final int? defaultCategoryId;
  final bool isArchived;
  factory Consignor.fromMap(Map<String, Object?> x) => Consignor(
    id: x['id']! as int,
    name: x['name']! as String,
    contactDetails: x['contact_details'] as String?,
    defaultCategoryId: x['default_category_id'] as int?,
    isArchived: x['is_archived'] == 1,
  );
}

class ConsignmentReceiptDraft {
  const ConsignmentReceiptDraft({
    required this.consignorId,
    required this.productId,
    required this.boxes,
    required this.unitsPerBox,
    required this.unitCostCentavos,
    required this.sellingPriceCentavos,
    this.supplierCostBasisQuantity = 1,
    this.packageName,
    this.baseUnitLabel,
    this.priceUnitName,
    this.notes,
  });
  final int consignorId,
      productId,
      boxes,
      unitsPerBox,
      unitCostCentavos,
      sellingPriceCentavos;
  final int supplierCostBasisQuantity;
  final String? packageName, baseUnitLabel, priceUnitName;
  final String? notes;
  int get totalUnits => boxes * unitsPerBox;
  int get consignedValueCentavos => totalUnits * unitCostCentavos;
  int costForQuantity(int quantity) =>
      (quantity * unitCostCentavos + supplierCostBasisQuantity ~/ 2) ~/
      supplierCostBasisQuantity;
  int get exactConsignedValueCentavos => costForQuantity(totalUnits);
  int get marginPerUnitCentavos => sellingPriceCentavos - unitCostCentavos;
}

class ConsignmentSummary {
  const ConsignmentSummary({
    required this.payableCentavos,
    required this.remainingUnits,
    required this.inventoryValueCentavos,
    required this.marginCentavos,
  });
  final int payableCentavos,
      remainingUnits,
      inventoryValueCentavos,
      marginCentavos;
}
