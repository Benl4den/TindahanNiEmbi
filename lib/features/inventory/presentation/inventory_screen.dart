import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/product_image.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/inventory_movement.dart';
import '../../../core/formatters/display_labels.dart';
import '../../../models/product.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../services/feature_access_service.dart';
import '../../../widgets/feature_access_builder.dart';
import '../../help/help_button.dart';
import '../../help/help_content.dart';

class _CorrectStockDialog extends StatefulWidget {
  const _CorrectStockDialog({required this.product, required this.repository});
  final Product product;
  final InventoryRepository repository;

  @override
  State<_CorrectStockDialog> createState() => _CorrectStockDialogState();
}

class _CorrectStockDialogState extends State<_CorrectStockDialog> {
  final quantity = TextEditingController();
  final otherReason = TextEditingController();
  bool adding = false;
  bool saving = false;
  String? reason;
  String? error;

  List<String> get reasons => adding
      ? const ['Physical Count Correction', 'Previously Missed Stock', 'Other']
      : const [
          'Damaged',
          'Expired',
          'Missing / Lost',
          'Physical Count Correction',
          'Other',
        ];

  int? get amount => int.tryParse(quantity.text.trim());
  int? get newStock {
    final value = amount;
    if (value == null || value <= 0) return null;
    return widget.product.currentQuantity + (adding ? value : -value);
  }

  @override
  void dispose() {
    quantity.dispose();
    otherReason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final value = amount;
    if (value == null || value <= 0) {
      setState(() => error = 'Enter a quantity greater than zero.');
      return;
    }
    if (newStock! < 0) {
      setState(() => error = 'You cannot remove more than the current stock.');
      return;
    }
    if (reason == null ||
        (reason == 'Other' && otherReason.text.trim().isEmpty)) {
      setState(() => error = 'Choose a reason and describe Other if selected.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.adjust(
        productId: widget.product.id,
        quantityChange: adding ? value : -value,
        reason: reason == 'Other'
            ? 'Other: ${otherReason.text.trim()}'
            : reason!,
        expectedCurrentQuantity: widget.product.currentQuantity,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on InvalidInventoryOperation catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not correct stock. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Correct Stock'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.product.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Use this for physical count differences, damage, or missing stock. Purchases belong in Stock In.',
          ),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Remove stock'),
                icon: Icon(Icons.remove),
              ),
              ButtonSegment(
                value: true,
                label: Text('Add stock'),
                icon: Icon(Icons.add),
              ),
            ],
            selected: {adding},
            onSelectionChanged: saving
                ? null
                : (selection) => setState(() {
                    adding = selection.first;
                    reason = null;
                    error = null;
                  }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: quantity,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() => error = null),
            decoration: InputDecoration(
              labelText: 'Quantity (${widget.product.baseUnitLabel})',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: ValueKey(adding),
            initialValue: reason,
            decoration: const InputDecoration(
              labelText: 'Reason',
              border: OutlineInputBorder(),
            ),
            items: reasons
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: saving
                ? null
                : (value) => setState(() {
                    reason = value;
                    error = null;
                  }),
          ),
          if (reason == 'Other') ...[
            const SizedBox(height: 14),
            TextField(
              controller: otherReason,
              maxLines: 2,
              onChanged: (_) => setState(() => error = null),
              decoration: const InputDecoration(
                labelText: 'Describe the reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Current: ${productQuantityText(widget.product, widget.product.currentQuantity)}',
          ),
          Text(
            'Change: ${amount == null || amount == 0 ? '—' : '${adding ? '+' : '-'}${productQuantityText(widget.product, amount!)}'}',
          ),
          Text(
            'New stock: ${newStock == null || newStock! < 0 ? '—' : productQuantityText(widget.product, newStock!)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Confirm Correction'),
      ),
    ],
  );
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.repository,
    required this.access,
    this.openStockIn = false,
  });
  final InventoryRepository repository;
  final FeatureAccessService access;
  final bool openStockIn;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<Product>> _products;
  late Future<List<InventoryMovement>> _history;
  late Future<OwnedInventorySummary> _summary;
  late Future<Map<int, OwnedInventoryProductValue>> _productValues;
  late Future<OwnedInventoryHealth> _freeHealth;
  late Future<OwnedInventoryHealth> _proHealth;
  bool _proLoaded = false;
  final _search = TextEditingController();
  ProductStockStatus? _status;
  String _sort = 'Name';
  String _ownership = 'All products';
  @override
  void initState() {
    super.initState();
    _reload();
    if (widget.openStockIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _chooseAndPost());
    }
  }

  void _reload() {
    _products = widget.repository.current();
    _history = widget.repository.history();
    _freeHealth = widget.repository.ownedHealth();
    _proLoaded = false;
  }

  void _loadProValues() {
    _proHealth = widget.repository.ownedHealth(includeRecentSales: true);
    _summary = widget.repository.ownedSummary();
    _productValues = widget.repository.ownedProductValues();
    _proLoaded = true;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _chooseAndPost({int? initialProductId}) async {
    late final List<Product> products;
    try {
      final results = await Future.wait([
        widget.repository.current(),
        widget.repository.ownedHealth(),
      ]);
      final ownedIds = (results[1] as OwnedInventoryHealth).productIds;
      products = (results[0] as List<Product>)
          .where((product) => ownedIds.contains(product.id))
          .toList();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load owned products. Please try again.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No owned products available for Stock In. Use Consignment for supplier-owned stock.',
          ),
        ),
      );
      return;
    }
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
          scrollable: true,
          title: const Text(AppStrings.stockIn),
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
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: AppStrings.quantity,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: cost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: AppStrings.unitCost,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: AppStrings.notes,
                    border: OutlineInputBorder(),
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
      if (mounted) {
        setState(_reload);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(AppStrings.stockSaved)));
      }
    } on InvalidInventoryOperation catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
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
    body: FeatureAccessBuilder(
      access: widget.access,
      feature: ProFeature.inventoryInsights,
      builder: (context, pro) {
        if (pro && !_proLoaded) _loadProValues();
        if (!pro) _proLoaded = false;
        return _inventoryBody(pro);
      },
    ),
  );

  Widget _inventoryBody(bool pro) => FutureBuilder<List<Product>>(
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
          FutureBuilder<OwnedInventoryHealth>(
            future: pro ? _proHealth : _freeHealth,
            builder: (_, healthSnapshot) {
              if (healthSnapshot.hasError) {
                return const Text(
                  'Could not load inventory status. Try again.',
                );
              }
              if (!healthSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final health = healthSnapshot.data!;
              return FutureBuilder<OwnedInventorySummary>(
                future: pro ? _summary : null,
                builder: (_, summarySnapshot) {
                  if (pro && summarySnapshot.hasError) {
                    return const Text(
                      'Inventory values are temporarily unavailable.',
                    );
                  }
                  if (pro && !summarySnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return FutureBuilder<Map<int, OwnedInventoryProductValue>>(
                    future: pro ? _productValues : null,
                    builder: (_, values) {
                      if (pro && values.hasError) {
                        return const Text(
                          'Could not load product values. Try again.',
                        );
                      }
                      if (pro && !values.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final productValues = pro
                          ? values.data!
                          : <int, OwnedInventoryProductValue>{};
                      final filtered = visible.where((product) {
                        final owned = health.productIds.contains(product.id);
                        return _ownership == 'All products' ||
                            (_ownership == 'Owned products' && owned) ||
                            (_ownership == 'Consigned products' && !owned);
                      }).toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _summaryCards(
                            pro ? summarySnapshot.data : null,
                            health,
                            pro,
                          ),
                          const SizedBox(height: 12),
                          pro ? _inventoryHealth(health) : _lockedInsights(),
                          const SizedBox(height: 16),
                          _inventoryToolbar(),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _filterChip('All', null),
                              _filterChip(
                                'Low Stock',
                                ProductStockStatus.lowStock,
                              ),
                              _filterChip(
                                'Out of Stock',
                                ProductStockStatus.outOfStock,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '${filtered.length} ${filtered.length == 1 ? 'product' : 'products'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _productList(
                            filtered,
                            productValues,
                            health.productIds,
                            pro,
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      );
    },
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

  Widget _summaryCards(
    OwnedInventorySummary? summary,
    OwnedInventoryHealth health,
    bool pro,
  ) {
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
                  if (pro) ...[
                    _summaryMetric(
                      'Current Inventory Cost',
                      standardMoney(s!.inventoryCostCentavos),
                      'How much your current owned stock costs you.',
                      Icons.inventory_2_outlined,
                      width,
                      const Color(0xFF64CF9D),
                    ),
                    _summaryMetric(
                      'Potential Sales Value',
                      standardMoney(s.potentialSalesValueCentavos),
                      'How much you could receive if all current stock is sold at current selling prices.',
                      Icons.sell_outlined,
                      width,
                      const Color(0xFF79B7F4),
                    ),
                    _summaryMetric(
                      'Potential Gross Profit',
                      standardMoney(s.potentialGrossProfitCentavos),
                      'Potential Sales Value minus Inventory Cost.',
                      Icons.trending_up,
                      width,
                      const Color(0xFFFFB45C),
                    ),
                  ] else ...[
                    _summaryMetric(
                      'Active Products',
                      '${health.activeProducts}',
                      'Products with stock',
                      Icons.inventory_2_outlined,
                      width,
                      const Color(0xFF64CF9D),
                    ),
                    _summaryMetric(
                      'Low Stock',
                      '${health.lowStock}',
                      'Needs attention',
                      Icons.warning_amber_rounded,
                      width,
                      const Color(0xFFFFCE56),
                    ),
                    _summaryMetric(
                      'Out of Stock',
                      '${health.outOfStock}',
                      'Unavailable',
                      Icons.cancel_outlined,
                      width,
                      const Color(0xFFFF7777),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryMetric(
    String title,
    String value,
    String help,
    IconData icon,
    double width,
    Color accent,
  ) => SizedBox(
    width: width,
    child: Builder(
      builder: (context) {
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
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(help, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _inventoryHealth(OwnedInventoryHealth health) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bar_chart, color: Color(0xFF65D7A6)),
            const SizedBox(width: 8),
            Text(
              'Inventory Health',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 10),
            const Chip(
              label: Text('PRO'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const Text('A quick view of your inventory status.'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (_, box) {
            final columns = box.maxWidth >= 850 ? 4 : 2;
            final width = (box.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _healthTile(
                  'Active Products',
                  health.activeProducts,
                  Icons.inventory_2_outlined,
                  const Color(0xFF65D7A6),
                  width,
                ),
                _healthTile(
                  'Low Stock',
                  health.lowStock,
                  Icons.warning_amber_rounded,
                  const Color(0xFFFFCE56),
                  width,
                ),
                _healthTile(
                  'Out of Stock',
                  health.outOfStock,
                  Icons.cancel_outlined,
                  const Color(0xFFFF7777),
                  width,
                ),
                _healthTile(
                  'No Recent Sales',
                  health.noRecentSales,
                  Icons.access_time,
                  const Color(0xFFCA9AF1),
                  width,
                ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Widget _healthTile(
    String label,
    int count,
    IconData icon,
    Color color,
    double width,
  ) => Container(
    width: width,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count', style: Theme.of(context).textTheme.titleLarge),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (label == 'No Recent Sales')
          const Tooltip(
            message: 'Owned products with stock and no posted sales in the last 30 days.',
            child: Icon(Icons.info_outline, size: 17),
          ),
      ],
    ),
  );

  Widget _lockedInsights() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.lock, color: Color(0xFFFFCE56)),
            Text(
              'Inventory Value & Profit Insights',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Chip(
              label: Text('PRO'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          'Know how much money is currently invested in your stock, its potential sales value, and potential gross profit.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (_, box) {
            final columns = box.maxWidth >= 640 ? 4 : 2;
            final width = (box.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: width,
                  height: 68,
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: Color(0xFF65D7A6),
                    size: 42,
                  ),
                ),
                for (final label in [
                  'Inventory Cost',
                  'Potential Sales Value',
                  'Potential Gross Profit',
                ])
                  Container(
                    width: width,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Row(
                          children: [
                            Icon(
                              Icons.lock,
                              size: 16,
                              color: Color(0xFFFFCE56),
                            ),
                            SizedBox(width: 5),
                            Text('--'),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: const Text('Pro is coming later'),
                content: const Text(
                  'Subscriptions are not available yet. Your stock and records remain available in the Free plan.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Preview Pro  ›'),
          ),
        ),
      ],
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
    Set<int> ownedIds,
    bool pro,
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
                    ? _wideProductRow(
                        p,
                        value,
                        ownedIds.contains(p.id),
                        pro,
                        statusLabel,
                        out,
                        low,
                      )
                    : _compactProductCard(
                        p,
                        value,
                        ownedIds.contains(p.id),
                        pro,
                        statusLabel,
                        out,
                        low,
                      ),
              ),
            );
          }).toList(),
        );

  Widget _wideProductRow(
    Product product,
    OwnedInventoryProductValue? value,
    bool owned,
    bool pro,
    String status,
    bool out,
    bool low,
  ) => Padding(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Expanded(flex: pro ? 4 : 8, child: _productIdentity(product, owned)),
        if (pro) const VerticalDivider(width: 24),
        if (pro && value == null)
          const Expanded(
            flex: 3,
            child: Text(
              'Supplier-owned stock • excluded from owned inventory values',
            ),
          )
        else if (pro && value != null) ...[
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
        _productMenu(product, owned: owned),
      ],
    ),
  );

  Widget _compactProductCard(
    Product product,
    OwnedInventoryProductValue? value,
    bool owned,
    bool pro,
    String status,
    bool out,
    bool low,
  ) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(child: _productIdentity(product, owned)),
            _productMenu(product, owned: owned),
          ],
        ),
        const SizedBox(height: 14),
        if (pro && value == null)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Supplier-owned stock • excluded from owned inventory values',
            ),
          )
        else if (pro && value != null)
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

  Widget _productIdentity(Product product, bool owned) {
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
                !owned
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );

  Widget _stockCell(Product product, String status, bool out, bool low) {
    final quantityDisplay = productQuantityText(
      product,
      product.currentQuantity,
    );
    final split = quantityDisplay.indexOf(' ');
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
          split < 0 ? quantityDisplay : quantityDisplay.substring(0, split),
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        Text(split < 0 ? '' : quantityDisplay.substring(split + 1)),
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

  Widget _productMenu(
    Product product, {
    required bool owned,
  }) => PopupMenuButton<String>(
    tooltip: 'Inventory actions for ${product.name}',
    onSelected: (action) {
      if (action == 'stock') {
        _chooseAndPost(initialProductId: product.id);
      } else if (action == 'adjust') {
        _correctStock(product);
      } else {
        _showHistory(productName: product.name);
      }
    },
    itemBuilder: (_) => [
      if (owned) const PopupMenuItem(value: 'stock', child: Text('Stock In')),
      if (owned)
        const PopupMenuItem(value: 'adjust', child: Text('Correct Stock')),
      const PopupMenuItem(value: 'history', child: Text('Movement History')),
    ],
    icon: const Icon(Icons.more_vert),
  );

  Future<void> _correctStock(Product product) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _CorrectStockDialog(product: product, repository: widget.repository),
    );
    if (saved == true && mounted) {
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} stock correction saved.')),
      );
    }
  }

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
                              '${m.quantityChange >= 0 ? '+' : '-'}${_movementQuantity(m, m.quantityChange.abs())}',
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
