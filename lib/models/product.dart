import 'product_unit.dart';

enum ProductStockStatus { inStock, lowStock, outOfStock }

class Product {
  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.photoPath,
    required this.purchasePriceCentavos,
    required this.sellingPriceCentavos,
    required this.currentQuantity,
    required this.minimumStockLevel,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
    this.baseUnitCode = 'PIECE',
    this.baseUnitLabel = 'piece',
    this.unitConfiguration,
    this.defaultPurchasePackageName,
    this.defaultPurchaseBaseQuantity,
  });

  final int id;
  final int categoryId;
  final String name;
  final String photoPath;
  final int purchasePriceCentavos;
  final int sellingPriceCentavos;
  final int currentQuantity;
  final int minimumStockLevel;
  final bool isArchived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String baseUnitCode;
  final String baseUnitLabel;
  final ProductUnitConfiguration? unitConfiguration;
  final String? defaultPurchasePackageName;
  final int? defaultPurchaseBaseQuantity;

  ProductStockStatus get stockStatus {
    if (currentQuantity == 0) {
      return ProductStockStatus.outOfStock;
    }
    if (currentQuantity <= minimumStockLevel) {
      return ProductStockStatus.lowStock;
    }
    return ProductStockStatus.inStock;
  }

  factory Product.fromMap(Map<String, Object?> map) => Product(
    id: map['id']! as int,
    categoryId: map['category_id']! as int,
    name: map['name']! as String,
    photoPath: map['photo_path']! as String,
    purchasePriceCentavos: map['purchase_price_centavos']! as int,
    sellingPriceCentavos: map['selling_price_centavos']! as int,
    currentQuantity: map['current_quantity']! as int,
    minimumStockLevel: map['minimum_stock_level']! as int,
    isArchived: map['is_archived'] == 1,
    createdAt: DateTime.parse(map['created_at']! as String),
    updatedAt: DateTime.parse(map['updated_at']! as String),
    baseUnitCode: (map['base_unit_code'] as String?) ?? 'PIECE',
    baseUnitLabel: (map['base_unit_label'] as String?) ?? 'piece',
    defaultPurchasePackageName: map['default_purchase_package_name'] as String?,
    defaultPurchaseBaseQuantity: map['default_purchase_base_quantity'] as int?,
  );
}

class ProductDraft {
  const ProductDraft({
    required this.categoryId,
    required this.name,
    required this.photoPath,
    required this.purchasePriceCentavos,
    required this.sellingPriceCentavos,
    required this.startingQuantity,
    required this.minimumStockLevel,
    this.unitConfiguration,
  });
  final int categoryId;
  final String name;
  final String photoPath;
  final int purchasePriceCentavos;
  final int sellingPriceCentavos;
  final int startingQuantity;
  final int minimumStockLevel;
  final ProductUnitConfiguration? unitConfiguration;
}
