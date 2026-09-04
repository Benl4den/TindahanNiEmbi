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
      title: const Text('Managed Brands'),
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
    body: FutureBuilder<List<InventoryGroup>>(
      future: widget.special.managedBrands(),
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
            title: 'No managed brands',
            actionLabel: 'Add Brand',
            onAction: _add,
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 360,
            mainAxisExtent: 130,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: snapshot.data!.length,
          itemBuilder: (_, index) {
            final group = snapshot.data![index];
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _open(group),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 27,
                        child: Icon(
                          group.code == 'SELECTA'
                              ? Icons.icecream_outlined
                              : Icons.sell_outlined,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          group.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
