enum BaseUnit {
  piece('PIECE', 'piece'),
  stick('STICK', 'stick'),
  bottle('BOTTLE', 'bottle'),
  sachet('SACHET', 'sachet'),
  gram('GRAM', 'g'),
  milliliter('MILLILITER', 'mL');

  const BaseUnit(this.code, this.label);
  final String code;
  final String label;
}

class PurchasePackageDraft {
  const PurchasePackageDraft({
    required this.name,
    required this.baseQuantity,
    this.isDefault = false,
  });
  final String name;
  final int baseQuantity;
  final bool isDefault;
}

class SellingOptionDraft {
  const SellingOptionDraft({
    required this.name,
    required this.baseQuantity,
    required this.priceCentavos,
    this.isDefault = false,
  });
  final String name;
  final int baseQuantity;
  final int priceCentavos;
  final bool isDefault;
}

class ProductUnitConfiguration {
  const ProductUnitConfiguration({
    required this.baseUnit,
    required this.purchasePackages,
    required this.sellingOptions,
  });
  final BaseUnit baseUnit;
  final List<PurchasePackageDraft> purchasePackages;
  final List<SellingOptionDraft> sellingOptions;
}

class ProductUnitPreset {
  const ProductUnitPreset._();

  static ProductUnitConfiguration forCategory(
    String categoryName,
    int defaultSellingPriceCentavos,
  ) {
    final name = categoryName.trim().toLowerCase().replaceAll(
      RegExp(r'[- ]+'),
      ' ',
    );
    if (name == 'rice') {
      return ProductUnitConfiguration(
        baseUnit: BaseUnit.gram,
        purchasePackages: const [
          PurchasePackageDraft(
            name: '25 kg Sack',
            baseQuantity: 25000,
            isDefault: true,
          ),
          PurchasePackageDraft(name: '50 kg Sack', baseQuantity: 50000),
        ],
        sellingOptions: [
          SellingOptionDraft(
            name: '1 kg',
            baseQuantity: 1000,
            priceCentavos: defaultSellingPriceCentavos,
            isDefault: true,
          ),
        ],
      );
    }
    if (name == 'soft drinks' || name == 'softdrinks') {
      return ProductUnitConfiguration(
        baseUnit: BaseUnit.bottle,
        purchasePackages: const [
          PurchasePackageDraft(name: 'Case', baseQuantity: 24, isDefault: true),
        ],
        sellingOptions: [
          SellingOptionDraft(
            name: 'Bottle',
            baseQuantity: 1,
            priceCentavos: defaultSellingPriceCentavos,
            isDefault: true,
          ),
          SellingOptionDraft(
            name: 'Case',
            baseQuantity: 24,
            priceCentavos: defaultSellingPriceCentavos,
          ),
        ],
      );
    }
    if (name == 'cigarettes' || name == 'cigarettes & tobacco') {
      return ProductUnitConfiguration(
        baseUnit: BaseUnit.stick,
        purchasePackages: const [
          PurchasePackageDraft(name: 'Pack', baseQuantity: 20, isDefault: true),
        ],
        sellingOptions: [
          SellingOptionDraft(
            name: 'Stick',
            baseQuantity: 1,
            priceCentavos: defaultSellingPriceCentavos,
            isDefault: true,
          ),
          SellingOptionDraft(
            name: 'Pack',
            baseQuantity: 20,
            priceCentavos: defaultSellingPriceCentavos,
          ),
        ],
      );
    }
    if (name == 'cooking oil') {
      return ProductUnitConfiguration(
        baseUnit: BaseUnit.milliliter,
        purchasePackages: const [
          PurchasePackageDraft(
            name: 'Gallon',
            baseQuantity: 3785,
            isDefault: true,
          ),
        ],
        sellingOptions: [
          SellingOptionDraft(
            name: 'Half Lapad',
            baseQuantity: 125,
            priceCentavos: defaultSellingPriceCentavos,
            isDefault: true,
          ),
          SellingOptionDraft(
            name: 'Lapad',
            baseQuantity: 250,
            priceCentavos: defaultSellingPriceCentavos,
          ),
        ],
      );
    }
    return ProductUnitConfiguration(
      baseUnit: BaseUnit.piece,
      purchasePackages: const [
        PurchasePackageDraft(name: 'Piece', baseQuantity: 1, isDefault: true),
      ],
      sellingOptions: [
        SellingOptionDraft(
          name: 'Piece',
          baseQuantity: 1,
          priceCentavos: defaultSellingPriceCentavos,
          isDefault: true,
        ),
      ],
    );
  }
}

class PurchasePackage {
  const PurchasePackage({
    required this.id,
    required this.productId,
    required this.name,
    required this.baseQuantity,
    required this.isDefault,
  });
  final int id, productId, baseQuantity;
  final String name;
  final bool isDefault;
  factory PurchasePackage.fromMap(Map<String, Object?> x) => PurchasePackage(
    id: x['id']! as int,
    productId: x['product_id']! as int,
    name: x['name']! as String,
    baseQuantity: x['base_quantity']! as int,
    isDefault: x['is_default'] == 1,
  );
}

class SellingOption {
  const SellingOption({
    required this.id,
    required this.productId,
    required this.name,
    required this.baseQuantity,
    required this.priceCentavos,
    required this.isDefault,
  });
  final int id, productId, baseQuantity, priceCentavos;
  final String name;
  final bool isDefault;
  factory SellingOption.fromMap(Map<String, Object?> x) => SellingOption(
    id: x['id']! as int,
    productId: x['product_id']! as int,
    name: x['name']! as String,
    baseQuantity: x['base_quantity']! as int,
    priceCentavos: x['price_centavos']! as int,
    isDefault: x['is_default'] == 1,
  );
}
