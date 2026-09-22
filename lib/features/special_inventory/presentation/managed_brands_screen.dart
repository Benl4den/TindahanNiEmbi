import 'package:flutter/material.dart';

import '../../../repositories/category_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/special_inventory_repository.dart';
import '../../../repositories/brand_analytics_repository.dart';
import '../../../services/feature_access_service.dart';
import '../../../services/product_photo_service.dart';
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
      if (mounted) setState(() {});
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
      if (mounted) setState(() {});
    } finally {
      _openingBrand = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Brands'),
          Text(
            'Track each brand’s products, stock, and sales in one place',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
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
    body: FutureBuilder<List<ManagedBrandSummary>>(
      future: widget.special.managedBrandSummaries(),
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return AppStateView.error(
            title: 'Could not load brands',
            onAction: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) {
          return const AppLoadingView(label: 'Loading brands…');
        }
        if (snapshot.data!.isEmpty) {
          return AppStateView.empty(
            title: 'No brands yet',
            actionLabel: 'Add Brand',
            onAction: _add,
          );
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${snapshot.data!.length} ${snapshot.data!.length == 1 ? 'brand' : 'brands'}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final products = snapshot.data!.fold<int>(
                              0,
                              (n, x) => n + x.productCount,
                            );
                            final needsRestock = snapshot.data!.fold<int>(
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
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 410,
                          mainAxisExtent: 192,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: snapshot.data!.length + 1,
                    itemBuilder: (_, index) {
                      if (index == snapshot.data!.length) {
                        return Card(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: .32),
                          child: InkWell(
                            onTap: _add,
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_circle_outline,
                                  size: 36,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Add Brand',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Build your next product collection',
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final summary = snapshot.data![index],
                          group = summary.group;
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
                                const Spacer(),
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
                                const SizedBox(height: 8),
                                Text(
                                  'Open brand products',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    fontWeight: FontWeight.w700,
                                  ),
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
