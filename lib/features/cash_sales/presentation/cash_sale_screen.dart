import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/product.dart';
import '../../../models/utang_draft.dart';
import '../../../repositories/cash_sale_repository.dart';
import '../../../repositories/reversal_repository.dart';
import '../../transactions/product_selection_controller.dart';
import 'sale_details_screen.dart';

class CashSaleScreen extends StatefulWidget {
  const CashSaleScreen({
    super.key,
    required this.products,
    this.repository,
    this.saveSale,
    this.loadProducts,
    this.embedded = false,
    this.onUtang,
    this.categoryNames = const {},
    this.frequentProductNames = const {},
    this.selectaProductIds = const {},
    this.reversals,
  }) : assert(repository != null || saveSale != null);
  final List<Product> products;
  final CashSaleRepository? repository;
  final Future<int> Function(List<UtangItemDraft>)? saveSale;
  final Future<List<Product>> Function()? loadProducts;
  final bool embedded;
  final Future<bool> Function(List<UtangItemDraft>)? onUtang;
  final Map<int, String> categoryNames;
  final Set<String> frequentProductNames;
  final Set<int> selectaProductIds;
  final ReversalRepository? reversals;
  @override
  State<CashSaleScreen> createState() => _State();
}

class _State extends State<CashSaleScreen> {
  late ProductSelectionController c;
  late List<Product> products;
  String search = '';
  String filter = 'ALL';
  bool saving = false;
  SalesHistoryEntry? lastTransaction;
  int todaySalesTotal = 0;
  int todayTransactionCount = 0;
  @override
  void initState() {
    super.initState();
    products = widget.products;
    c = ProductSelectionController(products);
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (widget.repository == null) return;
    final values = await Future.wait<Object?>([
      widget.repository!.latestTransaction(),
      widget.repository!.history(),
    ]);
    if (mounted) {
      final now = DateTime.now();
      final today = (values[1]! as List<SalesHistoryEntry>).where((x) {
        final d = x.occurredAt.toLocal();
        return x.status == 'POSTED' &&
            d.year == now.year &&
            d.month == now.month &&
            d.day == now.day;
      }).toList();
      setState(() {
        lastTransaction = values[0] as SalesHistoryEntry?;
        todaySalesTotal = today.fold(0, (sum, x) => sum + x.totalCentavos);
        todayTransactionCount = today.length;
      });
    }
  }

  String money(int cents) => '₱${(cents / 100).toStringAsFixed(2)}';

  Future<void> save() async {
    if (saving || c.totalCentavos == 0) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.receipt_long),
            SizedBox(width: 10),
            Text('Review Cash Sale'),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'CASH',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.green,
                  ),
                ),
              ),
              const Divider(),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: c.selectedProducts.length,
                    separatorBuilder: (_, _) => const Divider(height: 12),
                    itemBuilder: (_, i) {
                      final p = c.selectedProducts[i], q = c.quantityFor(p);
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text('$q × ${money(p.sellingPriceCentavos)}'),
                              ],
                            ),
                          ),
                          Text(
                            money(q * p.sellingPriceCentavos),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    money(c.totalCentavos),
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            child: const Text('Complete Sale'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => saving = true);
    try {
      final items = c.selectedProducts
          .map(
            (p) => UtangItemDraft(productId: p.id, quantity: c.quantityFor(p)),
          )
          .toList();
      CashSaleResult? result;
      if (widget.saveSale != null) {
        await widget.saveSale!(items);
      } else {
        result = await widget.repository!.saveWithResult(items);
      }
      final fresh =
          await (widget.loadProducts?.call() ?? Future.value(products));
      if (!mounted) return;
      setState(() {
        products = fresh;
        c = ProductSelectionController(fresh);
      });
      await _loadSummary();
      if (result != null && mounted) {
        await showDialog<void>(
          context: context,
          builder: (x) => AlertDialog(
            title: const Text('Sale Completed'),
            content: Text(
              '${result!.reference}\n\nTotal\n${money(result.totalCentavos)}',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(x),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The sale could not be completed. Your cart has been kept. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  List<UtangItemDraft> get _items => c.selectedProducts
      .map((p) => UtangItemDraft(productId: p.id, quantity: c.quantityFor(p)))
      .toList();
  Future<void> checkoutUtang() async {
    if (widget.onUtang == null || c.totalCentavos == 0) return;
    final ok = await widget.onUtang!(_items);
    if (ok) {
      final fresh =
          await (widget.loadProducts?.call() ?? Future.value(products));
      if (mounted) {
        setState(() {
          products = fresh;
          c = ProductSelectionController(fresh);
        });
      }
    }
  }

  Future<void> clearCart() async {
    if (c.selectedProducts.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Clear current sale?'),
        content: const Text('The selected products will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear Sale'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) setState(c.clear);
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.sizeOf(context).width >= 900;
    final content = Row(
      children: [
        Expanded(flex: landscape ? 3 : 1, child: _catalog()),
        if (landscape) SizedBox(width: 360, child: _cart()),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Sales')),
      body: content,
      floatingActionButton: landscape
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                  height: MediaQuery.sizeOf(context).height * .8,
                  child: _cart(),
                ),
              ),
              icon: const Icon(Icons.shopping_cart),
              label: Text('Cart (${c.selectedProducts.length})'),
            ),
    );
  }

  Widget _catalog() {
    final shown = products
        .where((p) => p.name.toLowerCase().contains(search.toLowerCase()))
        .where(
          (p) => switch (filter) {
            'FREQUENT' => widget.frequentProductNames.contains(p.name),
            'SELECTA' => widget.selectaProductIds.contains(p.id),
            'ALL' => true,
            _ => p.categoryId.toString() == filter,
          },
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search products...',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: [
              for (final item in <(String, String)>[
                ('ALL', 'All'),
                if (widget.frequentProductNames.isNotEmpty)
                  ('FREQUENT', 'Frequently Sold'),
                if (widget.selectaProductIds.isNotEmpty) ('SELECTA', 'Selecta'),
                ...widget.categoryNames.entries.map(
                  (entry) => (entry.key.toString(), entry.value),
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item.$2),
                    selected: filter == item.$1,
                    onSelected: (_) => setState(() => filter = item.$1),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) {
              final cols = box.maxWidth >= 900
                  ? 4
                  : box.maxWidth >= 600
                  ? 3
                  : 2;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  childAspectRatio: .76,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: shown.length,
                itemBuilder: (_, i) => _product(shown[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _product(Product p) {
    final q = c.quantityFor(p),
        out = p.currentQuantity == 0,
        low = !out && p.currentQuantity <= p.minimumStockLevel;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: out ? null : () => setState(() => c.increase(p)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.file(
                File(p.photoPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFE9EEE9),
                  child: Icon(Icons.inventory_2_outlined, size: 54),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    money(p.sellingPriceCentavos),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  Text(
                    out
                        ? 'Out of Stock'
                        : low
                        ? '${p.currentQuantity} left • Low Stock'
                        : '${p.currentQuantity} in stock',
                    style: TextStyle(
                      color: out
                          ? Colors.red.shade700
                          : low
                          ? Colors.orange.shade800
                          : Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (q > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton.filledTonal(
                          onPressed: () => setState(() => c.decrease(p)),
                          icon: const Icon(Icons.remove),
                        ),
                        Text(
                          '$q',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton.filled(
                          onPressed: q >= p.currentQuantity
                              ? null
                              : () => setState(() => c.increase(p)),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: out
                            ? null
                            : () => setState(() => c.increase(p)),
                        child: const Text('Add'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cart() => Material(
    color: Colors.white,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Current Sale',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: c.selectedProducts.isEmpty ? null : clearCart,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    backgroundColor: Colors.red.shade50,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Sale'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: c.selectedProducts.isEmpty
                ? const Center(
                    child: Text(
                      'Your cart is empty.\nSelect products to begin a sale.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView(
                    children: c.selectedProducts.map((p) {
                      final q = c.quantityFor(p);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer
                              .withValues(alpha: .16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary
                                .withValues(alpha: .16),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Image.file(
                                  File(p.photoPath),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const ColoredBox(
                                    color: Color(0xffeeeeee),
                                    child: Icon(Icons.inventory_2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Remove item',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            setState(() => c.remove(p)),
                                        icon: const Icon(Icons.close, size: 19),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '$q × ${money(p.sellingPriceCentavos)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      const Spacer(),
                                      IconButton.filledTonal(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            setState(() => c.decrease(p)),
                                        icon: const Icon(
                                          Icons.remove,
                                          size: 18,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Text(
                                          '$q',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      IconButton.filled(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: q >= p.currentQuantity
                                            ? null
                                            : () =>
                                                  setState(() => c.increase(p)),
                                        icon: const Icon(Icons.add, size: 18),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      money(q * p.sellingPriceCentavos),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      money(c.totalCentavos),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: c.totalCentavos == 0 || saving ? null : save,
                  icon: const Icon(Icons.check_circle),
                  label: Text(saving ? 'Saving...' : 'Review & Complete Sale'),
                ),
                if (widget.onUtang != null) ...[
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: c.totalCentavos == 0 || saving
                        ? null
                        : checkoutUtang,
                    icon: const Icon(Icons.people_alt),
                    label: const Text('Sell on Credit'),
                  ),
                ],
                const SizedBox(height: 8),
                _lastTransactionCard(),
                if (widget.repository != null) ...[
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showHistory(todayOnly: true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.today, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              "TODAY'S SALES",
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                money(todaySalesTotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                '$todayTransactionCount transactions',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _showHistory,
                      icon: const Icon(Icons.history, size: 19),
                      label: const Text('Cash & Credit History'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _lastTransactionCard() {
    final sale = lastTransaction;
    final utang = sale?.isUtang ?? false;
    final accent = utang
        ? Colors.orange.shade800
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .08),
        border: Border.all(color: accent.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: sale == null
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LAST TRANSACTION',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 10),
                Text('No sales recorded yet.'),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'LAST TRANSACTION',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        sale.reference,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        money(sale.totalCentavos),
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showHistoryDetails(sale),
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('View Details'),
                    ),
                  ],
                ),
                Text(
                  '${utang ? 'Credit • ${sale.customerName}' : 'Cash'} • ${_saleWhen(sale.occurredAt.toLocal())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
    );
  }

  String _saleWhen(DateTime value) {
    final now = DateTime.now(),
        sameDay =
            now.year == value.year &&
            now.month == value.month &&
            now.day == value.day;
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(value));
    return '${sameDay ? 'Today' : MaterialLocalizations.of(context).formatShortDate(value)} • $time';
  }

  Future<void> _showHistory({bool todayOnly = false}) async {
    var filter = 'ALL';
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setModal) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          todayOnly ? "Today's Sales" : 'All Transactions',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialog),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final x in const [
                          ('ALL', 'All'),
                          ('CASH', 'Cash'),
                          ('UTANG', 'Credit'),
                        ])
                          ChoiceChip(
                            label: Text(x.$2),
                            selected: filter == x.$1,
                            onSelected: (_) => setModal(() => filter = x.$1),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: FutureBuilder<List<SalesHistoryEntry>>(
                    future: widget.repository!.history(type: filter),
                    builder: (_, s) {
                      final entries = (s.data ?? const <SalesHistoryEntry>[])
                          .where((e) {
                            if (!todayOnly) return true;
                            final d = e.occurredAt.toLocal(),
                                now = DateTime.now();
                            return d.year == now.year &&
                                d.month == now.month &&
                                d.day == now.day;
                          })
                          .toList();
                      return !s.hasData
                          ? const Center(child: CircularProgressIndicator())
                          : entries.isEmpty
                          ? const Center(child: Text('No transactions found.'))
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: entries.length,
                              separatorBuilder: (_, _) => const Divider(
                                height: 1,
                                indent: 76,
                                endIndent: 20,
                              ),
                              itemBuilder: (_, i) {
                                final e = entries[i],
                                    local = e.occurredAt.toLocal();
                                return ListTile(
                                  leading: Icon(
                                    e.isUtang
                                        ? Icons.people_alt
                                        : Icons.payments,
                                  ),
                                  title: Text(
                                    '${e.isUtang ? 'Credit Sale' : 'Cash Sale'} • ${e.reference}',
                                  ),
                                  subtitle: Text(
                                    '${e.customerName == null ? '' : '${e.customerName} • '}${MaterialLocalizations.of(context).formatMediumDate(local)} • ${TimeOfDay.fromDateTime(local).format(context)}\n'
                                    '${e.itemCount} items • ${e.correctedById != null
                                        ? 'CORRECTED'
                                        : e.status == 'REVERSED'
                                        ? 'REVERSED'
                                        : 'COMPLETED'}'
                                    '${e.correctionOfId == null ? '' : '\nCorrection of #${e.correctionOfId}'}',
                                  ),
                                  trailing: Text(
                                    money(e.totalCentavos),
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: e.isUtang
                                          ? Colors.orange.shade800
                                          : Theme.of(context)
                                                .colorScheme
                                                .primary,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.pop(dialog);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                          (_) => _showHistoryDetails(e),
                                        );
                                  },
                                );
                              },
                            );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHistoryDetails(SalesHistoryEntry entry) async {
    if (!entry.isUtang) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
            child: SaleDetailsScreen(
              repository: widget.repository!,
              saleId: entry.id,
              reversals: widget.reversals,
            ),
          ),
        ),
      );
      return;
    }
    final items = await widget.repository!.utangItems(entry.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Credit Sale • ${entry.reference}'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.customerName != null)
                  Text('Customer: ${entry.customerName}'),
                Text(_saleWhen(entry.occurredAt.toLocal())),
                const SizedBox(height: 8),
                Text(
                  'Status: ${entry.correctedById != null
                      ? 'CORRECTED'
                      : entry.status == 'REVERSED'
                      ? 'REVERSED'
                      : 'COMPLETED'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (entry.correctedById != null)
                  Text('Corrected by Credit Sale #${entry.correctedById}'),
                if (entry.correctionOfId != null)
                  Text('Correction of Credit Sale #${entry.correctionOfId}'),
                const Divider(),
                ...items.map(
                  (x) => ListTile(
                    title: Text(x['product_name_snapshot']! as String),
                    subtitle: Text(
                      '${x['quantity']} × ${money(x['unit_price_centavos']! as int)}',
                    ),
                    trailing: Text(money(x['line_total_centavos']! as int)),
                  ),
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${entry.itemCount} items\nTotal: ${money(entry.totalCentavos)}',
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
