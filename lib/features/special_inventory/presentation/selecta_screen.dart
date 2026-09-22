import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../models/product.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/brand_analytics_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/product_unit_repository.dart';
import '../../inventory/presentation/package_stock_in_dialog.dart';
import '../../../repositories/special_inventory_repository.dart';
import '../../../services/product_photo_service.dart';
import '../../../services/feature_access_service.dart';
import '../../../widgets/app_state_view.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/status_badge.dart';
import '../../../widgets/product_image.dart';
import '../../products/presentation/product_form_screen.dart';

class SelectaScreen extends StatefulWidget {
  const SelectaScreen({
    super.key,
    required this.special,
    required this.products,
    required this.inventory,
    required this.categories,
    required this.photoService,
    required this.analytics,
    required this.access,
    this.groupCode = 'SELECTA',
    this.groupName = 'Selecta',
    this.lockFrozenCategory = true,
  });
  final SpecialInventoryRepository special;
  final ProductRepository products;
  final InventoryRepository inventory;
  final CategoryRepository categories;
  final ProductPhotoService photoService;
  final BrandAnalyticsRepository analytics;
  final FeatureAccessService access;
  final String groupCode, groupName;
  final bool lockFrozenCategory;
  @override
  State<SelectaScreen> createState() => _SelectaScreenState();
}

class _SelectaScreenState extends State<SelectaScreen> {
  String query = '';
  ProductStockStatus? status;
  Future<void> _assign() async {
    final all = await widget.products.searchActive();
    if (!mounted || all.isEmpty) return;
    int selected = all.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: Text('Assign to ${widget.groupName}'),
          content: SizedBox(
            width: 480,
            child: DropdownButtonFormField<int>(
              initialValue: selected,
              decoration: const InputDecoration(
                labelText: 'Product',
                border: OutlineInputBorder(),
              ),
              items: all
                  .map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                  )
                  .toList(),
              onChanged: (v) => set(() => selected = v!),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.special.assign(selected, widget.groupCode);
      if (mounted) setState(() {});
    }
  }

  Future<void> _create() async {
    final categories = await widget.categories.getActive();
    if (!mounted) return;
    final frozen = categories.where((x) {
      final name = x.name.trim().toLowerCase().replaceAll(
        RegExp(r'[- ]+'),
        ' ',
      );
      return name == 'ice & frozen treats' ||
          name == 'ice cream & frozen treats';
    }).firstOrNull;
    if (widget.lockFrozenCategory && frozen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Active category “Ice & Frozen Treats” is required.'),
        ),
      );
      return;
    }
    Product? created;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 900),
          child: ProductFormScreen(
            repository: widget.products,
            photoService: widget.photoService,
            categories: categories,
            initialCategoryId: widget.lockFrozenCategory ? frozen?.id : null,
            categoryInitiallyLocked: widget.lockFrozenCategory,
            onSaved: (value) => created = value,
          ),
        ),
      ),
    );
    if (saved == true && created != null) {
      await widget.special.assign(created!.id, widget.groupCode);
      if (mounted) setState(() {});
    }
  }

  Future<void> _edit(Product product) async {
    final categories = await widget.categories.getActive();
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 900),
          child: ProductFormScreen(
            repository: widget.products,
            photoService: widget.photoService,
            categories: categories,
            product: product,
          ),
        ),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _stockIn(Product p) async {
    final saved = await showPackageStockInDialog(
      context: context,
      product: p,
      repository: ProductUnitRepository(widget.inventory.db),
    );
    if (saved && mounted) setState(() {});
  }

  Future<void> _saleHistory(Product product) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: ProductImage(path: product.photoPath, borderRadius: 10),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('${product.name} Sales History')),
          ],
        ),
        content: SizedBox(
          width: 620,
          height: 500,
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: widget.special.productSalesHistory(product.id),
            builder: (_, snapshot) {
              if (snapshot.hasError) {
                return const AppStateView.error(
                  title: 'Could not load product sales history',
                  message: 'Close this window and try again.',
                );
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Text(
                  'No completed sales recorded for this product yet.',
                );
              }
              final quantity = rows.fold<int>(
                0,
                (sum, row) => sum + (row['quantity']! as int),
              );
              final total = rows.fold<int>(
                0,
                (sum, row) => sum + (row['line_total_centavos']! as int),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Wrap(
                      spacing: 24,
                      runSpacing: 6,
                      children: [
                        _historyMetric(
                          'Quantity sold',
                          productQuantityText(product, quantity),
                        ),
                        _historyMetric('Sales value', standardMoney(total)),
                        _historyMetric('Completed sales', '${rows.length}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Completed sales only. Cancelled and corrected sales are excluded.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final row = rows[index];
                        final occurredAt = DateTime.parse(
                          row['occurred_at']! as String,
                        ).toLocal();
                        final source = row['source']! as String;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 5,
                          ),
                          leading: Icon(
                            source == 'UTANG sale'
                                ? Icons.people_outline
                                : source == 'GCash sale'
                                ? Icons.account_balance_wallet_outlined
                                : Icons.payments_outlined,
                          ),
                          title: Text(
                            '$source • ${productQuantityText(product, row['quantity']! as int)}',
                          ),
                          subtitle: Text(
                            '${MaterialLocalizations.of(context).formatMediumDate(occurredAt)} • ${TimeOfDay.fromDateTime(occurredAt).format(context)}\nRecorded by ${row['actor_name']! as String}',
                          ),
                          isThreeLine: true,
                          trailing: Text(
                            standardMoney(row['line_total_centavos']! as int),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _historyMetric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
    ],
  );

  Widget _brandMetric(String label, String value, IconData icon) => SizedBox(
    width: 205,
    child: Card(
      color: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: .4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    ),
  );

  Widget _brandOverview() => FutureBuilder<bool>(
    future: widget.access.allows(ProFeature.managedBrandAnalytics),
    builder: (_, gate) {
      if (gate.data != true) return const SizedBox.shrink();
      return FutureBuilder<Map<String, Object?>>(
        future: widget.analytics.summary(widget.groupCode),
        builder: (_, result) {
          if (!result.hasData) {
            return result.hasError
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Could not load brand performance.'),
                  )
                : const LinearProgressIndicator();
          }
          final data = result.data!;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Brand performance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _brandMetric(
                      'Sales',
                      standardMoney(data['sales']! as int),
                      Icons.payments_outlined,
                    ),
                    _brandMetric(
                      'Estimated cost',
                      standardMoney(data['cost']! as int),
                      Icons.inventory_2_outlined,
                    ),
                    _brandMetric(
                      'Estimated gross profit',
                      standardMoney(data['profit']! as int),
                      Icons.trending_up,
                    ),
                    _brandMetric(
                      'Units sold',
                      '${data['units']}',
                      Icons.shopping_bag_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'Posted sales are kept in brand history, including sales made before a product was assigned. Older costs are estimates; a product linked to multiple brands can appear in each brand’s history.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Future<void> _remove(Product product) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from brand?'),
        content: Text(
          '${product.name} will remain in Products, Inventory, Sales, and history. Only its ${widget.groupName} membership will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove from Brand'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.special.remove(product.id, widget.groupCode);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.groupName),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: Text('Add ${widget.groupName} Product'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: IconButton.filledTonal(
            onPressed: _assign,
            tooltip: 'Assign Existing Product',
            icon: const Icon(Icons.playlist_add),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        _brandOverview(),
        Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (_, box) {
              final search = AppSearchField(
                hintText: 'Search ${widget.groupName} products',
                onChanged: (v) => setState(() => query = v),
              );
              final chips =
                  [
                        (null, 'All'),
                        (ProductStockStatus.lowStock, 'Low Stock'),
                        (ProductStockStatus.outOfStock, 'Out of Stock'),
                      ]
                      .map(
                        (x) => ChoiceChip(
                          label: Text(x.$2),
                          selected: status == x.$1,
                          onSelected: (_) => setState(() => status = x.$1),
                        ),
                      )
                      .toList();
              if (box.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    search,
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(spacing: 8, children: chips),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 16),
                  ...chips.map(
                    (chip) => Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: chip,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Product>>(
            future: widget.special.products(
              widget.groupCode,
              query: query,
              status: status,
            ),
            builder: (_, s) {
              if (s.hasError) {
                return AppStateView.error(
                  title: 'Could not load ${widget.groupName} products',
                  actionLabel: 'Try Again',
                  onAction: () => setState(() {}),
                );
              }
              if (!s.hasData) {
                return AppLoadingView(
                  label: 'Loading ${widget.groupName} products…',
                );
              }
              if (s.data!.isEmpty) {
                return AppStateView.empty(
                  title: 'No ${widget.groupName} products found',
                  message: 'Assign an existing product or add a new one.',
                  actionLabel: 'Add Product',
                  onAction: _create,
                );
              }
              return FutureBuilder<Map<int, OwnedInventoryProductValue>>(
                future: widget.inventory.ownedProductValues(),
                builder: (_, values) {
                  if (values.hasError) {
                    return const Center(
                      child: Text(
                        'Could not load product values. Try reopening this brand.',
                      ),
                    );
                  }
                  if (!values.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 440,
                          mainAxisExtent: 430,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: s.data!.length,
                    itemBuilder: (_, i) {
                      final p = s.data![i],
                          out = p.currentQuantity == 0,
                          low =
                              !out && p.currentQuantity <= p.minimumStockLevel;
                      final value = values.data![p.id];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 96,
                                  height: 140,
                                  child: ProductImage(
                                    path: p.photoPath,
                                    placeholderIcon: Icons.inventory_2_outlined,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      p.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    Text(standardMoney(p.sellingPriceCentavos)),
                                    Text(
                                      'Stock ${productQuantityText(p, p.currentQuantity)}',
                                    ),
                                    StatusBadge(
                                      label: out
                                          ? 'Out of Stock'
                                          : low
                                          ? 'Low Stock'
                                          : 'In Stock',
                                      status: out
                                          ? AppStatus.critical
                                          : low
                                          ? AppStatus.attention
                                          : AppStatus.normal,
                                    ),
                                    const SizedBox(height: 10),
                                    if (value == null)
                                      Text(
                                        'Supplier-owned stock • not included in owned inventory values',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      )
                                    else ...[
                                      Text(
                                        'Current Stock Cost  ${standardMoney(value.currentStockCostCentavos)}',
                                      ),
                                      Text(
                                        'Potential Sales Value  ${standardMoney(value.potentialSalesValueCentavos)}',
                                      ),
                                      Text(
                                        'Potential Gross Profit  ${standardMoney(value.potentialGrossProfitCentavos)}',
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          height: 48,
                                          child: FilledButton.tonalIcon(
                                            onPressed: () => _stockIn(p),
                                            icon: const Icon(Icons.add_box),
                                            label: const Text('Stock In'),
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextButton.icon(
                                                onPressed: () =>
                                                    _saleHistory(p),
                                                icon: const Icon(
                                                  Icons.bar_chart_outlined,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                  'Sale History',
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Edit product',
                                              onPressed: () => _edit(p),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Remove from brand',
                                              onPressed: () => _remove(p),
                                              icon: const Icon(
                                                Icons.remove_circle_outline,
                                              ),
                                            ),
                                          ],
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
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
