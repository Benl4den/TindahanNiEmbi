import 'dart:io';

import 'package:flutter/material.dart';

import '../../../repositories/inventory_repository.dart';
import '../../../repositories/operations_repository.dart';

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
  String filter = 'ALL';
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
    allData = widget.operations.restock();
  }

  Future<void> stock(RestockItem item) async {
    if (item.isConsignment) {
      widget.openConsignment();
      return;
    }
    final c = TextEditingController(text: '${item.suggested}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: Text('Stock In — ${item.product.name}'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            child: const Text('Stock In'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.inventory.stockIn(
          productId: item.product.id,
          quantity: int.tryParse(c.text) ?? 0,
        );
        if (mounted) setState(reload);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is InvalidInventoryOperation
                    ? e.message
                    : 'Could not stock in.',
              ),
            ),
          );
        }
      }
    }
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric(
                    'Products Needing Restock',
                    low + out,
                    Icons.add_shopping_cart,
                  ),
                  _metric('Low Stock', low, Icons.warning_amber),
                  _metric('Out of Stock', out, Icons.error_outline),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final x in [
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
              SizedBox(
                width: 300,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search products',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      setState(() => search = v.trim().toLowerCase()),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<RestockItem>>(
            future: data,
            builder: (_, s) => !s.hasData
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: s.data!
                        .where(
                          (x) => x.product.name.toLowerCase().contains(search),
                        )
                        .length,
                    itemBuilder: (_, i) {
                      final visible = s.data!
                          .where(
                            (x) =>
                                x.product.name.toLowerCase().contains(search),
                          )
                          .toList();
                      final x = visible[i];
                      final out = x.product.currentQuantity == 0;
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(18),
                          leading: SizedBox(
                            width: 64,
                            height: 64,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: File(x.product.photoPath).existsSync()
                                  ? Image.file(
                                      File(x.product.photoPath),
                                      fit: BoxFit.cover,
                                    )
                                  : const ColoredBox(
                                      color: Color(0xffeeeeee),
                                      child: Icon(Icons.inventory_2),
                                    ),
                            ),
                          ),
                          title: Text(
                            x.product.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          subtitle: Text(
                            'Current: ${x.product.currentQuantity}   Minimum: ${x.product.minimumStockLevel}\nSuggested Restock: +${x.suggested}${x.isConsignment ? ' • Consignment' : ''}\n${out ? 'OUT OF STOCK' : 'LOW STOCK'}',
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
                      );
                    },
                  ),
          ),
        ),
      ],
    ),
  );

  Widget _metric(String label, int value, IconData icon) => SizedBox(
    width: 230,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 32),
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
