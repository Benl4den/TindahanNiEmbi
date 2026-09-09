import 'package:flutter/material.dart';

import '../../../repositories/category_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/special_inventory_repository.dart';
import '../../../services/product_photo_service.dart';
import '../../../widgets/app_state_view.dart';
import 'selecta_screen.dart';

class ManagedBrandsScreen extends StatefulWidget {
  const ManagedBrandsScreen({
    super.key,
    required this.special,
    required this.products,
    required this.inventory,
    required this.categories,
    required this.photoService,
  });
  final SpecialInventoryRepository special;
  final ProductRepository products;
  final InventoryRepository inventory;
  final CategoryRepository categories;
  final ProductPhotoService photoService;

  @override
  State<ManagedBrandsScreen> createState() => _ManagedBrandsScreenState();
}

class _ManagedBrandsScreenState extends State<ManagedBrandsScreen> {
  Future<void> _add() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Managed Brand'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Brand name'),
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

  void _open(InventoryGroup group) {
    Navigator.push(
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
        ),
      ),
    ).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Managed Brands'),
          Text(
            'Organize supplier and branded product groups',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      actions: [
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
            title: 'Could not load managed brands',
            onAction: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) {
          return const AppLoadingView(label: 'Loading managed brands…');
        }
        if (snapshot.data!.isEmpty) {
          return AppStateView.empty(
            title: 'No managed brands yet',
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
                          '${snapshot.data!.length} managed brands',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.data!.fold<int>(0, (n, x) => n + x.productCount)} products across brands • ${snapshot.data!.fold<int>(0, (n, x) => n + x.lowStockCount + x.outOfStockCount)} need restock',
                        ),
                        const Text(
                          'Keep each brand’s products and stock needs together. Open a brand to manage its catalog or add a new brand as your store grows.',
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
                          mainAxisExtent: 190,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                    itemCount: snapshot.data!.length + 1,
                    itemBuilder: (_, index) {
                      if (index == snapshot.data!.length) {
                        return Card(
                          child: InkWell(
                            onTap: _add,
                            borderRadius: BorderRadius.circular(12),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline, size: 36),
                                SizedBox(height: 12),
                                Text('Add Brand'),
                                SizedBox(height: 6),
                                Text('Build your next product collection'),
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
                                      child: Icon(
                                        group.code == 'SELECTA'
                                            ? Icons.icecream_outlined
                                            : Icons.sell_outlined,
                                      ),
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
                                                  fontWeight: FontWeight.w800,
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
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _status(
                                      '${summary.lowStockCount} low stock',
                                      Icons.warning_amber_rounded,
                                      Colors.orange,
                                    ),
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
