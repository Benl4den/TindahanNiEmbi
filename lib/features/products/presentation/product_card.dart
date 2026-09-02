import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/product.dart';

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
            Expanded(
              child: Image.file(
                File(product.photoPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFE3E5DF),
                  child: Icon(Icons.image_not_supported_outlined, size: 54),
                ),
              ),
            ),
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
                  Text(
                    _status,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: warning
                          ? Colors.red.shade800
                          : Colors.green.shade800,
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
