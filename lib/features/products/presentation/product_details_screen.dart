import 'package:flutter/material.dart';

import '../../../core/formatters/display_labels.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/product.dart';
import '../../../repositories/product_insights_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../services/feature_access_service.dart';
import '../../../widgets/feature_access_builder.dart';
import '../../../widgets/product_image.dart';

class ProductDetailsScreen extends StatefulWidget {
  const ProductDetailsScreen({
    super.key,
    required this.product,
    required this.repository,
    required this.access,
    required this.onEdit,
    this.categoryName,
  });

  final Product product;
  final SqliteProductRepository repository;
  final FeatureAccessService access;
  final VoidCallback onEdit;
  final String? categoryName;

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  late Future<({String name, int baseQuantity})> sellingOption;
  Future<ProductPurchasingSummary>? purchasing;
  Future<ProductInsights>? insights;
  ProductInsightsRange range = ProductInsightsRange.last30Days;

  @override
  void initState() {
    super.initState();
    sellingOption = widget.repository.defaultSellingOption(widget.product);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Product Details'),
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: FeatureAccessBuilder(
      access: widget.access,
      feature: ProFeature.productInsights,
      builder: (context, pro) {
        if (pro) {
          purchasing ??= widget.repository.purchasingSummary(widget.product);
          insights ??= widget.repository.insights.load(widget.product, range);
        } else {
          // Free never requests Pro summaries. Re-entering Pro reloads them.
          purchasing = null;
          insights = null;
        }
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                children: [
                  _identity(context),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  FutureBuilder<({String name, int baseQuantity})>(
                    future: sellingOption,
                    builder: (context, snapshot) =>
                        _pricing(context, pro, snapshot.data),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  pro ? _businessInsights(context) : _lockedInsights(context),
                ],
              ),
            ),
            _footer(context),
          ],
        );
      },
    ),
  );

  Widget _identity(BuildContext context) {
    final product = widget.product;
    final status = product.stockStatus;
    final label = switch (status) {
      ProductStockStatus.inStock => 'In Stock',
      ProductStockStatus.lowStock => 'Low Stock',
      ProductStockStatus.outOfStock => 'Out of Stock',
    };
    final accent = switch (status) {
      ProductStockStatus.inStock => const Color(0xFF52C995),
      ProductStockStatus.lowStock => const Color(0xFFF2B45F),
      ProductStockStatus.outOfStock => const Color(0xFFEC7777),
    };
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 102,
            height: 102,
            child: ProductImage(path: product.photoPath),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.categoryName ?? 'Product',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: widget.onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit Product'),
        ),
      ],
    );
  }

  Widget _pricing(
    BuildContext context,
    bool pro,
    ({String name, int baseQuantity})? option,
  ) {
    final p = widget.product;
    final costUnit = p.defaultPurchasePackageName ?? p.baseUnitLabel;
    final sellingUnit = option?.name ?? p.baseUnitLabel;
    final potential = option == null
        ? null
        : p.currentQuantity * p.sellingPriceCentavos ~/ option.baseQuantity;
    final tiles = <Widget>[
      _metric(
        context,
        Icons.inventory_2_outlined,
        'Current Stock',
        productQuantityText(p, p.currentQuantity),
      ),
      if (pro)
        FutureBuilder<ProductPurchasingSummary>(
          future: purchasing,
          builder: (context, snapshot) => _metric(
            context,
            Icons.payments_outlined,
            'Current Stock Cost',
            snapshot.hasError
                ? 'Unavailable'
                : !snapshot.hasData
                ? 'Loading…'
                : !snapshot.data!.isOwned
                ? 'Supplier-owned'
                : standardMoney(snapshot.data!.currentStockCostCentavos),
            detail:
                snapshot.hasData && snapshot.data!.hasIncompletePurchaseHistory
                ? 'Estimated cost'
                : null,
          ),
        ),
      _metric(
        context,
        Icons.sell_outlined,
        'Current Cost',
        '${standardMoney(p.purchasePriceCentavos)} / $costUnit',
      ),
      _metric(
        context,
        Icons.sell_outlined,
        'Selling Price',
        '${standardMoney(p.sellingPriceCentavos)} / $sellingUnit',
      ),
      if (pro)
        _metric(
          context,
          Icons.bar_chart_outlined,
          'Potential Sales Value',
          potential == null ? 'Loading…' : standardMoney(potential),
          info: 'Current stock valued at the default selling price. Not actual sales.',
        ),
      if (pro)
        FutureBuilder<ProductPurchasingSummary>(
          future: purchasing,
          builder: (context, snapshot) {
            final summary = snapshot.data;
            return _metric(
              context,
              Icons.trending_up,
              'Potential Gross Profit',
              snapshot.hasError
                  ? 'Unavailable'
                  : potential == null || summary == null
                  ? 'Loading…'
                  : !summary.isOwned
                  ? 'Not applicable'
                  : standardMoney(potential - summary.currentStockCostCentavos),
              info: 'Potential sales value minus current owned stock cost; not profit already earned.',
            );
          },
        ),
      _metric(
        context,
        Icons.notifications_none,
        'Low Stock Alert At',
        productQuantityText(p, p.minimumStockLevel),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(
          context,
          Icons.inventory_2_outlined,
          'Stock & Pricing',
          'Key information to manage this product.',
        ),
        const SizedBox(height: 10),
        _grid(tiles, columns: pro ? 3 : 2, height: 76),
      ],
    );
  }

  Widget _lockedInsights(BuildContext context) {
    const gold = Color(0xFFFFD777);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 9,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(Icons.lock_outline, color: gold, size: 29),
              Text(
                'Business Insights',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: gold),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(color: gold, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('See how this product is performing.'),
          const Text(
            'Get sales trends, profit history, stock forecasts, and more with Pro.',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 68,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B634A).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.analytics_outlined,
                  color: Color(0xFF63D3A4),
                  size: 40,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _grid(
                  [
                    _lockedTile(context, 'Total Sold'),
                    _lockedTile(context, 'Total Sales'),
                    _lockedTile(context, 'Gross Profit'),
                  ],
                  columns: 3,
                  height: 72,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('Pro is coming later'),
                  content: const Text(
                    'Subscriptions are not available yet. Your products and records remain available in the Free plan.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              ),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: const Text('Upgrade to Pro'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _businessInsights(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: _sectionHeading(
              context,
              Icons.analytics_outlined,
              'Business Insights',
              'Sales, profit, and stock insights to help you make better decisions.',
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<ProductInsightsRange>(
            value: range,
            items: ProductInsightsRange.values
                .map(
                  (value) =>
                      DropdownMenuItem(value: value, child: Text(value.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                range = value;
                insights = widget.repository.insights.load(
                  widget.product,
                  value,
                );
              });
            },
          ),
        ],
      ),
      const SizedBox(height: 10),
      FutureBuilder<ProductInsights>(
        future: insights,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Could not load business insights. Reopen Product Details to try again.',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final x = snapshot.data!;
          final trend = x.recentRestockUnitCostsCentavos;
          final profit = x.grossProfitCentavos;
          return _grid(
            [
              _insight(
                context,
                Icons.shopping_cart_outlined,
                const Color(0xFF56D59C),
                'Total Sold',
                productQuantityText(widget.product, x.soldBaseQuantity),
              ),
              _insight(
                context,
                Icons.paid_outlined,
                const Color(0xFFD4A6EF),
                'Total Sales',
                standardMoney(x.totalSalesCentavos),
              ),
              _insight(
                context,
                Icons.stacked_line_chart,
                const Color(0xFFF4BA64),
                'Gross Profit Earned',
                profit == null ? 'Cost data missing' : standardMoney(profit),
                detail: profit != null && x.profitEstimated
                    ? 'Estimated from recorded costs'
                    : null,
              ),
              _insight(
                context,
                Icons.pie_chart_outline,
                const Color(0xFF80C8FF),
                'Profit Margin',
                x.profitMargin == null
                    ? 'Cost data missing'
                    : '${standardNumber(x.profitMargin!, maxDecimals: 1)}%',
              ),
              _insight(
                context,
                Icons.calendar_month_outlined,
                const Color(0xFFBDB7FF),
                'Average Daily Sales',
                x.soldBaseQuantity == 0
                    ? 'No sales yet'
                    : _averageQuantity(x.averageDailyBaseQuantity),
              ),
              _insight(
                context,
                Icons.signal_cellular_alt,
                const Color(0xFF65D5B0),
                'Estimated Days of Stock Left',
                x.estimatedDaysOfStock == null
                    ? 'Not enough data'
                    : '${standardNumber(x.estimatedDaysOfStock!, maxDecimals: 1)} days',
                info: 'Current stock divided by average daily sales in the selected period.',
              ),
              _insight(
                context,
                Icons.sync,
                const Color(0xFF65D5B0),
                'Restock Frequency',
                '${x.restockFrequency} ${x.restockFrequency == 1 ? 'time' : 'times'}',
              ),
              _insight(
                context,
                Icons.trending_up,
                const Color(0xFFF4BA64),
                'Purchase Cost Trend',
                trend.isEmpty
                    ? 'No purchase history yet'
                    : trend.map(standardMoney).join(' → '),
                detail: trend.isEmpty
                    ? null
                    : 'Last ${trend.length} ${trend.length == 1 ? 'restock' : 'restocks'} • per ${widget.product.defaultPurchasePackageName ?? widget.product.baseUnitLabel}',
              ),
              _insight(
                context,
                Icons.star_outline,
                const Color(0xFFFFD777),
                'Performance',
                x.performance,
                detail: x.saleCount == 0
                    ? 'No posted sales in this period.'
                    : '${x.saleCount} posted ${x.saleCount == 1 ? 'transaction' : 'transactions'} in this period.',
              ),
            ],
            columns: 3,
            height: 85,
          );
        },
      ),
    ],
  );

  String _averageQuantity(double base) {
    final p = widget.product;
    if (p.baseUnitCode == 'GRAM') {
      return '${standardNumber(base / 1000, maxDecimals: 2)} kg';
    }
    if (p.baseUnitCode == 'MILLILITER') {
      return '${standardNumber(base / 1000, maxDecimals: 2)} L';
    }
    return '${standardNumber(base, maxDecimals: 2)} ${p.baseUnitLabel}${base == 1 ? '' : 's'}';
  }

  Widget _sectionHeading(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary, size: 27),
      const SizedBox(width: 11),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );

  Widget _grid(
    List<Widget> tiles, {
    required int columns,
    required double height,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final count = constraints.maxWidth < 420
          ? 1
          : constraints.maxWidth < 650
          ? 2
          : columns;
      final width = (constraints.maxWidth - (count - 1) * 9) / count;
      return Wrap(
        spacing: 9,
        runSpacing: 8,
        children: tiles
            .map((tile) => SizedBox(width: width, height: height, child: tile))
            .toList(),
      );
    },
  );

  BoxDecoration _panel(BuildContext context) => BoxDecoration(
    color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1A2928)
        : Theme.of(context).colorScheme.surfaceContainerLow,
    border: Border.all(color: Theme.of(context).dividerColor),
    borderRadius: BorderRadius.circular(12),
  );

  Widget _metric(
    BuildContext context,
    IconData icon,
    String label,
    String value, {
    String? info,
    String? detail,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: _panel(context),
    child: Row(
      children: [
        Icon(icon, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (info != null)
                    Tooltip(
                      message: info,
                      child: const Icon(Icons.info_outline, size: 15),
                    ),
                ],
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (detail != null)
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _lockedTile(BuildContext context, String label) => Container(
    padding: const EdgeInsets.all(8),
    decoration: _panel(context),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Row(
          children: [
            Icon(Icons.lock_outline, size: 15, color: Color(0xFFFFD777)),
            SizedBox(width: 5),
            Text('--'),
          ],
        ),
      ],
    ),
  );

  Widget _insight(
    BuildContext context,
    IconData icon,
    Color accent,
    String label,
    String value, {
    String? detail,
    String? info,
  }) => Container(
    padding: const EdgeInsets.all(9),
    decoration: _panel(context),
    child: Row(
      children: [
        Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 22, color: accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (info != null)
                    Tooltip(
                      message: info,
                      child: const Icon(Icons.info_outline, size: 15),
                    ),
                ],
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (detail != null)
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _footer(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actions = <Widget>[
          OutlinedButton.icon(
            onPressed: () => _history(context, purchases: true),
            icon: const Icon(Icons.list_alt_outlined),
            label: const Text('View Purchase History'),
          ),
          OutlinedButton.icon(
            onPressed: () => _history(context, purchases: false),
            icon: const Icon(Icons.history),
            label: const Text('Stock Movement History'),
          ),
        ];
        final close = OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        );
        if (constraints.maxWidth < 650) {
          return Wrap(spacing: 8, runSpacing: 8, children: [...actions, close]);
        }
        return Row(children: [...actions, const Spacer(), close]);
      },
    ),
  );

  Future<void> _history(BuildContext context, {required bool purchases}) async {
    final title = purchases ? 'Purchase History' : 'Stock Movement History';
    final List<Object> rows = purchases
        ? await widget.repository.purchaseHistory(widget.product.id)
        : await widget.repository.stockMovementHistory(widget.product.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 560,
          height: 420,
          child: rows.isEmpty
              ? const Center(child: Text('No history recorded yet.'))
              : ListView.separated(
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
                        '${movement.quantityChange > 0 ? '+' : '-'}${productQuantityText(widget.product, movement.quantityChange.abs())}',
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
