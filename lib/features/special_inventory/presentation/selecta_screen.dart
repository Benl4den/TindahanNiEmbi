import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/product.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/special_inventory_repository.dart';
import '../../../services/product_photo_service.dart';
import '../../products/presentation/product_form_screen.dart';

class SelectaScreen extends StatefulWidget {
  const SelectaScreen({
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
          title: const Text('Assign Selecta Product'),
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
      await widget.special.assign(selected, 'SELECTA');
      if (mounted) setState(() {});
    }
  }

  Future<void> _create() async {
    final categories = await widget.categories.getActive();
    if (!mounted) return;
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
            onSaved: (value) => created = value,
          ),
        ),
      ),
    );
    if (saved == true && created != null) {
      await widget.special.assign(created!.id, 'SELECTA');
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
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Stock In — ${p.name}'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Stock In'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.inventory.stockIn(
        productId: p.id,
        quantity: int.tryParse(controller.text) ?? 0,
      );
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Selecta Products'),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('Add Selecta Product'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: OutlinedButton(
            onPressed: _assign,
            child: const Text('Assign Existing'),
          ),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search Selecta products',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              ...[
                (null, 'All'),
                (ProductStockStatus.lowStock, 'Low Stock'),
                (ProductStockStatus.outOfStock, 'Out of Stock'),
              ].map(
                (x) => ChoiceChip(
                  label: Text(x.$2),
                  selected: status == x.$1,
                  onSelected: (_) => setState(() => status = x.$1),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Product>>(
            future: widget.special.products(
              'SELECTA',
              query: query,
              status: status,
            ),
            builder: (_, s) {
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.data!.isEmpty) {
                return const Center(
                  child: Text(
                    'No Selecta products found.',
                    style: TextStyle(fontSize: 20),
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 480,
                  mainAxisExtent: 180,
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
                              width: 110,
                              height: 110,
                              child:
                                  p.photoPath.isNotEmpty &&
                                      File(p.photoPath).existsSync()
                                  ? Image.file(
                                      File(p.photoPath),
                                      fit: BoxFit.cover,
                                    )
                                  : const ColoredBox(
                                      color: Color(0xffeeeeee),
                                      child: Icon(Icons.icecream, size: 48),
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
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  '₱${(p.sellingPriceCentavos / 100).toStringAsFixed(2)}',
                                ),
                                Text(
                                  'Stock ${p.currentQuantity}  •  Minimum ${p.minimumStockLevel}',
                                ),
                                Text(
                                  out
                                      ? 'Out of Stock'
                                      : low
                                      ? 'Low Stock'
                                      : 'In Stock',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: out
                                        ? Colors.red
                                        : low
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _stockIn(p),
                                      icon: const Icon(Icons.add_box),
                                      label: const Text('Stock In'),
                                    ),
                                    IconButton(
                                      onPressed: () => _edit(p),
                                      icon: const Icon(Icons.edit),
                                      tooltip: 'Edit Product',
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
