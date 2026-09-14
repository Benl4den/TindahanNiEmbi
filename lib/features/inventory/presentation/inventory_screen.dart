import 'package:flutter/material.dart';

import '../../../widgets/overview_banner.dart';

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
          label: const Text('History'),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: FutureBuilder<List<Product>>(
      future: _products,
      builder: (_, products) {
        if (!products.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final visible = _filterAndSort(products.data!);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FutureBuilder<OwnedInventorySummary>(
              future: _summary,
              builder: (_, s) => _summaryCards(s.data),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search inventory',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _filterChip('All', null),
                _filterChip('Low Stock', ProductStockStatus.lowStock),
                _filterChip('Out of Stock', ProductStockStatus.outOfStock),
                PopupMenuButton<String>(
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'Name', child: Text('Name')),
                    PopupMenuItem(
                      value: 'Lowest Stock',
                      child: Text('Lowest Stock'),
                    ),
                    PopupMenuItem(
                      value: 'Highest Stock',
                      child: Text('Highest Stock'),
                    ),
                    PopupMenuItem(
                      value: 'Recently Updated',
                      child: Text('Recently Updated'),
                    ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.sort, size: 18),
                    label: Text('Sort: $_sort'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<Map<int, OwnedInventoryProductValue>>(
              future: _productValues,
              builder: (_, values) =>
                  _productList(visible, values.data ?? const {}),
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
    return LayoutBuilder(
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
    );
  }

  Widget _summaryMetric(String title, int value, IconData icon, double width) =>
      SizedBox(
        width: width,
        child: OverviewBanner(
          title: title,
          value: standardMoney(value),
          caption: 'Owned stock only',
          icon: icon,
          valueFontSize: 22,
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
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                value == null
                                    ? 'Consignment stock • Sell: ${standardMoney(p.sellingPriceCentavos)} / ${p.baseUnitLabel}'
                                    : 'Cost: ${standardMoney(value.currentStockCostCentavos ~/ (p.currentQuantity == 0 ? 1 : p.currentQuantity))} / ${p.baseUnitLabel} • Sell: ${standardMoney(p.sellingPriceCentavos)} / ${p.baseUnitLabel}',
                              ),
                              if (value != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Current Stock Cost: ${standardMoney(value.currentStockCostCentavos)}',
                                ),
                                Text(
                                  'Potential Sales Value: ${standardMoney(value.potentialSalesValueCentavos)}',
                                ),
                                Text(
                                  'Potential Gross Profit: ${standardMoney(value.potentialGrossProfitCentavos)}',
                                ),
                              ],
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
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
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
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _showHistory(productName: p.name),
                        icon: const Icon(Icons.history),
                        label: const Text('View Movement History'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
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
            builder: (_, s) => !s.hasData
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
