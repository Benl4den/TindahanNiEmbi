import 'package:flutter/material.dart';

import '../../../repositories/inventory_repository.dart';
import '../../../core/formatters/number_format.dart';
import '../../../repositories/operations_repository.dart';
import '../../../repositories/product_unit_repository.dart';
import '../../inventory/presentation/package_stock_in_dialog.dart';
import '../../../widgets/app_state_view.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/product_image.dart';

class RestockScreen extends StatefulWidget {
  const RestockScreen({
    super.key,
    required this.operations,
    required this.inventory,
    required this.openConsignment,
  });
  final OperationsRepository operations;
  final InventoryRepository inventory;
  final void Function(int? consignorId, int? productId) openConsignment;
  @override
  State<RestockScreen> createState() => _State();
}

class _State extends State<RestockScreen> {
  String filter = 'NEEDS';
  String search = '';
  late Future<List<RestockItem>> data;
  late Future<List<RestockItem>> allData;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    data = widget.operations.restock(filter: filter);
    allData = widget.operations.restock(filter: 'ALL');
  }

  Future<void> stock(RestockItem item) async {
    if (item.isConsignment) {
      widget.openConsignment(item.consignorId, item.product.id);
      return;
    }
    final saved = await showPackageStockInDialog(
      context: context,
      product: item.product,
      repository: ProductUnitRepository(widget.inventory.db),
      suggestedBaseQuantity: item.suggested,
    );
    if (saved && mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Restock')),
    body: LayoutBuilder(
      builder: (_, viewport) => viewport.maxWidth < 600
          ? _compactBody()
          : Column(
              children: [
                FutureBuilder<List<RestockItem>>(
                  future: allData,
                  builder: (_, s) {
                    final items = s.data ?? const <RestockItem>[];
                    final low = items
                        .where(
                          (x) =>
                              x.product.currentQuantity > 0 &&
                              x.product.currentQuantity <=
                                  x.product.minimumStockLevel,
                        )
                        .length;
                    final out = items
                        .where((x) => x.product.currentQuantity == 0)
                        .length;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                      child: LayoutBuilder(
                        builder: (_, box) {
                          final cards = [
                            _metric(
                              'Needs Restock',
                              low + out,
                              Icons.add_shopping_cart,
                            ),
                            _metric(
                              'Low Stock ($low)',
                              low,
                              Icons.warning_amber,
                              Colors.orange.shade800,
                            ),
                            _metric(
                              'Out of Stock ($out)',
                              out,
                              Icons.error_outline,
                              Colors.red.shade700,
                            ),
                          ];
                          return box.maxWidth < 650
                              ? Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: cards,
                                )
                              : Row(
                                  children: [
                                    for (var i = 0; i < cards.length; i++) ...[
                                      Expanded(child: cards[i]),
                                      if (i < cards.length - 1)
                                        const SizedBox(width: 12),
                                    ],
                                  ],
                                );
                        },
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (_, box) {
                      final chips = <Widget>[
                        for (final x in [
                          ('NEEDS', 'Needs Restock'),
                          ('ALL', 'All'),
                          ('LOW', 'Low Stock'),
                          ('OUT', 'Out of Stock'),
                          ('SELECTA', 'Selecta'),
                        ])
                          ChoiceChip(
                            label: Text(x.$2),
                            selected: filter == x.$1,
                            onSelected: (_) {
                              setState(() {
                                filter = x.$1;
                                reload();
                              });
                            },
                          ),
                      ];
                      final searchField = AppSearchField(
                        hintText: 'Search products',
                        onChanged: (v) =>
                            setState(() => search = v.trim().toLowerCase()),
                      );
                      if (box.maxWidth < 760) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            searchField,
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
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(spacing: 8, children: chips),
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(width: 300, child: searchField),
                        ],
                      );
                    },
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<RestockItem>>(
                    future: data,
                    builder: (_, s) {
                      if (s.hasError) {
                        return AppStateView.error(
                          title: 'Could not load restock list',
                          actionLabel: 'Try Again',
                          onAction: () => setState(reload),
                        );
                      }
                      if (!s.hasData) {
                        return const AppLoadingView(
                          label: 'Loading restock list…',
                        );
                      }
                      final visible = s.data!
                          .where(
                            (x) =>
                                x.product.name.toLowerCase().contains(search),
                          )
                          .toList();
                      if (visible.isEmpty) {
                        final stocked = search.isEmpty && filter == 'NEEDS';
                        return AppStateView(
                          icon: stocked
                              ? Icons.inventory_2_outlined
                              : Icons.search_off,
                          title: stocked
                              ? 'All products are sufficiently stocked'
                              : 'No products match this view',
                          message: stocked
                              ? 'You’re ready for the next sale. Low-stock products appear here automatically when they reach their Low Stock Alert At setting. Review that setting in Products as demand changes.'
                              : 'Try another filter or search to find a product.',
                          actionLabel: 'View All Stock',
                          onAction: () => setState(() {
                            filter = 'ALL';
                            search = '';
                            reload();
                          }),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final x = visible[i];
                          final out = x.product.currentQuantity <= 0;
                          final low =
                              !out &&
                              x.product.currentQuantity > 0 &&
                              x.product.currentQuantity <=
                                  x.product.minimumStockLevel;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(18),
                                leading: SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: ProductImage(
                                      path: x.product.photoPath,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  x.product.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Current: ${productQuantityText(x.product, x.product.currentQuantity)}${x.isConsignment ? ' • ${x.consignorName ?? 'Consignment'}' : ''}',
                                    ),
                                    if (out || low)
                                      Text(
                                        out ? 'OUT OF STOCK' : 'LOW STOCK',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          fontWeight: FontWeight.w700,
                                          shadows: low
                                              ? [
                                                  Shadow(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error
                                                        .withValues(alpha: .7),
                                                    blurRadius: 8,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      )
                                    else
                                      const Text('IN STOCK'),
                                  ],
                                ),
                                trailing: FilledButton(
                                  onPressed: () => stock(x),
                                  child: Text(
                                    x.isConsignment
                                        ? 'Receive Consignment'
                                        : 'Stock In',
                                  ),
                                ),
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
    ),
  );

  Widget _compactBody() => FutureBuilder<List<RestockItem>>(
    future: data,
    builder: (_, snapshot) {
      final visible = (snapshot.data ?? const <RestockItem>[])
          .where((item) => item.product.name.toLowerCase().contains(search))
          .toList();
      Widget? state;
      if (snapshot.hasError) {
        state = AppStateView.error(
          title: 'Could not load restock list',
          actionLabel: 'Try Again',
          onAction: () => setState(reload),
        );
      } else if (!snapshot.hasData) {
        state = const AppLoadingView(label: 'Loading restock list…');
      } else if (visible.isEmpty) {
        final stocked = search.isEmpty && filter == 'NEEDS';
        state = AppStateView(
          icon: stocked ? Icons.inventory_2_outlined : Icons.search_off,
          title: stocked
              ? 'All products are sufficiently stocked'
              : 'No products match this view',
          message: stocked
              ? 'Low-stock products appear here when they reach their Low Stock Alert At setting.'
              : 'Try another filter or search to find a product.',
          actionLabel: 'View All Stock',
          onAction: () => setState(() {
            filter = 'ALL';
            search = '';
            reload();
          }),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: visible.length + 2 + (state == null ? 0 : 1),
        itemBuilder: (_, index) {
          if (index == 0) return _compactSummary();
          if (index == 1) return _compactFilters();
          if (state != null) return SizedBox(height: 280, child: state);
          return _compactCard(visible[index - 2]);
        },
      );
    },
  );

  Widget _compactSummary() => FutureBuilder<List<RestockItem>>(
    future: allData,
    builder: (_, snapshot) {
      final items = snapshot.data ?? const <RestockItem>[];
      final low = items
          .where(
            (item) =>
                item.product.currentQuantity > 0 &&
                item.product.currentQuantity <= item.product.minimumStockLevel,
          )
          .length;
      final out = items
          .where((item) => item.product.currentQuantity <= 0)
          .length;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Chip(label: Text('Needs Restock: ${low + out}')),
              Chip(label: Text('Low Stock: $low')),
              Chip(label: Text('Out of Stock: $out')),
            ],
          ),
        ),
      );
    },
  );

  Widget _compactFilters() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          hintText: 'Search products',
          onChanged: (value) =>
              setState(() => search = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              for (final option in [
                ('NEEDS', 'Needs Restock'),
                ('ALL', 'All'),
                ('LOW', 'Low Stock'),
                ('OUT', 'Out of Stock'),
                ('SELECTA', 'Selecta'),
              ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: filter == option.$1,
                  onSelected: (_) => setState(() {
                    filter = option.$1;
                    reload();
                  }),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _compactCard(RestockItem item) {
    final quantity = item.product.currentQuantity;
    final out = quantity <= 0;
    final low = !out && quantity <= item.product.minimumStockLevel;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ProductImage(path: item.product.photoPath),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.product.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Current: ${productQuantityText(item.product, quantity)}',
                        ),
                        if (item.isConsignment && item.consignorName != null)
                          Text(item.consignorName!),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                out
                    ? 'OUT OF STOCK'
                    : low
                    ? 'LOW STOCK'
                    : 'IN STOCK',
                style: TextStyle(
                  color: out || low
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => stock(item),
                child: Text(
                  item.isConsignment ? 'Receive Consignment' : 'Stock In',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, int value, IconData icon, [Color? accent]) =>
      SizedBox(
        width: 210,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: (accent ?? Theme.of(context).colorScheme.primary)
                        .withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 26,
                    color: accent ?? Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label),
                      Text(
                        '$value',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
