import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../core/theme/app_theme.dart';
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
import '../../../widgets/feature_access_builder.dart';
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
  String sort = 'Name';
  String period = 'This Month';
  Future<
    ({List<Product> products, Map<int, OwnedInventoryProductValue> values})
  >?
  _productsFuture;
  Future<
    ({
      Map<String, Object?> selected,
      Map<String, Object?> month,
      ({String name, int units})? top,
    })
  >?
  _performanceFuture;

  void _refresh() => setState(() {
    _productsFuture = null;
    _performanceFuture = null;
  });

  Future<
    ({List<Product> products, Map<int, OwnedInventoryProductValue> values})
  >
  _loadProducts() async => (
    products: await widget.special.products(widget.groupCode),
    values: await widget.inventory.ownedProductValues(),
  );

  Future<
    ({
      Map<String, Object?> selected,
      Map<String, Object?> month,
      ({String name, int units})? top,
    })
  >
  _loadPerformance() async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final from = switch (period) {
      'Last Month' => DateTime(now.year, now.month - 1),
      'All Time' => null,
      _ => monthStart,
    };
    final to = switch (period) {
      'Last Month' => monthStart,
      'All Time' => null,
      _ => nextMonth,
    };
    final selected = await widget.analytics.summary(
      widget.groupCode,
      from: from,
      to: to,
      currentMembersOnly: true,
    );
    final month = period == 'This Month'
        ? selected
        : await widget.analytics.summary(
            widget.groupCode,
            from: monthStart,
            to: nextMonth,
            currentMembersOnly: true,
          );
    final top = await widget.analytics.topProduct(
      widget.groupCode,
      from: from,
      to: to,
      currentMembersOnly: true,
    );
    return (selected: selected, month: month, top: top);
  }

  Future<void> _assign() async {
    final all = await widget.products.searchActive();
    final assigned = await widget.special.products(widget.groupCode);
    if (!mounted) return;
    final assignedIds = assigned.map((p) => p.id).toSet();
    final available = all.where((p) => !assignedIds.contains(p.id)).toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No unassigned products available. Add a new product first.',
          ),
        ),
      );
      return;
    }
    int selected = available.first.id;
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
              items: available
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
      if (mounted) _refresh();
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
      if (mounted) _refresh();
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
    if (saved == true && mounted) _refresh();
  }

  Future<void> _stockIn(Product p) async {
    final saved = await showPackageStockInDialog(
      context: context,
      product: p,
      repository: ProductUnitRepository(widget.inventory.db),
    );
    if (saved && mounted) _refresh();
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

  Widget _panel({
    required String title,
    required String subtitle,
    required Widget child,
    Widget? trailing,
    Widget? titleAction,
    bool showHeader = true,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceContainer,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        ?titleAction,
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                ?trailing,
              ],
            ),
          if (showHeader) const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    String value,
    IconData icon,
    Color accent, {
    String? detail,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: accent.withValues(alpha: .14),
            child: Icon(icon, color: accent, size: 25),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricGrid(List<Widget> cards) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 940
          ? 4
          : box.maxWidth >= 520
          ? 2
          : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cards.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: columns == 4 ? 136 : 150,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemBuilder: (_, index) => cards[index],
      );
    },
  );

  void _showBrandInfo() => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('About brand performance'),
      content: const Text(
        'This dashboard counts posted sales attributed to products currently assigned to the brand. Earlier sales may be included when a product is assigned; older costs are estimates. Removing a product does not delete its sales history. A product linked to multiple brands can appear in each brand’s history.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Widget _periodButton() => PopupMenuButton<String>(
    tooltip: 'Choose performance period',
    onSelected: (value) => setState(() {
      period = value;
      _performanceFuture = null;
    }),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'This Month', child: Text('This Month')),
      PopupMenuItem(value: 'Last Month', child: Text('Last Month')),
      PopupMenuItem(value: 'All Time', child: Text('All Time')),
    ],
    child: Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined, size: 20),
          const SizedBox(width: 10),
          Text(period, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(width: 14),
          const Icon(Icons.keyboard_arrow_down),
        ],
      ),
    ),
  );

  Widget _performancePanels(List<Product> products) => FeatureAccessBuilder(
    access: widget.access,
    feature: ProFeature.managedBrandAnalytics,
    builder: (_, allowed) {
      if (!allowed) return const SizedBox.shrink();
      return FutureBuilder<
        ({
          Map<String, Object?> selected,
          Map<String, Object?> month,
          ({String name, int units})? top,
        })
      >(
        future: _performanceFuture ??= _loadPerformance(),
        builder: (_, snapshot) {
          if (snapshot.hasError) {
            return AppStateView.error(
              title: 'Could not load brand performance',
              actionLabel: 'Try Again',
              onAction: _refresh,
            );
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final data = snapshot.data!;
          final selected = data.selected;
          final sales = selected['sales']! as int;
          final profit = selected['profit']! as int;
          final low = products
              .where((p) => p.stockStatus == ProductStockStatus.lowStock)
              .length;
          final out = products
              .where((p) => p.stockStatus == ProductStockStatus.outOfStock)
              .length;
          final stockLabel = products.isEmpty
              ? 'No products'
              : out > 0
              ? 'Out of Stock'
              : low > 0
              ? 'Low Stock'
              : 'Healthy';
          final stockColor = products.isEmpty
              ? Theme.of(context).colorScheme.onSurface
              : out > 0
              ? context.semanticColors.danger
              : low > 0
              ? context.semanticColors.warning
              : context.semanticColors.success;
          final stockDetail = products.length == 1
              ? '1 product • ${productQuantityText(products.single, products.single.currentQuantity)}'
              : '${products.length} products';
          final margin = sales == 0
              ? '—'
              : '${(profit * 100 / sales).toStringAsFixed(1)}%';
          final primary = Theme.of(context).colorScheme.primary;
          return Column(
            children: [
              _panel(
                title: 'Brand Performance',
                subtitle:
                    'Sales and profit from products assigned to this brand.',
                titleAction: IconButton(
                  tooltip: 'About brand performance',
                  onPressed: _showBrandInfo,
                  icon: const Icon(Icons.info_outline),
                ),
                trailing: _periodButton(),
                child: _metricGrid([
                  _metric(
                    'Sales',
                    standardMoney(sales),
                    Icons.payments_outlined,
                    primary,
                  ),
                  _metric(
                    'Cost of Sold Products',
                    standardMoney(selected['cost']! as int),
                    Icons.shopping_basket_outlined,
                    context.semanticColors.warning,
                  ),
                  _metric(
                    'Gross Profit',
                    standardMoney(profit),
                    Icons.bar_chart_outlined,
                    primary,
                  ),
                  _metric(
                    'Units Sold',
                    '${selected['units']}',
                    Icons.shopping_bag_outlined,
                    Theme.of(context).colorScheme.onSurface,
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              _panel(
                title: 'Performance Insights',
                subtitle: "Key insights about this brand's performance.",
                child: _metricGrid([
                  _metric('Profit Margin', margin, Icons.percent, primary),
                  _metric(
                    'Top Product',
                    data.top?.name ?? 'No sales yet',
                    Icons.emoji_events_outlined,
                    context.semanticColors.warning,
                    detail: data.top == null
                        ? 'In selected period'
                        : '${data.top!.units} units sold',
                  ),
                  _metric(
                    'Sales This Month',
                    standardMoney(data.month['sales']! as int),
                    Icons.bar_chart_outlined,
                    primary,
                  ),
                  _metric(
                    'Stock Health',
                    stockLabel,
                    Icons.inventory_2_outlined,
                    stockColor,
                    detail: stockDetail,
                  ),
                ]),
              ),
            ],
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
      if (mounted) _refresh();
    }
  }

  Widget _topActions() => Wrap(
    spacing: 14,
    runSpacing: 10,
    children: [
      SizedBox(
        height: 56,
        child: OutlinedButton.icon(
          onPressed: _assign,
          icon: const Icon(Icons.link),
          label: const Text('Assign Existing Products'),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
      SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('Add New Product'),
        ),
      ),
    ],
  );

  Widget _filterButton(String label, ProductStockStatus? value) {
    final selected = status == value;
    void onPressed() => setState(() => status = value);
    return SizedBox(
      height: 50,
      child: selected
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.check, size: 19),
              label: Text(label),
            )
          : OutlinedButton(onPressed: onPressed, child: Text(label)),
    );
  }

  Widget _sortButton() => PopupMenuButton<String>(
    tooltip: 'Sort products, currently $sort',
    onSelected: (value) => setState(() => sort = value),
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'Name', child: Text('Name')),
      PopupMenuItem(value: 'Stock', child: Text('Stock')),
      PopupMenuItem(value: 'Price', child: Text('Price')),
    ],
    child: Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tune, size: 20),
          const SizedBox(width: 8),
          Text('Sort', style: Theme.of(context).textTheme.labelLarge),
          const Icon(Icons.keyboard_arrow_down),
        ],
      ),
    ),
  );

  Widget _productsToolbar(int count) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          children: [
            Text(
              'Products in ${widget.groupName}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '$count ${count == 1 ? 'product' : 'products'}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        Text(
          'Manage products assigned to this brand.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
    final search = SizedBox(
      height: 52,
      child: AppSearchField(
        hintText: 'Search ${widget.groupName} products...',
        onChanged: (value) =>
            setState(() => query = value.trim().toLowerCase()),
      ),
    );
    final controls = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _filterButton('All', null),
        _filterButton('Low Stock', ProductStockStatus.lowStock),
        _filterButton('Out of Stock', ProductStockStatus.outOfStock),
        _sortButton(),
      ],
    );
    return LayoutBuilder(
      builder: (_, box) => box.maxWidth >= 1300
          ? Row(
              children: [
                SizedBox(width: 300, child: heading),
                const SizedBox(width: 14),
                Expanded(child: search),
                const SizedBox(width: 12),
                controls,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 12),
                search,
                const SizedBox(height: 10),
                controls,
              ],
            ),
    );
  }

  Widget _productIdentity(Product p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        p.name,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 5),
      Text(
        standardMoney(p.sellingPriceCentavos),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      Text(
        'Stock: ${productQuantityText(p, p.currentQuantity)}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 5),
      StatusBadge(
        label: switch (p.stockStatus) {
          ProductStockStatus.outOfStock => 'Out of Stock',
          ProductStockStatus.lowStock => 'Low Stock',
          _ => 'In Stock',
        },
        status: switch (p.stockStatus) {
          ProductStockStatus.outOfStock => AppStatus.critical,
          ProductStockStatus.lowStock => AppStatus.attention,
          _ => AppStatus.normal,
        },
      ),
    ],
  );

  Widget _productValue(
    String label,
    String value,
    String helper,
    Color color,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 3),
      Text(helper, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  List<Widget> _productMetrics(Product p, OwnedInventoryProductValue? value) {
    final colors = Theme.of(context).colorScheme;
    if (value == null) {
      return [
        _productValue(
          'Current Stock Cost',
          '—',
          'Supplier-owned stock',
          colors.onSurface,
        ),
        _productValue(
          'Potential Sales Value',
          '—',
          'Excluded from owned values',
          colors.primary,
        ),
        _productValue(
          'Potential Gross Profit',
          '—',
          'Excluded from owned values',
          context.semanticColors.warning,
        ),
      ];
    }
    final quantity = productQuantityText(p, p.currentQuantity);
    final packageSize = p.defaultPurchaseBaseQuantity ?? 1;
    final costPerUnit =
        (p.purchasePriceCentavos + packageSize ~/ 2) ~/ packageSize;
    final costHelper =
        p.currentQuantity * costPerUnit == value.currentStockCostCentavos
        ? '$quantity × ${standardMoney(costPerUnit)}'
        : 'Current owned-stock valuation';
    final salesHelper = '$quantity × ${standardMoney(p.sellingPriceCentavos)}';
    final profitPerUnit = p.sellingPriceCentavos - costPerUnit;
    final profitHelper =
        p.currentQuantity * profitPerUnit == value.potentialGrossProfitCentavos
        ? '$quantity × ${standardMoney(profitPerUnit)}'
        : 'Potential sales − stock cost';
    return [
      _productValue(
        'Current Stock Cost',
        standardMoney(value.currentStockCostCentavos),
        costHelper,
        colors.onSurface,
      ),
      _productValue(
        'Potential Sales Value',
        standardMoney(value.potentialSalesValueCentavos),
        salesHelper,
        colors.primary,
      ),
      _productValue(
        'Potential Gross Profit',
        standardMoney(value.potentialGrossProfitCentavos),
        profitHelper,
        context.semanticColors.warning,
      ),
    ];
  }

  Widget _productActions(Product p) => Wrap(
    spacing: 10,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      SizedBox(
        height: 50,
        child: OutlinedButton.icon(
          onPressed: () => _stockIn(p),
          icon: const Icon(Icons.add_circle_outline, size: 19),
          label: const Text('Stock In'),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Theme.of(context).colorScheme.primary),
          ),
        ),
      ),
      SizedBox(
        height: 50,
        child: OutlinedButton.icon(
          onPressed: () => _saleHistory(p),
          icon: const Icon(Icons.bar_chart_outlined, size: 19),
          label: const Text('Sale History'),
        ),
      ),
      SizedBox(
        height: 50,
        width: 50,
        child: PopupMenuButton<String>(
          tooltip: 'More product actions',
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            if (action == 'edit') _edit(p);
            if (action == 'history') _saleHistory(p);
            if (action == 'remove') _remove(p);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit Product'),
                dense: true,
              ),
            ),
            const PopupMenuItem(
              value: 'history',
              child: ListTile(
                leading: Icon(Icons.bar_chart_outlined),
                title: Text('View Sale History'),
                dense: true,
              ),
            ),
            PopupMenuItem(
              value: 'remove',
              child: ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: context.semanticColors.danger,
                ),
                title: Text(
                  'Remove from ${widget.groupName}',
                  style: TextStyle(color: context.semanticColors.danger),
                ),
                dense: true,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _productRow(Product p, OwnedInventoryProductValue? value) {
    final metrics = _productMetrics(p, value);
    final border = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (_, box) {
          if (box.maxWidth < 1180) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _productIdentity(p),
                const Divider(height: 24),
                LayoutBuilder(
                  builder: (_, inner) {
                    final columns = inner.maxWidth >= 760
                        ? 3
                        : inner.maxWidth >= 490
                        ? 2
                        : 1;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final metric in metrics)
                          SizedBox(
                            width:
                                (inner.maxWidth - 14 * (columns - 1)) / columns,
                            child: metric,
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _productActions(p),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 22, child: _productIdentity(p)),
              for (final metric in metrics) ...[
                Container(
                  width: 1,
                  height: 100,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: border,
                ),
                Expanded(flex: 18, child: metric),
              ],
              const SizedBox(width: 12),
              _productActions(p),
            ],
          );
        },
      ),
    );
  }

  Widget _productsPanel(
    List<Product> all,
    Map<int, OwnedInventoryProductValue> values,
  ) {
    final needle = query.trim().toLowerCase();
    final visible = all
        .where(
          (p) =>
              (needle.isEmpty || p.name.toLowerCase().contains(needle)) &&
              (status == null || p.stockStatus == status),
        )
        .toList();
    visible.sort(
      (a, b) => switch (sort) {
        'Stock' => a.currentQuantity.compareTo(b.currentQuantity),
        'Price' => a.sellingPriceCentavos.compareTo(b.sellingPriceCentavos),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      },
    );
    return _panel(
      title: 'Products in ${widget.groupName}',
      subtitle: 'Manage products assigned to this brand.',
      showHeader: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _productsToolbar(all.length),
          const SizedBox(height: 14),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Text(
                    all.isEmpty
                        ? 'No products assigned to ${widget.groupName} yet.'
                        : 'No matching products found.',
                  ),
                  if (all.isEmpty) ...[
                    const SizedBox(height: 12),
                    _topActions(),
                  ],
                ],
              ),
            )
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _productRow(visible[i], values[visible[i].id]),
            ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.groupName), toolbarHeight: 64),
    body:
        FutureBuilder<
          ({
            List<Product> products,
            Map<int, OwnedInventoryProductValue> values,
          })
        >(
          future: _productsFuture ??= _loadProducts(),
          builder: (_, snapshot) {
            if (snapshot.hasError) {
              return AppStateView.error(
                title: 'Could not load ${widget.groupName}',
                actionLabel: 'Try Again',
                onAction: _refresh,
              );
            }
            if (!snapshot.hasData) {
              return AppLoadingView(label: 'Loading ${widget.groupName}…');
            }
            final data = snapshot.data!;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (_, box) => box.maxWidth >= 760
                        ? Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.groupName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    Text(
                                      widget.lockFrozenCategory
                                          ? 'Ice cream and frozen treats'
                                          : 'Manage this brand and its products',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge,
                                    ),
                                  ],
                                ),
                              ),
                              _topActions(),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.groupName,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              Text(
                                widget.lockFrozenCategory
                                    ? 'Ice cream and frozen treats'
                                    : 'Manage this brand and its products',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 12),
                              _topActions(),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  _performancePanels(data.products),
                  const SizedBox(height: 14),
                  _productsPanel(data.products, data.values),
                ],
              ),
            );
          },
        ),
  );
}
