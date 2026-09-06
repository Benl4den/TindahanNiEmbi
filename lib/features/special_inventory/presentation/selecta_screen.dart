import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../models/product.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/product_unit_repository.dart';
import '../../inventory/presentation/package_stock_in_dialog.dart';
import '../../../repositories/special_inventory_repository.dart';
import '../../../services/product_photo_service.dart';
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
    this.groupCode = 'SELECTA',
    this.groupName = 'Selecta',
    this.lockFrozenCategory = true,
  });
  final SpecialInventoryRepository special;
  final ProductRepository products;
  final InventoryRepository inventory;
  final CategoryRepository categories;
  final ProductPhotoService photoService;
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
              return GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 440,
                  mainAxisExtent: 248,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: s.data!.length,
                itemBuilder: (_, i) {
                  final p = s.data![i],
                      out = p.currentQuantity == 0,
                      low = !out && p.currentQuantity <= p.minimumStockLevel;
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
                                placeholderIcon: Icons.icecream_outlined,
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
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  '₱${(p.sellingPriceCentavos / 100).toStringAsFixed(2)}',
                                ),
                                Text(
                                  'Stock ${productQuantityText(p, p.currentQuantity)}  •  Minimum ${productQuantityText(p, p.minimumStockLevel)}',
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
                                const SizedBox(height: 6),
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
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Wrap(
                                        children: [
                                          TextButton(
                                            onPressed: () => _remove(p),
                                            child: const Text('Remove'),
                                          ),
                                          TextButton.icon(
                                            onPressed: () => _edit(p),
                                            icon: const Icon(
                                              Icons.edit,
                                              size: 18,
                                            ),
                                            label: const Text('Edit'),
                                          ),
                                        ],
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
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}
