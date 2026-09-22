import 'package:flutter/material.dart';

import '../../../widgets/product_image.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/inventory_movement.dart';
import '../../../core/formatters/display_labels.dart';
import '../../../models/product.dart';
import '../../../repositories/inventory_repository.dart';
import '../../help/help_button.dart';
import '../../help/help_content.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.repository,
    this.openStockIn = false,
  });
  final InventoryRepository repository;
  final bool openStockIn;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<Product>> _products;
  late Future<List<InventoryMovement>> _history;
  late Future<OwnedInventorySummary> _summary;
  late Future<Map<int, OwnedInventoryProductValue>> _productValues;
  final _search = TextEditingController();
  ProductStockStatus? _status;
  String _sort = 'Name';
  String _ownership = 'All products';
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
    _summary = widget.repository.ownedSummary();
    _productValues = widget.repository.ownedProductValues();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _chooseAndPost(bool adjustment, {int? initialProductId}) async {
    final products = await widget.repository.current();
    if (!mounted || products.isEmpty) return;
    var productId = products.any((p) => p.id == initialProductId)
        ? initialProductId!
        : products.first.id;
    final quantity = TextEditingController();
    final cost = TextEditingController();
    final notes = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(AppStrings.inventory),
      actions: [
        const HelpButton(topic: HelpTopicId.inventory),
        TextButton.icon(
          onPressed: _showHistory,
          icon: const Icon(Icons.history),
          label: const Text('Inventory History'),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: FutureBuilder<List<Product>>(
      future: _products,
      builder: (_, products) {
        if (products.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(_reload),
              child: const Text('Could not load inventory. Try again'),
            ),
          );
        }
        if (!products.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final visible = _filterAndSort(products.data!);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            FutureBuilder<OwnedInventorySummary>(
              future: _summary,
              builder: (_, s) => s.hasError
                  ? const Text('Inventory values are temporarily unavailable.')
                  : _summaryCards(s.data),
            ),
            const SizedBox(height: 20),
            FutureBuilder<Map<int, OwnedInventoryProductValue>>(
              future: _productValues,
              builder: (_, values) {
                final productValues = values.data ?? const {};
                final filtered = visible.where((product) {
                  final owned = productValues.containsKey(product.id);
                  return _ownership == 'All products' ||
                      (_ownership == 'Owned products' && owned) ||
                      (_ownership == 'Consigned products' && !owned);
                }).toList();
                return Column(
                  children: [
                    _inventoryToolbar(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _filterChip('All', null),
                        _filterChip('Low Stock', ProductStockStatus.lowStock),
                        _filterChip(
                          'Out of Stock',
                          ProductStockStatus.outOfStock,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '${filtered.length} ${filtered.length == 1 ? 'product' : 'products'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _productList(filtered, productValues),
                  ],
                );
              },
            ),
          ],
        );
      },
    ),
  );

  Widget _filterChip(String label, ProductStockStatus? value) => ChoiceChip(
    label: Text(label),
    selected: _status == value,
    onSelected: (_) => setState(() => _status = value),
  );

  Widget _inventoryToolbar() {
    final search = TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        labelText: 'Search inventory',
        hintText: 'Search inventory by product name',
      ),
    );
    final filter = PopupMenuButton<String>(
      onSelected: (value) => setState(() => _ownership = value),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'All products', child: Text('All products')),
        PopupMenuItem(value: 'Owned products', child: Text('Owned products')),
        PopupMenuItem(
          value: 'Consigned products',
          child: Text('Consigned products'),
        ),
      ],
      child: _toolbarButton(
        Icons.filter_alt_outlined,
        _ownership == 'All products' ? 'Filter' : _ownership,
      ),
    );
    final sort = PopupMenuButton<String>(
      onSelected: (value) => setState(() => _sort = value),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'Name', child: Text('Name')),
        PopupMenuItem(value: 'Lowest Stock', child: Text('Lowest Stock')),
        PopupMenuItem(value: 'Highest Stock', child: Text('Highest Stock')),
        PopupMenuItem(
          value: 'Recently Updated',
          child: Text('Recently Updated'),
        ),
      ],
      child: _toolbarButton(Icons.sort, 'Sort: $_sort'),
    );
    return LayoutBuilder(
      builder: (_, box) {
        if (box.maxWidth >= 760) {
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              filter,
              const SizedBox(width: 12),
              sort,
            ],
          );
        }
        return Column(
          children: [
            search,
            const SizedBox(height: 10),
            Row(children: [filter, const SizedBox(width: 10), sort]),
          ],
        );
      },
    );
  }

  Widget _toolbarButton(IconData icon, String label) => Container(
    constraints: const BoxConstraints(minHeight: 52),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 6),
        const Icon(Icons.keyboard_arrow_down, size: 18),
      ],
    ),
  );

  List<Product> _filterAndSort(List<Product> source) {
    final query = _search.text.trim().toLowerCase();
    final products = source
        .where(
          (p) =>
              (_status == null || p.stockStatus == _status) &&
              (query.isEmpty || p.name.toLowerCase().contains(query)),
        )
        .toList();
    products.sort(
      (a, b) => switch (_sort) {
        'Lowest Stock' => a.currentQuantity.compareTo(b.currentQuantity),
        'Highest Stock' => b.currentQuantity.compareTo(a.currentQuantity),
        'Recently Updated' => b.updatedAt.compareTo(a.updatedAt),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      },
    );
    return products;
  }

  Widget _summaryCards(OwnedInventorySummary? summary) {
    final s = summary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: .3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Owned Inventory Summary',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Supplier-owned consignment stock is not included.',
                child: Icon(Icons.info_outline, size: 19),
              ),
            ],
          ),
          const Text('Consignment stock excluded'),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (_, box) {
              final columns = box.maxWidth >= 900
                  ? 3
                  : box.maxWidth >= 560
                  ? 2
                  : 1;
              final width = (box.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _summaryMetric(
                    'Inventory Cost',
                    s?.inventoryCostCentavos ?? 0,
                    Icons.inventory_2_outlined,
                    width,
                  ),
                  _summaryMetric(
                    'Potential Sales Value',
                    s?.potentialSalesValueCentavos ?? 0,
                    Icons.sell_outlined,
                    width,
                  ),
                  _summaryMetric(
                    'Potential Gross Profit',
                    s?.potentialGrossProfitCentavos ?? 0,
                    Icons.trending_up_outlined,
                    width,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(String title, int value, IconData icon, double width) =>
      SizedBox(
        width: width,
        child: Builder(
          builder: (context) {
            final help = switch (title) {
              'Inventory Cost' => 'How much your current owned stock cost you.',
              'Potential Sales Value' => 'How much you could receive if all current stock is sold at current selling prices.',
              _ => 'Potential Sales Value minus Inventory Cost.',
            };
            final accent = switch (title) {
              'Potential Sales Value' => Colors.blue.shade600,
              'Potential Gross Profit' => Colors.orange.shade700,
              _ => Theme.of(context).colorScheme.primary,
            };
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: accent.withValues(alpha: .16),
                    foregroundColor: accent,
                    child: Icon(icon),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Tooltip(
                              message: help,
                              child: const Icon(Icons.info_outline, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          standardMoney(value),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          help,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

  String _movementQuantity(InventoryMovement movement, int quantity) =>
      baseQuantityText(
        quantity,
        baseUnitCode: movement.baseUnitCode,
        baseUnitLabel: movement.baseUnitLabel,
      );

  Widget _productList(
    List<Product> products,
    Map<int, OwnedInventoryProductValue> values,
  ) => products.isEmpty
      ? const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: Text('No products match these filters.')),
        )
      : Column(
          children: products.map((p) {
            final out = p.currentQuantity == 0;
            final low = !out && p.currentQuantity <= p.minimumStockLevel;
            final value = values[p.id];
            final statusLabel = out
                ? 'Out of Stock'
                : low
                ? 'Low Stock'
                : 'In Stock';
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: LayoutBuilder(
                builder: (_, box) => box.maxWidth >= 850
                    ? _wideProductRow(p, value, statusLabel, out, low)
                    : _compactProductCard(p, value, statusLabel, out, low),
              ),
            );
          }).toList(),
        );

  Widget _wideProductRow(
    Product product,
    OwnedInventoryProductValue? value,
    String status,
    bool out,
    bool low,
  ) => Padding(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        SizedBox(width: 330, child: _productIdentity(product, value)),
        const VerticalDivider(width: 24),
        if (value == null)
          const Expanded(
            flex: 3,
            child: Text(
              'Supplier-owned stock • excluded from owned inventory values',
            ),
          )
        else ...[
          Expanded(
            child: _valueCell(
              'Current Stock Cost',
              value.currentStockCostCentavos,
            ),
          ),
          Expanded(
            child: _valueCell(
              'Potential Sales Value',
              value.potentialSalesValueCentavos,
            ),
          ),
          Expanded(
            child: _valueCell(
              'Potential Gross Profit',
              value.potentialGrossProfitCentavos,
            ),
          ),
        ],
        const VerticalDivider(width: 24),
        SizedBox(width: 150, child: _stockCell(product, status, out, low)),
        _productMenu(product),
      ],
    ),
  );

  Widget _compactProductCard(
    Product product,
    OwnedInventoryProductValue? value,
    String status,
    bool out,
    bool low,
  ) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: _productIdentity(product, value)),
            _productMenu(product),
          ],
        ),
        const SizedBox(height: 14),
        if (value == null)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Supplier-owned stock • excluded from owned inventory values',
            ),
          )
        else
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _valueCell('Current Stock Cost', value.currentStockCostCentavos),
              _valueCell(
                'Potential Sales Value',
                value.potentialSalesValueCentavos,
              ),
              _valueCell(
                'Potential Gross Profit',
                value.potentialGrossProfitCentavos,
              ),
            ],
          ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 180,
            child: _stockCell(product, status, out, low),
          ),
        ),
      ],
    ),
  );

  Widget _productIdentity(Product product, OwnedInventoryProductValue? value) {
    final packageSize = product.defaultPurchaseBaseQuantity ?? 1;
    final costPerUnit = (product.purchasePriceCentavos / packageSize).round();
    return Row(
      children: [
        Semantics(
          image: true,
          label: '${product.name} product image',
          child: SizedBox(
            width: 72,
            height: 72,
            child: ProductImage(path: product.photoPath, borderRadius: 12),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                value == null
                    ? 'Supplier-owned inventory'
                    : 'Cost: ${standardMoney(costPerUnit)} / ${product.baseUnitLabel}',
              ),
              Text(
                'Sell: ${standardMoney(product.sellingPriceCentavos)} / ${product.baseUnitLabel}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _valueCell(String label, int amount) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          standardMoney(amount),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );

  Widget _stockCell(Product product, String status, bool out, bool low) {
    final color = out
        ? Theme.of(context).colorScheme.error
        : low
        ? Colors.orange.shade700
        : Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${product.currentQuantity}',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        Text(product.baseUnitLabel),
        const SizedBox(height: 4),
        Chip(
          label: Text(status),
          side: BorderSide.none,
          backgroundColor: color.withValues(alpha: .16),
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _productMenu(Product product) => PopupMenuButton<String>(
    tooltip: 'Inventory actions for ${product.name}',
    onSelected: (action) {
      if (action == 'stock') {
        _chooseAndPost(false, initialProductId: product.id);
      } else if (action == 'adjust') {
        _chooseAndPost(true, initialProductId: product.id);
      } else {
        _showHistory(productName: product.name);
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'stock', child: Text('Stock In')),
      PopupMenuItem(value: 'adjust', child: Text('Adjust Stock')),
      PopupMenuItem(value: 'history', child: Text('Movement History')),
    ],
    icon: const Icon(Icons.more_vert),
  );

  Future<void> _showHistory({String? productName}) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          productName == null
              ? 'Stock Movement History'
              : '$productName Movement History',
        ),
        content: SizedBox(
          width: 680,
          height: 480,
          child: FutureBuilder<List<InventoryMovement>>(
            future: _history,
            builder: (_, s) => s.hasError
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Could not load stock history. Close this window and try again.',
                      ),
                    ),
                  )
                : !s.hasData
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (_) {
                      final movements = productName == null
                          ? s.data!
                          : s.data!
                                .where((m) => m.productName == productName)
                                .toList();
                      if (movements.isEmpty) {
                        return const Center(
                          child: Text('No movement recorded yet.'),
                        );
                      }
                      return ListView.separated(
                        itemCount: movements.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (_, i) {
                          final m = movements[i];
                          return ListTile(
                            title: Text(m.productName),
                            subtitle: Text(
                              '${DisplayLabels.movement(m.type)} • ${_movementQuantity(m, m.quantityBefore)} → ${_movementQuantity(m, m.quantityAfter)}${m.notes == null || m.notes!.isEmpty ? '' : '\n${m.notes}'}',
                            ),
                            trailing: Text(
                              '${m.quantityChange > 0 ? '+' : ''}${_movementQuantity(m, m.quantityChange.abs())}',
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
