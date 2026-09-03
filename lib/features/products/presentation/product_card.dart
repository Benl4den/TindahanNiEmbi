import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/product.dart';
import '../../../widgets/status_badge.dart';
import '../../../widgets/product_image.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onDetails,
    required this.onEdit,
    required this.onArchive,
    this.categoryName,
    this.inventoryGroups = const [],
  });
  final Product product;
  final VoidCallback onDetails;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final String? categoryName;
  final List<String> inventoryGroups;

  String get _status => switch (product.stockStatus) {
    ProductStockStatus.outOfStock => AppStrings.outOfStock,
    ProductStockStatus.lowStock => AppStrings.lowStock,
    ProductStockStatus.inStock => AppStrings.inStock,
  };

  @override
  Widget build(BuildContext context) {
    final warning = product.stockStatus != ProductStockStatus.inStock;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onDetails,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ProductImage(path: product.photoPath)),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₱${(product.sellingPriceCentavos / 100).toStringAsFixed(2)}  •  Stock: ${product.currentQuantity}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    'Minimum: ${product.minimumStockLevel}${categoryName == null ? '' : ' • $categoryName'}${inventoryGroups.isEmpty ? '' : ' • ${inventoryGroups.join(', ')}'}',
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusBadge(
                      label: _status,
                      status:
                          product.stockStatus == ProductStockStatus.outOfStock
                          ? AppStatus.critical
                          : product.stockStatus == ProductStockStatus.lowStock
                          ? AppStatus.attention
                          : AppStatus.normal,
                      icon: warning
                          ? Icons.warning_amber
                          : Icons.check_circle_outline,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onEdit,
                          child: const Text(AppStrings.edit),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onArchive,
                          child: const Text(AppStrings.archive),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
