import 'package:flutter/material.dart';

import '../../../repositories/category_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/special_inventory_repository.dart';
import '../../../repositories/brand_analytics_repository.dart';
import '../../../services/feature_access_service.dart';
import '../../../services/product_photo_service.dart';
import '../../../widgets/feature_access_builder.dart';
import '../../../widgets/pro_feature_preview.dart';
import '../../../widgets/pro_overview_panel.dart';
import '../../../core/formatters/number_format.dart';
import '../../../widgets/app_state_view.dart';
import '../../help/help_button.dart';
import '../../help/help_content.dart';
import 'selecta_screen.dart';

class ManagedBrandsScreen extends StatefulWidget {
  const ManagedBrandsScreen({
    super.key,
    required this.special,
    required this.products,
    required this.inventory,
    required this.categories,
    required this.photoService,
    required this.analytics,
    required this.access,
  });
  final SpecialInventoryRepository special;
  final ProductRepository products;
  final InventoryRepository inventory;
  final CategoryRepository categories;
  final ProductPhotoService photoService;
  final BrandAnalyticsRepository analytics;
  final FeatureAccessService access;

  @override
  State<ManagedBrandsScreen> createState() => _ManagedBrandsScreenState();
}

class _ManagedBrandsScreenState extends State<ManagedBrandsScreen> {
  bool _openingBrand = false;
  String _search = '';
  String _filter = 'All';
  String _sort = 'Name';
  Future<
    ({
      List<ManagedBrandSummary> brands,
      Map<int, ({int sales, int profit})> totals,
    })
  >?
  _brandFuture;

  void _refreshBrands() {
    if (mounted) setState(() => _brandFuture = _brandData());
  }

  Future<
    ({
      List<ManagedBrandSummary> brands,
      Map<int, ({int sales, int profit})> totals,
    })
  >
  _brandData() async {
    final brands = await widget.special.managedBrandSummaries();
    final totals = await widget.analytics.totalsByBrand();
    return (brands: brands, totals: totals);
  }

  Future<void> _add() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.sell_outlined),
        title: const Text('Add Brand'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Brand name',
              helperText: 'Use a name that is easy to recognize.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.special.createBrand(name);
      _refreshBrands();
    }
  }

  Future<void> _open(InventoryGroup group) async {
    if (_openingBrand) return;
    _openingBrand = true;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SelectaScreen(
            special: widget.special,
            products: widget.products,
            inventory: widget.inventory,
            categories: widget.categories,
            photoService: widget.photoService,
            groupCode: group.code,
            groupName: group.name,
            lockFrozenCategory: group.code == 'SELECTA',
            analytics: widget.analytics,
            access: widget.access,
          ),
        ),
      );
      _refreshBrands();
    } finally {
      _openingBrand = false;
    }
  }

  @override
  Widget build(BuildContext context) => FeatureAccessBuilder(
    access: widget.access,
    feature: ProFeature.managedBrandAnalytics,
    builder: (context, allowed) => allowed
        ? _buildPro(context)
        : Scaffold(
            appBar: AppBar(
              title: _headerTitle,
              actions: const [HelpButton(topic: HelpTopicId.brands)],
            ),
            body: const ProFeaturePreview(
              title: 'Understand your brands better',
              description: 'Organize products by brand and see how each brand contributes to your store.',
              icon: Icons.sell_outlined,
              metrics: ['Brand Sales', 'Brand Profit', 'Total Products'],
              benefits: [
                'Manage individual brands',
                'Assign products to brands',
                'Track brand sales and profit',
                'See brand performance',
                'Compare which brands help you earn more',
              ],
            ),
          ),
  );

  static const _headerTitle = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Brands'),
      Text(
        'Track each brand’s products, stock, and sales in one place',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
      ),
    ],
  );

  Widget _buildPro(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: _headerTitle,
      actions: [
        const HelpButton(topic: HelpTopicId.brands),
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Add Brand'),
          ),
        ),
      ],
    ),
    body: FutureBuilder<({List<ManagedBrandSummary> brands, Map<int, ({int sales, int profit})> totals})>(
      future: _brandFuture ??= _brandData(),
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return AppStateView.error(
            title: 'Could not load brands',
            onAction: _refreshBrands,
          );
        }
        if (!snapshot.hasData) {
          return const AppLoadingView(label: 'Loading brands…');
        }
        final allBrands = snapshot.data!.brands;
        final totals = snapshot.data!.totals;
        if (allBrands.isEmpty) {
          return AppStateView.empty(
            title: 'No brands yet',
            message: 'Create a brand to organize products and see brand-level performance.',
            actionLabel: 'Add Brand',
            onAction: _add,
          );
        }
        final brands = allBrands.where((brand) {
          final matchesSearch = brand.group.name.toLowerCase().contains(
            _search,
          );
          final matchesFilter = _filter == 'All' || brand.productCount > 0;
          return matchesSearch && matchesFilter;
        }).toList();
        brands.sort(
          (a, b) => switch (_sort) {
            'Sales' => (totals[b.group.id]?.sales ?? 0).compareTo(
              totals[a.group.id]?.sales ?? 0,
            ),
            'Profit' => (totals[b.group.id]?.profit ?? 0).compareTo(
              totals[a.group.id]?.profit ?? 0,
            ),
            _ => a.group.name.toLowerCase().compareTo(
              b.group.name.toLowerCase(),
            ),
          },
        );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: ProOverviewPanel(
                      title: 'Brand Overview',
                      subtitle: 'A summary of your brand performance.',
                      metrics: [
                        ProOverviewMetric(
                          'Total Brand Sales',
                          standardMoney(
                            totals.values.fold<int>(0, (n, x) => n + x.sales),
                          ),
                          Icons.sell_outlined,
                          Theme.of(context).colorScheme.primary,
                        ),
                        ProOverviewMetric(
                          'Total Brand Profit',
                          standardMoney(
                            totals.values.fold<int>(0, (n, x) => n + x.profit),
                          ),
                          Icons.analytics_outlined,
                          Theme.of(context).colorScheme.tertiary,
                        ),
                        ProOverviewMetric(
                          'Brands',
                          '${allBrands.length}',
                          Icons.inventory_2_outlined,
                          Theme.of(context).colorScheme.secondary,
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 340,
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search brands...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (value) => setState(
                              () => _search = value.trim().toLowerCase(),
                            ),
                          ),
                        ),
                        DropdownButton<String>(
                          value: _filter,
                          items: const [
                            DropdownMenuItem(
                              value: 'All',
                              child: Text('Filter: All'),
                            ),
                            DropdownMenuItem(
                              value: 'With products',
                              child: Text('With products'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _filter = value ?? 'All'),
                        ),
                        DropdownButton<String>(
                          value: _sort,
                          items: const [
                            DropdownMenuItem(
                              value: 'Name',
                              child: Text('Sort: Name'),
                            ),
                            DropdownMenuItem(
                              value: 'Sales',
                              child: Text('Sort: Sales'),
                            ),
                            DropdownMenuItem(
                              value: 'Profit',
                              child: Text('Sort: Profit'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _sort = value ?? 'Name'),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${brands.length} ${brands.length == 1 ? 'brand' : 'brands'}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final products = brands.fold<int>(
                              0,
                              (n, x) => n + x.productCount,
                            );
                            final needsRestock = brands.fold<int>(
                              0,
                              (n, x) => n + x.lowStockCount + x.outOfStockCount,
                            );
                            return Text(
                              needsRestock == 0
                                  ? '$products ${products == 1 ? 'product' : 'products'} across brands • Stock healthy'
                                  : '$products ${products == 1 ? 'product' : 'products'} across brands • $needsRestock need restock',
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    itemCount: brands.length,
                    itemBuilder: (_, index) {
                      final summary = brands[index], group = summary.group;
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _open(group),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 27,
                                      child: Icon(Icons.inventory_2_outlined),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            group.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          Text(
                                            '${summary.productCount} ${summary.productCount == 1 ? 'product' : 'products'}',
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 28,
                                  runSpacing: 8,
                                  children: [
                                    Text(
                                      'Sales  ${standardMoney(totals[group.id]?.sales ?? 0)}',
                                    ),
                                    Text(
                                      'Profit  ${standardMoney(totals[group.id]?.profit ?? 0)}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (summary.lowStockCount == 0 &&
                                    summary.outOfStockCount == 0)
                                  _status(
                                    'Stock healthy',
                                    Icons.verified_outlined,
                                    Theme.of(context).colorScheme.primary,
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      if (summary.lowStockCount > 0)
                                        _status(
                                          '${summary.lowStockCount} low stock',
                                          Icons.warning_amber_rounded,
                                          Colors.orange,
                                        ),
                                      if (summary.outOfStockCount > 0)
                                        _status(
                                          '${summary.outOfStockCount} out',
                                          Icons.error_outline,
                                          Colors.red,
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _status(String label, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
