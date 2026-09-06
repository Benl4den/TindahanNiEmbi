import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/inventory_movement.dart';
import '../../../models/product.dart';
import '../../../repositories/inventory_repository.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.repository,
    this.openStockIn = false,
    this.allowAdjustment = true,
  });
  final InventoryRepository repository;
  final bool openStockIn;
  final bool allowAdjustment;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<Product>> _products;
  late Future<List<InventoryMovement>> _history;
  late Future<int> _value;
  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.openStockIn) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _chooseAndPost(false),
      );
    }
  }

  void _reload() {
    _products = widget.repository.current();
    _history = widget.repository.history();
    _value = widget.repository.inventoryValueCentavos();
  }

  Future<void> _chooseAndPost(bool adjustment) async {
    final products = await widget.repository.current();
    if (!mounted || products.isEmpty) return;
    var productId = products.first.id;
    final quantity = TextEditingController();
    final cost = TextEditingController();
    final notes = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(adjustment ? AppStrings.adjustment : AppStrings.stockIn),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: productId,
                  decoration: const InputDecoration(
                    labelText: AppStrings.products,
                    border: OutlineInputBorder(),
                  ),
                  items: products
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            '${p.name} (${productQuantityText(p, p.currentQuantity)})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => productId = v!),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: adjustment
                        ? '+ / - ${AppStrings.quantity}'
                        : AppStrings.quantity,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                if (!adjustment)
                  TextField(
                    controller: cost,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: AppStrings.unitCost,
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (!adjustment) const SizedBox(height: 14),
                TextField(
                  controller: notes,
                  decoration: InputDecoration(
                    labelText: adjustment
                        ? AppStrings.reason
                        : AppStrings.notes,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(AppStrings.confirm),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final amount = int.tryParse(quantity.text) ?? 0;
    try {
      if (adjustment) {
        await widget.repository.adjust(
          productId: productId,
          quantityChange: amount,
          reason: notes.text,
        );
      } else {
        final enteredCost = double.tryParse(cost.text.trim());
        if (cost.text.trim().isNotEmpty && enteredCost == null) {
          throw const InvalidInventoryOperation('Invalid unit cost.');
        }
        await widget.repository.stockIn(
          productId: productId,
          quantity: amount,
          unitCostCentavos: enteredCost == null
              ? null
              : (enteredCost * 100).round(),
          notes: notes.text,
        );
      }
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.stockSaved)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.couldNotSave)));
      }
    }
  }

  String _type(String type) => switch (type) {
    'INITIAL_STOCK' => 'Starting Stock',
    'STOCK_IN' => 'Stock In',
    'ADJUSTMENT_IN' => 'Adjustment In',
    'ADJUSTMENT_OUT' => 'Adjustment Out',
    'UTANG' => 'UTANG Sale',
    _ => type,
  };

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.inventory),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'All'),
            Tab(text: AppStrings.lowStock),
            Tab(text: AppStrings.outOfStock),
            Tab(text: AppStrings.movementHistory),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _productList(null),
          _productList(ProductStockStatus.lowStock),
          _productList(ProductStockStatus.outOfStock),
          FutureBuilder<List<InventoryMovement>>(
            future: _history,
            builder: (_, s) => s.hasData
                ? ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: s.data!.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (_, i) {
                      final m = s.data![i];
                      return ListTile(
                        title: Text(
                          m.productName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        subtitle: Text(
                          '${_type(m.type)} • ${m.quantityBefore} → ${m.quantityAfter}\n${m.notes ?? ''}',
                        ),
                        trailing: Text(
                          '${m.quantityChange > 0 ? '+' : ''}${m.quantityChange}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      );
                    },
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<int>(
            future: _value,
            builder: (_, s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Owned Inventory Value'),
                Text(
                  standardMoney(s.data ?? 0),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _productList(
    ProductStockStatus? status,
  ) => FutureBuilder<List<Product>>(
    future: status == null
        ? _products
        : widget.repository.current(status: status),
    builder: (_, s) => s.hasData
        ? ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: s.data!.length,
            itemBuilder: (_, i) {
              final p = s.data![i];
              final out = p.currentQuantity == 0;
              final low = !out && p.currentQuantity <= p.minimumStockLevel;
              final statusLabel = out
                  ? 'Out of Stock'
                  : low
                  ? 'Low Stock'
                  : 'In Stock';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: out
                            ? Colors.red.shade50
                            : low
                            ? Colors.orange.shade50
                            : Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: out
                              ? Colors.red.shade700
                              : low
                              ? Colors.orange.shade800
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Text('Selling Price'),
                            Text(
                              '₱${(p.sellingPriceCentavos / 100).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Stock'),
                            Text(
                              productQuantityText(p, p.currentQuantity),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: out
                                    ? Colors.red.shade700
                                    : low
                                    ? Colors.orange.shade800
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          )
        : const Center(child: CircularProgressIndicator()),
  );
}
