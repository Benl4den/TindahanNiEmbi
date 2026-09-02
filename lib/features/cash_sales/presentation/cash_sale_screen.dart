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
  CashSaleResult? lastSale;
  int todayTotal = 0;
  @override
  void initState() {
    super.initState();
    products = widget.products;
    c = ProductSelectionController(products);
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    if (widget.repository == null) return;
    final values = await Future.wait([
      widget.repository!.latest(),
      widget.repository!.todayTotal(),
    ]);
    if (mounted) {
      setState(() {
        lastSale = values[0] as CashSaleResult?;
        todayTotal = values[1] as int;
      });
    }
  }

  String money(int cents) => '₱${(cents / 100).toStringAsFixed(2)}';

  Future<void> save() async {
    if (saving || c.totalCentavos == 0) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('Complete Sale?'),
        content: Text(
          '${c.selectedProducts.length} products\nTotal: ${money(c.totalCentavos)}',
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
        if (result != null) lastSale = result;
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(child: _summary('Today’s Sales', money(todayTotal))),
              Expanded(
                child: _summary(
                  'Low Stock',
                  '${products.where((p) => p.currentQuantity > 0 && p.currentQuantity <= p.minimumStockLevel).length}',
                ),
              ),
              Expanded(
                child: _summary(
                  'Out of Stock',
                  '${products.where((p) => p.currentQuantity == 0).length}',
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
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Current Sale',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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
                      return ListTile(
                        title: Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text('$q × ${money(p.sellingPriceCentavos)}'),
                        trailing: Text(money(q * p.sellingPriceCentavos)),
                      );
                    }).toList(),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(20),
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
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: c.totalCentavos == 0 || saving ? null : save,
                  icon: const Icon(Icons.check_circle),
                  label: Text(saving ? 'Saving...' : 'Review & Complete Sale'),
                ),
                if (widget.onUtang != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: c.totalCentavos == 0 || saving
                        ? null
                        : checkoutUtang,
                    icon: const Icon(Icons.people_alt),
                    label: const Text('UTANG'),
                  ),
                ],
                const SizedBox(height: 16),
                _lastSaleCard(),
                if (widget.repository != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('sales-transaction-history'),
                    onPressed: _showHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('Cash & UTANG History'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _lastSaleCard() {
    final sale = lastSale;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer
            .withValues(alpha: .38),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .28),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: sale == null
          ? const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LAST SALE',
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
                        'LAST SALE',
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
                const SizedBox(height: 8),
                Text(
                  money(sale.totalCentavos),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  '${sale.itemCount} items • ${_saleWhen(sale.occurredAt.toLocal())}',
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.repository == null
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) => Dialog(
                            insetPadding: const EdgeInsets.all(16),
                            clipBehavior: Clip.antiAlias,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: 760,
                                maxHeight: 820,
                              ),
                              child: SaleDetailsScreen(
                                repository: widget.repository!,
                                saleId: sale.id,
                                reversals: widget.reversals,
                              ),
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('View Sale Details'),
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

  Future<void> _showHistory() async {
    var filter = 'ALL';
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setModal) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 820),
            child: Column(
              children: [
                ListTile(
                  title: const Text('Sales Transactions'),
                  trailing: IconButton(
                    onPressed: () => Navigator.pop(dialog),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final x in const [
                      ('ALL', 'All'),
                      ('CASH', 'Cash'),
                      ('UTANG', 'UTANG'),
                    ])
                      ChoiceChip(
                        label: Text(x.$2),
                        selected: filter == x.$1,
                        onSelected: (_) => setModal(() => filter = x.$1),
                      ),
                  ],
                ),
                Expanded(
                  child: FutureBuilder<List<SalesHistoryEntry>>(
                    future: widget.repository!.history(type: filter),
                    builder: (_, s) => !s.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : s.data!.isEmpty
                        ? const Center(child: Text('No transactions found.'))
                        : ListView.builder(
                            itemCount: s.data!.length,
                            itemBuilder: (_, i) {
                              final e = s.data![i],
                                  local = e.occurredAt.toLocal();
                              return ListTile(
                                leading: Icon(
                                  e.isUtang ? Icons.people_alt : Icons.payments,
                                ),
                                title: Text(
                                  '${e.isUtang ? 'UTANG' : 'Cash Sale'} • ${e.reference}',
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
                                trailing: Text(money(e.totalCentavos)),
                                onTap: () {
                                  Navigator.pop(dialog);
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => _showHistoryDetails(e),
                                  );
                                },
                              );
                            },
                          ),
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
        title: Text('UTANG • ${entry.reference}'),
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
                  Text('Corrected by UTANG #${entry.correctedById}'),
                if (entry.correctionOfId != null)
                  Text('Correction of UTANG #${entry.correctionOfId}'),
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

  Widget _summary(String label, String value) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    ),
  );
}
