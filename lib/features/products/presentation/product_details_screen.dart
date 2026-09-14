import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../core/formatters/display_labels.dart';
import '../../../models/product.dart';
import '../../../repositories/product_repository.dart';
import '../../../widgets/product_image.dart';

class ProductDetailsScreen extends StatelessWidget {
  const ProductDetailsScreen({
    super.key,
    required this.product,
    required this.repository,
    required this.onEdit,
  });
  final Product product;
  final SqliteProductRepository repository;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Product Details')),
    body: FutureBuilder<ProductPurchasingSummary>(
      future: repository.purchasingSummary(product),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final s = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                SizedBox(
                  width: 112,
                  height: 112,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ProductImage(path: product.photoPath),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        product.stockStatus == ProductStockStatus.outOfStock
                            ? 'Out of Stock'
                            : product.stockStatus == ProductStockStatus.lowStock
                            ? 'Low Stock'
                            : 'In Stock',
                      ),
                      Text(
                        'Current stock: ${productQuantityText(product, product.currentQuantity)}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _heading(context, 'PRODUCT OVERVIEW'),
            if (!s.isOwned)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'This is consignment stock. Owned-inventory costs and purchasing totals do not apply.',
                  ),
                ),
              )
            else
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric(
                    'Current Stock',
                    productQuantityText(product, product.currentQuantity),
                  ),
                  _metric(
                    'Current Stock Cost',
                    '${standardMoney(s.currentStockCostCentavos)}${s.hasIncompletePurchaseHistory ? ' • Estimated' : ''}',
                  ),
                  _metric(
                    'Potential Sales Value',
                    standardMoney(s.potentialSalesValueCentavos),
                  ),
                  _metric(
                    'Potential Gross Profit',
                    '${standardMoney(s.potentialGrossProfitCentavos)}${s.hasIncompletePurchaseHistory ? ' • Estimated' : ''}',
                  ),
                ],
              ),
            const SizedBox(height: 24),
            _heading(context, 'PURCHASING'),
            if (s.isOwned)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric(
                    'Lifetime Quantity Purchased',
                    productQuantityText(product, s.lifetimeQuantity),
                  ),
                  _metric(
                    'Lifetime Purchased Cost',
                    '${standardMoney(s.lifetimePurchasedCostCentavos)}${s.hasIncompletePurchaseHistory ? ' • Estimated' : ''}',
                  ),
                  _metric(
                    'Average Purchase Cost',
                    '${standardMoney(_displayAverage(s))}/$_averageUnit${s.hasIncompletePurchaseHistory ? ' • Estimated' : ''}',
                  ),
                ],
              ),
            if (s.hasIncompletePurchaseHistory)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Purchase cost is missing for ${productQuantityText(product, s.unpricedPurchaseQuantity)}. The latest recorded purchase cost for this product is used as an estimate. Potential sales value is unaffected.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            _heading(context, 'PRICING'),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric(
                  'Current Cost',
                  standardMoney(product.purchasePriceCentavos),
                ),
                _metric(
                  'Selling Price',
                  standardMoney(product.sellingPriceCentavos),
                ),
                _metric(
                  'Low Stock Alert At',
                  productQuantityText(product, product.minimumStockLevel),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (s.isOwned)
              OutlinedButton.icon(
                onPressed: () => _history(context, purchases: true),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Purchase History'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _history(context, purchases: false),
              icon: const Icon(Icons.history),
              label: const Text('Stock Movement History'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Product'),
            ),
          ],
        );
      },
    ),
  );

  String get _averageUnit =>
      product.baseUnitCode == 'GRAM' ? 'kg' : product.baseUnitLabel;
  int _displayAverage(ProductPurchasingSummary summary) =>
      product.baseUnitCode == 'GRAM'
      ? summary.averagePurchaseCostCentavos * 1000
      : summary.averagePurchaseCostCentavos;
  Widget _heading(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(label, style: Theme.of(context).textTheme.titleMedium),
  );
  Widget _metric(String label, String value) => SizedBox(
    width: 230,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _history(BuildContext context, {required bool purchases}) async {
    final title = purchases ? 'Purchase History' : 'Stock Movement History';
    final List<Object> rows = purchases
        ? await repository.purchaseHistory(product.id)
        : await repository.stockMovementHistory(product.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          height: 420,
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, i) {
              final row = rows[i];
              if (row is ProductPurchaseRecord) {
                return ListTile(
                  title: Text(
                    '${row.quantity} ${row.unit} • ${standardMoney(row.totalCostCentavos)}',
                  ),
                  subtitle: Text(
                    MaterialLocalizations.of(dialog)
                        .formatMediumDate(row.occurredAt.toLocal()),
                  ),
                );
              }
              final movement = row as ProductStockMovementRecord;
              return ListTile(
                title: Text(DisplayLabels.movement(movement.type)),
                subtitle: Text(
                  MaterialLocalizations.of(dialog)
                      .formatMediumDate(movement.occurredAt.toLocal()),
                ),
                trailing: Text(
                  '${movement.quantityChange > 0 ? '+' : ''}${productQuantityText(product, movement.quantityChange.abs())}',
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
