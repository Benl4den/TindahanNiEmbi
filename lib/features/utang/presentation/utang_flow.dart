import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/customer.dart';
import '../../../models/product.dart';
import '../../../models/utang_draft.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/payment_repository.dart';
import '../../payments/presentation/payment_screen.dart';
import '../../../repositories/utang_repository.dart';
import '../../customers/presentation/customer_form_screen.dart';
import '../../transactions/product_selection_controller.dart';
import 'utang_customer_card.dart';

class UtangCustomerScreen extends StatefulWidget {
  const UtangCustomerScreen({
    super.key,
    required this.customers,
    required this.products,
    required this.utang,
    required this.payments,
  });
  final CustomerRepository customers;
  final ProductRepository products;
  final UtangRepository utang;
  final PaymentRepository payments;
  @override
  State<UtangCustomerScreen> createState() => _UtangCustomerScreenState();
}

class _UtangCustomerScreenState extends State<UtangCustomerScreen> {
  final q = TextEditingController();
  late Future<List<Customer>> list;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => list = widget.customers.searchActive(q.text);
  Future<void> create() async {
    final existingIds = (await widget.customers.searchActive())
        .map((customer) => customer.id)
        .toSet();
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(repository: widget.customers),
      ),
    );
    if (ok == true && mounted) {
      final customers = await widget.customers.searchActive();
      if (!mounted) return;
      setState(reload);
      final created = customers.where((c) => !existingIds.contains(c.id));
      if (created.isNotEmpty) await openCustomer(created.first);
    }
  }

  Future<void> newUtang(Customer c) async {
    final p = await widget.products.searchActive();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UtangProductsScreen(
          customer: c,
          products: p,
          customers: widget.customers,
          utang: widget.utang,
        ),
      ),
    );
  }

  Future<void> openCustomer(Customer c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerUtangScreen(
          customerId: c.id,
          customers: widget.customers,
          products: widget.products,
          utang: widget.utang,
          payments: widget.payments,
        ),
      ),
    );
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MGA UTANGAN')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: q,
            decoration: const InputDecoration(
              labelText: 'Search UTANGAN...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(reload),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Customer>>(
            future: list,
            builder: (_, s) => s.hasData
                ? s.data!.isEmpty
                      ? const Center(
                          child: Text(
                            'No UTANGAN Yet.\nAdd a customer to start tracking UTANG.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: s.data!
                              .map(
                                (c) => UtangCustomerCard(
                                  customer: c,
                                  onTap: () => openCustomer(c),
                                ),
                              )
                              .toList(),
                        )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: create,
      icon: const Icon(Icons.person_add),
      label: const Text('Add New UTANGAN'),
    ),
  );
}

class UtangProductsScreen extends StatefulWidget {
  const UtangProductsScreen({
    super.key,
    required this.customer,
    required this.products,
    required this.customers,
    required this.utang,
  });
  final Customer customer;
  final List<Product> products;
  final CustomerRepository customers;
  final UtangRepository utang;
  @override
  State<UtangProductsScreen> createState() => _UtangProductsScreenState();
}

class _UtangProductsScreenState extends State<UtangProductsScreen> {
  late final ProductSelectionController c;
  String q = '';
  @override
  void initState() {
    super.initState();
    c = ProductSelectionController(widget.products);
  }

  @override
  Widget build(BuildContext context) {
    final shown = c.products
        .where((p) => p.name.toLowerCase().contains(q.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('New UTANG — ${widget.customer.fullName}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: AppStrings.searchProducts,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: .72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: shown.length,
              itemBuilder: (_, i) {
                final p = shown[i], qty = c.quantityFor(p);
                return Card(
                  child: Column(
                    children: [
                      Expanded(
                        child: Image.file(
                          File(p.photoPath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.inventory_2, size: 60),
                        ),
                      ),
                      Text(
                        p.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '₱${(p.sellingPriceCentavos / 100).toStringAsFixed(2)} • Stock: ${p.currentQuantity}',
                      ),
                      if (p.currentQuantity == 0)
                        const Text(AppStrings.outOfStock)
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton.filled(
                              onPressed: () => setState(() => c.decrease(p)),
                              icon: const Icon(Icons.remove),
                              iconSize: 30,
                            ),
                            Text(
                              '$qty',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            IconButton.filled(
                              onPressed: () => setState(() => c.increase(p)),
                              icon: const Icon(Icons.add),
                              iconSize: 30,
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Total: ₱${(c.totalCentavos / 100).toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  FilledButton(
                    onPressed: c.totalCentavos == 0
                        ? null
                        : () async {
                            final saved = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => UtangReviewScreen(
                                  customer: widget.customer,
                                  selection: c,
                                  customers: widget.customers,
                                  utang: widget.utang,
                                ),
                              ),
                            );
                            if (saved == true && context.mounted) {
                              Navigator.pop(context, true);
                            }
                          },
                    child: const Text('Review UTANG'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UtangReviewScreen extends StatefulWidget {
  const UtangReviewScreen({
    super.key,
    required this.customer,
    required this.selection,
    required this.customers,
    required this.utang,
  });
  final Customer customer;
  final ProductSelectionController selection;
  final CustomerRepository customers;
  final UtangRepository utang;
  @override
  State<UtangReviewScreen> createState() => _UtangReviewScreenState();
}

class _UtangReviewScreenState extends State<UtangReviewScreen> {
  bool saving = false;
  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.utang.save(
        UtangDraft(
          customerId: widget.customer.id,
          items: widget.selection.selectedProducts
              .map(
                (p) => UtangItemDraft(
                  productId: p.id,
                  quantity: widget.selection.quantityFor(p),
                ),
              )
              .toList(),
        ),
      );
      widget.selection.clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('UTANG saved.')));
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CustomerDetails>(
    future: widget.customers.details(widget.customer.id),
    builder: (_, s) {
      if (!s.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final old = s.data!.customer.balanceCentavos,
          newDebt = widget.selection.totalCentavos;
      return Scaffold(
        appBar: AppBar(title: const Text('Review UTANG')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.customer.fullName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            ...widget.selection.selectedProducts.map(
              (p) => ListTile(
                title: Text(p.name),
                subtitle: Text(
                  '₱${(p.sellingPriceCentavos / 100).toStringAsFixed(2)} × ${widget.selection.quantityFor(p)}',
                ),
                trailing: Text(
                  '₱${(p.sellingPriceCentavos * widget.selection.quantityFor(p) / 100).toStringAsFixed(2)}',
                ),
              ),
            ),
            Text('New UTANG: ₱${(newDebt / 100).toStringAsFixed(2)}'),
            Text('Previous UTANG: ₱${(old / 100).toStringAsFixed(2)}'),
            Text(
              'Total UTANG: ₱${((old + newDebt) / 100).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: saving ? null : save,
              child: const Text('Save UTANG'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(AppStrings.back),
            ),
          ],
        ),
      );
    },
  );
}

class CustomerUtangScreen extends StatefulWidget {
  const CustomerUtangScreen({
    super.key,
    required this.customerId,
    required this.customers,
    required this.products,
    required this.utang,
    required this.payments,
  });
  final int customerId;
  final CustomerRepository customers;
  final ProductRepository products;
  final UtangRepository utang;
  final PaymentRepository payments;
  @override
  State<CustomerUtangScreen> createState() => _CustomerUtangState();
}

class _CustomerUtangState extends State<CustomerUtangScreen> {
  late Future<CustomerDetails> data;
  String filter = 'All';
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => data = widget.customers.details(widget.customerId);
  Future<void> newUtang(Customer customer) async {
    final products = await widget.products.searchActive();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UtangProductsScreen(
          customer: customer,
          products: products,
          customers: widget.customers,
          utang: widget.utang,
        ),
      ),
    );
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('UTANGAN Details')),
    body: FutureBuilder<CustomerDetails>(
      future: data,
      builder: (_, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final d = s.data!,
            entries = d.ledger
                .where(
                  (e) =>
                      filter == 'All' ||
                      (filter == 'UTANG'
                          ? e.type.startsWith('UTANG')
                          : e.type.startsWith('PAYMENT')),
                )
                .toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              d.customer.fullName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Current UTANG'),
                          Text(
                            _money(d.customer.balanceCentavos),
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: d.customer.balanceCentavos > 0
                                  ? Colors.orange.shade800
                                  : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => newUtang(d.customer),
                      icon: const Icon(Icons.add),
                      label: const Text('New UTANG'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: d.customer.balanceCentavos <= 0
                          ? null
                          : () async {
                              final ok = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PaymentScreen(
                                    customer: d.customer,
                                    repository: widget.payments,
                                  ),
                                ),
                              );
                              if (ok == true && mounted) setState(reload);
                            },
                      icon: const Icon(Icons.payments),
                      label: const Text('Record Payment'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: ['All', 'UTANG', 'Payments']
                  .map(
                    (x) => ChoiceChip(
                      label: Text(x),
                      selected: filter == x,
                      onSelected: (_) => setState(() => filter = x),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            ...entries.map(
              (e) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    child: Icon(
                      e.type.startsWith('UTANG')
                          ? Icons.receipt_long
                          : Icons.payments,
                    ),
                  ),
                  title: Text(e.type.startsWith('UTANG') ? 'UTANG' : 'Payment'),
                  subtitle: Text(
                    '${_date(e.occurredAt.toLocal())}\n${e.itemCount == null ? '' : '${e.itemCount} products'}',
                  ),
                  trailing: e.type == 'UTANG'
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '+${_money(e.amountCentavos.abs())}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                              ),
                            ),
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'View Details',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Icon(Icons.chevron_right),
                              ],
                            ),
                          ],
                        )
                      : Text(
                          '-${_money(e.amountCentavos.abs())}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                  onTap: e.type == 'UTANG' && e.utangTransactionId != null
                      ? () => _showDetails(d, e)
                      : null,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
  String _money(int c) => '₱${(c / 100).toStringAsFixed(2)}';
  String _date(DateTime d) =>
      '${MaterialLocalizations.of(context).formatMediumDate(d)} • ${TimeOfDay.fromDateTime(d).format(context)}';
  Future<void> _showDetails(
    CustomerDetails details,
    CustomerLedgerEntry entry,
  ) {
    final ordered = details.ledger.toList()
      ..sort((a, b) {
        final time = a.occurredAt.compareTo(b.occurredAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    var previous = 0;
    for (final item in ordered) {
      if (item.id == entry.id) break;
      previous += item.amountCentavos;
    }
    return showDialog<void>(
      context: context,
      builder: (_) => UtangDetailsDialog(
        repository: widget.customers,
        transactionId: entry.utangTransactionId!,
        previousCentavos: previous,
        resultingCentavos: previous + entry.amountCentavos,
      ),
    );
  }
}

class UtangDetailsDialog extends StatelessWidget {
  const UtangDetailsDialog({
    super.key,
    required this.repository,
    required this.transactionId,
    required this.previousCentavos,
    required this.resultingCentavos,
  });
  final CustomerRepository repository;
  final int transactionId;
  final int previousCentavos, resultingCentavos;
  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 680,
        maxHeight: MediaQuery.sizeOf(context).height * .86,
      ),
      child: FutureBuilder<Map<String, Object?>>(
        future: repository.utangDetails(transactionId),
        builder: (_, s) {
          if (!s.hasData) {
            return const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final d = s.data!, items = d['items']! as List<Map<String, Object?>>;
          final at = DateTime.parse(d['occurred_at']! as String).toLocal();
          final pieces = items.fold<int>(
            0,
            (n, x) => n + (x['quantity']! as int),
          );
          String money(int c) => '₱${(c / 100).toStringAsFixed(2)}';
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UTANG DETAILS',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            d['reference']! as String,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  d['full_name']! as String,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${MaterialLocalizations.of(context).formatFullDate(at)}\n${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
                ),
                const Divider(height: 28),
                const Text(
                  'PRODUCTS',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Expanded(
                  child: ListView(
                    children: items
                        .map(
                          (x) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(x['product_name_snapshot']! as String),
                            subtitle: Text(
                              '${x['quantity']} × ${money(x['unit_price_centavos']! as int)}',
                            ),
                            trailing: Text(
                              money(x['line_total_centavos']! as int),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const Divider(),
                Text('${items.length} product types • $pieces total pieces'),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'UTANG TOTAL',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      money(d['total_centavos']! as int),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ],
                ),
                _balance('Previous UTANG', money(previousCentavos)),
                _balance('Current/Resulting UTANG', money(resultingCentavos)),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
  Widget _balance(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
