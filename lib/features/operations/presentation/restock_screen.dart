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
  final VoidCallback openConsignment;
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
      widget.openConsignment();
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
    body: Column(
      children: [
        FutureBuilder<List<RestockItem>>(
          future: allData,
          builder: (_, s) {
            final items = s.data ?? const <RestockItem>[];
            final low = items
                .where(
                  (x) =>
                      x.product.currentQuantity > 0 &&
                      x.product.currentQuantity <= x.product.minimumStockLevel,
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
                      'Low Stock',
                      low,
                      Icons.warning_amber,
                      Colors.orange.shade800,
                    ),
                    _metric(
                      'Out of Stock',
                      out,
                      Icons.error_outline,
                      Colors.red.shade700,
                    ),
                  ];
                  return box.maxWidth < 650
                      ? Wrap(spacing: 10, runSpacing: 10, children: cards)
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
                return const AppLoadingView(label: 'Loading restock list…');
              }
              final visible = s.data!
                  .where((x) => x.product.name.toLowerCase().contains(search))
                  .toList();
              if (visible.isEmpty) {
                return const AppStateView.empty(
                  title: 'All stocked up',
                  message: 'No products match this view or currently need replenishment.',
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
                      x.product.currentQuantity <= x.product.minimumStockLevel;
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
                            child: ProductImage(path: x.product.photoPath),
                          ),
                        ),
                        title: Text(
                          x.product.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        subtitle: Text(
                          'Current: ${standardNumber(x.product.currentQuantity)}   Minimum: ${standardNumber(x.product.minimumStockLevel)}\nSuggested Restock: +${standardNumber(x.suggested)}${x.isConsignment ? ' • Consignment' : ''}\n${out
                              ? 'OUT OF STOCK'
                              : low
                              ? 'LOW STOCK'
                              : 'IN STOCK'}',
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
  );

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
                          fontWeight: FontWeight.w900,
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
