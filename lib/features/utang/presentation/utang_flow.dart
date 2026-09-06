import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/customer.dart';
import '../../../models/product.dart';
import '../../../models/product_unit.dart';
import '../../../models/utang_draft.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/product_unit_repository.dart';
import '../../../repositories/payment_repository.dart';
import '../../../repositories/reversal_repository.dart';
import '../../../repositories/correction_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/app_refresh_controller.dart';
import '../../payments/presentation/payment_screen.dart';
import '../../../repositories/utang_repository.dart';
import '../../customers/presentation/customer_form_screen.dart';
import '../../transactions/product_selection_controller.dart';
import 'utang_customer_card.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/app_alerts.dart';

class UtangCustomerScreen extends StatefulWidget {
  const UtangCustomerScreen({
    super.key,
    required this.customers,
    required this.products,
    required this.utang,
    required this.payments,
    this.reversals,
  });
  final CustomerRepository customers;
  final ProductRepository products;
  final UtangRepository utang;
  final PaymentRepository payments;
  final ReversalRepository? reversals;
  @override
  State<UtangCustomerScreen> createState() => _UtangCustomerScreenState();
}

class _UtangCustomerScreenState extends State<UtangCustomerScreen> {
  final q = TextEditingController();
  late Future<List<Customer>> list;
  late Future<List<Customer>> allCustomers;
  @override
  void initState() {
    super.initState();
    reload();
    AppRefreshController.instance.addListener(_refreshFromChange);
  }

  void _refreshFromChange() {
    if (mounted) setState(reload);
  }

  @override
  void dispose() {
    AppRefreshController.instance.removeListener(_refreshFromChange);
    super.dispose();
  }

  void reload() {
    list = widget.customers.searchActive(q.text);
    allCustomers = widget.customers.searchActive();
  }

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
          reversals: widget.reversals,
        ),
      ),
    );
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customer Accounts')),
    body: Column(
      children: [
        FutureBuilder<List<Customer>>(
          future: allCustomers,
          builder: (_, snapshot) {
            final customers = snapshot.data ?? const <Customer>[];
            final owing = customers
                .where((x) => x.balanceCentavos > 0)
                .toList();
            final total = owing.fold<int>(
              0,
              (sum, x) => sum + x.balanceCentavos,
            );
            final highest = owing.fold<int>(
              0,
              (value, x) =>
                  x.balanceCentavos > value ? x.balanceCentavos : value,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  _utangMetric(
                    'Total Outstanding UTANG',
                    '₱${(total / 100).toStringAsFixed(2)}',
                    Colors.orange.shade800,
                  ),
                  _utangMetric(
                    'Customers with Balance',
                    '${owing.length}',
                    Colors.orange.shade800,
                  ),
                  _utangMetric(
                    'Highest Current Balance',
                    '₱${(highest / 100).toStringAsFixed(2)}',
                    Colors.red.shade700,
                  ),
                ],
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: AppSearchField(
            controller: q,
            hintText: 'Search customers...',
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
                            'No UTANGAN yet.\nAdd an UTANGAN to start tracking UTANG.',
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
      label: const Text('Add New Customer'),
    ),
  );

  Widget _utangMetric(String label, String value, Color color) => Container(
    width: 230,
    margin: const EdgeInsets.only(right: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      border: Border.all(color: color.withValues(alpha: .3)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
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
  Map<int, List<SellingOption>> options = const {};
  String q = '';
  @override
  void initState() {
    super.initState();
    c = ProductSelectionController(widget.products);
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final units = ProductUnitRepository(widget.utang.db),
        loaded = <int, List<SellingOption>>{};
    for (final product in widget.products) {
      loaded[product.id] = await units.sellingOptions(product.id);
    }
    if (mounted) setState(() => options = loaded);
  }

  Future<void> _addProduct(Product product) async {
    final choices = options[product.id] ?? const <SellingOption>[];
    final usable = choices.isEmpty
        ? [
            SellingOption(
              id: -product.id,
              productId: product.id,
              name: 'Piece',
              baseQuantity: 1,
              priceCentavos: product.sellingPriceCentavos,
              isDefault: true,
            ),
          ]
        : choices;
    final measured =
        product.baseUnitCode == 'GRAM' &&
        usable.any((x) => x.baseQuantity >= 1000);
    if (usable.length == 1 && !measured) {
      setState(() => c.add(product, usable.single));
      return;
    }
    var selected = usable.first;
    String? error;
    final quantity = TextEditingController(text: '1');
    final result = await showDialog<({SellingOption option, int value, int scale})>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: Text(product.name),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<SellingOption>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'Selling option',
                  ),
                  items: usable
                      .map(
                        (x) => DropdownMenuItem(
                          value: x,
                          child: Text(
                            '${x.name} — ₱${(x.priceCentavos / 100).toStringAsFixed(2)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (x) {
                    if (x != null) setLocal(() => selected = x);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        product.baseUnitCode == 'GRAM' &&
                            selected.baseQuantity >= 1000
                        ? 'Quantity in kg'
                        : 'Quantity',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final parsed = parseSaleQuantity(
                    quantity.text,
                    measured:
                        product.baseUnitCode == 'GRAM' &&
                        selected.baseQuantity >= 1000,
                  );
                  if (parsed.value * selected.baseQuantity % parsed.scale !=
                      0) {
                    throw const FormatException(
                      'Quantity cannot be converted exactly.',
                    );
                  }
                  Navigator.pop(dialog, (
                    option: selected,
                    value: parsed.value,
                    scale: parsed.scale,
                  ));
                } on FormatException catch (e) {
                  setLocal(() => error = e.message);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      try {
        setState(
          () => c.add(
            product,
            result.option,
            quantityValue: result.value,
            quantityScale: result.scale,
          ),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not enough stock for that quantity.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = c.products
        .where((p) => p.name.toLowerCase().contains(q.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('New UTANG Sale — ${widget.customer.fullName}'),
      ),
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
                        '₱${(p.sellingPriceCentavos / 100).toStringAsFixed(2)} • Stock: ${productQuantityText(p, p.currentQuantity)}',
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
                              onPressed: () => _addProduct(p),
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
                    child: const Text('Review UTANG Sale'),
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
          items: widget.selection.drafts,
        ),
      );
      widget.selection.clear();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('UTANG sale saved.')));
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        await showFriendlyError(
          context,
          title: 'Could Not Complete UTANG Sale',
          message: transactionFailureMessage(error),
        );
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
        appBar: AppBar(title: const Text('Review UTANG Sale')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.customer.fullName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            ...widget.selection.lines.map(
              (line) => ListTile(
                title: Text(line.product.name),
                subtitle: Text(
                  '${line.quantityText} ${line.option.name} × ₱${(line.option.priceCentavos / 100).toStringAsFixed(2)}',
                ),
                trailing: Text(
                  '₱${(line.lineTotalCentavos / 100).toStringAsFixed(2)}',
                ),
              ),
            ),
            Text('New UTANG: ₱${(newDebt / 100).toStringAsFixed(2)}'),
            Text('Previous Balance: ₱${(old / 100).toStringAsFixed(2)}'),
            Text(
              'Total UTANG Balance: ₱${((old + newDebt) / 100).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: saving ? null : save,
              child: const Text('Save UTANG Sale'),
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
    this.reversals,
  });
  final int customerId;
  final CustomerRepository customers;
  final ProductRepository products;
  final UtangRepository utang;
  final PaymentRepository payments;
  final ReversalRepository? reversals;
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
    AppRefreshController.instance.addListener(_refreshDetails);
  }

  void _refreshDetails() {
    if (mounted) setState(reload);
  }

  @override
  void dispose() {
    AppRefreshController.instance.removeListener(_refreshDetails);
    super.dispose();
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
    appBar: AppBar(title: const Text('Customer Account Details')),
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
                          const Text('Current Balance'),
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
                          const SizedBox(height: 8),
                          Text(
                            'Last UTANG Sale: ${_lastDate(d.ledger, 'UTANG')}\nLast Payment: ${_lastDate(d.ledger, 'PAYMENT')}\nOutstanding UTANG transactions: ${_outstandingCount(d)}',
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => newUtang(d.customer),
                      icon: const Icon(Icons.add),
                      label: const Text('New UTANG Sale'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: d.customer.balanceCentavos <= 0
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => Dialog(
                                  insetPadding: const EdgeInsets.all(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 620,
                                      maxHeight: 620,
                                    ),
                                    child: PaymentScreen(
                                      customer: d.customer,
                                      repository: widget.payments,
                                    ),
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
              children: ['All', 'UTANG', 'Payments', 'UTANG Products']
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
            if (filter == 'UTANG Products')
              ...d.products.map(
                (item) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.shopping_bag_outlined),
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${item.quantity} ${item.option} • ${_date(item.occurredAt.toLocal())}',
                    ),
                    trailing: Text(
                      _money(item.lineTotalCentavos),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              )
            else
              ..._groupByDay(entries).entries.map(
                (group) => Card(
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    title: Text(
                      MaterialLocalizations.of(context).formatMediumDate(
                        group.value.first.occurredAt.toLocal(),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${group.value.length} ${group.value.length == 1 ? 'transaction' : 'transactions'}',
                    ),
                    children: group.value
                        .map(
                          (e) => ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              child: Icon(
                                e.type.startsWith('UTANG')
                                    ? Icons.receipt_long
                                    : Icons.payments,
                              ),
                            ),
                            title: Text(
                              e.type.startsWith('UTANG') ? 'UTANG' : 'Payment',
                            ),
                            subtitle: Text(
                              '${TimeOfDay.fromDateTime(e.occurredAt.toLocal()).format(context)}'
                              '${e.description == null ? '' : ' • ${e.description}'}\n'
                              '${e.itemCount == null ? '' : '${e.itemCount} items'}',
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
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
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
                            onTap:
                                e.type == 'UTANG' &&
                                    e.utangTransactionId != null
                                ? () => _showDetails(d, e)
                                : e.type == 'PAYMENT' &&
                                      e.paymentId != null &&
                                      widget.reversals != null
                                ? () => _showPaymentDetails(e, d.customer)
                                : null,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
  String _money(int c) => '₱${(c / 100).toStringAsFixed(2)}';
  Map<String, List<CustomerLedgerEntry>> _groupByDay(
    List<CustomerLedgerEntry> entries,
  ) {
    final groups = <String, List<CustomerLedgerEntry>>{};
    for (final entry in entries) {
      final day = entry.occurredAt.toLocal();
      final key = '${day.year}-${day.month}-${day.day}';
      groups.putIfAbsent(key, () => []).add(entry);
    }
    return groups;
  }

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
        reversals: widget.reversals,
      ),
    );
  }

  Future<void> _reversePayment(CustomerLedgerEntry entry) async {
    final reason = TextEditingController(), pin = TextEditingController();
    String? error;
    final done = await showDialog<bool>(
      context: context,
      builder: (x) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Reverse Only?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reason,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Owner PIN',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () async {
                if (reason.text.trim().isEmpty) {
                  set(() => error = 'Reason is required.');
                  return;
                }
                try {
                  final authorized =
                      await AuthService(widget.reversals!.db)
                          .verify(pin.text) ==
                      UserRole.owner;
                  if (!authorized) {
                    throw const ReversalException('Incorrect Owner PIN.');
                  }
                  await widget.reversals!.reversePayment(
                    entry.paymentId!,
                    reason.text,
                    ownerPinAuthorized: true,
                  );
                  if (x.mounted) Navigator.pop(x, true);
                } catch (e) {
                  if (x.mounted) {
                    set(
                      () => error = e is ReversalException
                          ? e.message
                          : 'Could not reverse payment.',
                    );
                  }
                }
              },
              child: const Text('Confirm Reversal'),
            ),
          ],
        ),
      ),
    );
    if (done == true && mounted) setState(reload);
  }

  Future<void> _showPaymentDetails(
    CustomerLedgerEntry entry,
    Customer customer,
  ) async {
    final relation = await CorrectionRepository(widget.reversals!.db)
        .relationship('PAYMENT', entry.paymentId!);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Payment Details'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.fullName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(_date(entry.occurredAt.toLocal())),
              Text(
                _money(entry.amountCentavos.abs()),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (relation != null)
                Text(
                  relation['original_entity_id'] == entry.paymentId
                      ? 'Status: CORRECTED\nCorrected by PAY-${(relation['replacement_entity_id']! as int).toString().padLeft(6, '0')}\nReason: ${relation['reason']}'
                      : 'Status: COMPLETED — correction of PAY-${(relation['original_entity_id']! as int).toString().padLeft(6, '0')}',
                ),
            ],
          ),
        ),
        actions: [
          if (relation == null)
            TextButton(
              onPressed: () async {
                Navigator.pop(dialog);
                await _correctPayment(entry, customer);
              },
              child: const Text('Correct Transaction'),
            ),
          if (relation == null)
            TextButton(
              onPressed: () async {
                Navigator.pop(dialog);
                await _reversePayment(entry);
              },
              child: const Text('Reverse Only'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _correctPayment(
    CustomerLedgerEntry entry,
    Customer customer,
  ) async {
    final amount = TextEditingController(),
        reason = TextEditingController(),
        pin = TextEditingController();
    String? error;
    var saving = false;
    final done = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, set) {
          final cents = ((double.tryParse(amount.text) ?? 0) * 100).round();
          return AlertDialog(
            title: const Text('Correct Transaction'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${customer.fullName}\nOriginal Payment: ${_money(entry.amountCentavos.abs())}',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => set(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Corrected Payment',
                      prefixText: '₱ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Text(
                    'Resulting UTANG Balance: ${_money(customer.balanceCentavos + entry.amountCentavos.abs() - cents)}',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    decoration: InputDecoration(
                      labelText: 'Correction reason',
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Owner PIN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving || cents <= 0
                    ? null
                    : () async {
                        set(() => saving = true);
                        try {
                          final authorized =
                              await AuthService(widget.reversals!.db)
                                  .verify(pin.text) ==
                              UserRole.owner;
                          await CorrectionRepository(widget.reversals!.db)
                              .correctPayment(
                                originalId: entry.paymentId!,
                                correctedAmountCentavos: cents,
                                reason: reason.text,
                                ownerPinAuthorized: authorized,
                              );
                          if (dialog.mounted) Navigator.pop(dialog, true);
                        } catch (e) {
                          if (dialog.mounted) {
                            set(() {
                              saving = false;
                              error = e is CorrectionException
                                  ? e.message
                                  : 'Could not correct payment.';
                            });
                          }
                        }
                      },
                child: const Text('Confirm Correction'),
              ),
            ],
          );
        },
      ),
    );
    if (done == true && mounted) setState(reload);
  }

  String _lastDate(List<CustomerLedgerEntry> entries, String type) {
    final matching = entries.where((e) => e.type == type).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return matching.isEmpty
        ? 'None'
        : _date(matching.first.occurredAt.toLocal());
  }

  int _outstandingCount(CustomerDetails details) {
    var remaining = details.customer.balanceCentavos, count = 0;
    final debts = details.ledger.where((e) => e.type == 'UTANG').toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    for (final debt in debts) {
      if (remaining <= 0) break;
      count++;
      remaining -= debt.amountCentavos;
    }
    return count;
  }
}

class UtangDetailsDialog extends StatelessWidget {
  const UtangDetailsDialog({
    super.key,
    required this.repository,
    required this.transactionId,
    required this.previousCentavos,
    required this.resultingCentavos,
    this.reversals,
  });
  final CustomerRepository repository;
  final int transactionId;
  final int previousCentavos, resultingCentavos;
  final ReversalRepository? reversals;
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
                            'CREDIT SALE DETAILS',
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
                            subtitle: Text(_snapshotSubtitle(x)),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'CREDIT TOTAL',
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
                _balance('Previous Balance', money(previousCentavos)),
                _balance('Current/Resulting Balance', money(resultingCentavos)),
                if (d['status'] == 'REVERSED')
                  const Chip(label: Text('REVERSED')),
                if (reversals != null)
                  FutureBuilder<Map<String, Object?>?>(
                    future: CorrectionRepository(reversals!.db)
                        .relationship('UTANG', transactionId),
                    builder: (_, s) {
                      final r = s.data;
                      if (r == null) return const SizedBox.shrink();
                      return Text(
                        r['original_entity_id'] == transactionId
                            ? 'CORRECTED by UTG-${(r['replacement_entity_id']! as int).toString().padLeft(6, '0')}\nReason: ${r['reason']}'
                            : 'Correction of UTG-${(r['original_entity_id']! as int).toString().padLeft(6, '0')}',
                      );
                    },
                  ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
                if (reversals != null && d['status'] == 'POSTED') ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _correct(context, d),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Correct Transaction'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                    ),
                    onPressed: () async {
                      final reason = TextEditingController(),
                          pin = TextEditingController();
                      String? error;
                      final done = await showDialog<bool>(
                        context: context,
                        builder: (x) => StatefulBuilder(
                          builder: (_, set) => AlertDialog(
                            title: const Text('Reverse Only?'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: reason,
                                  decoration: InputDecoration(
                                    labelText: 'Reason',
                                    border: const OutlineInputBorder(),
                                    errorText: error,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: pin,
                                  obscureText: true,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Owner PIN',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(x, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                ),
                                onPressed: () async {
                                  if (reason.text.trim().isEmpty) {
                                    set(() => error = 'Reason is required.');
                                    return;
                                  }
                                  try {
                                    final authorized =
                                        await AuthService(reversals!.db)
                                            .verify(pin.text) ==
                                        UserRole.owner;
                                    if (!authorized) {
                                      throw const ReversalException(
                                        'Incorrect Owner PIN.',
                                      );
                                    }
                                    await reversals!.reverseUtang(
                                      transactionId,
                                      reason.text,
                                      ownerPinAuthorized: true,
                                    );
                                    if (x.mounted) Navigator.pop(x, true);
                                  } catch (e) {
                                    if (x.mounted) {
                                      set(
                                        () => error = e is ReversalException
                                            ? e.message
                                            : 'Could not reverse UTANG sale.',
                                      );
                                    }
                                  }
                                },
                                child: const Text('Confirm Reversal'),
                              ),
                            ],
                          ),
                        ),
                      );
                      if (done == true && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.undo),
                    label: const Text('Reverse Only'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );

  Future<void> _correct(
    BuildContext context,
    Map<String, Object?> details,
  ) async {
    final db = reversals!.db;
    final products = await db.query(
      'products',
      where: 'is_archived=0',
      orderBy: 'name COLLATE NOCASE',
    );
    final customers = await db.query(
      'customers',
      where: 'is_archived=0',
      orderBy: 'full_name COLLATE NOCASE',
    );
    if (!context.mounted) return;
    final originalItems = details['items']! as List<Map<String, Object?>>;
    final quantities = <int, int>{
      for (final x in originalItems)
        x['product_id']! as int: x['quantity']! as int,
    };
    final names = <int, String>{
      for (final x in products) x['id']! as int: x['name']! as String,
    };
    for (final x in originalItems) {
      names[x['product_id']! as int] = x['product_name_snapshot']! as String;
    }
    var customerId = details['customer_id']! as int;
    int? addId = products.isEmpty ? null : products.first['id']! as int;
    final reason = TextEditingController(), pin = TextEditingController();
    String? error;
    var saving = false;
    final done = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Correct Transaction'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ORIGINAL CREDIT SALE — ${details['reference']}\n${details['full_name']} • ₱${((details['total_centavos']! as int) / 100).toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Divider(),
                  DropdownButtonFormField<int>(
                    initialValue: customerId,
                    decoration: const InputDecoration(
                      labelText: 'Correct Customer',
                    ),
                    items: customers
                        .map(
                          (c) => DropdownMenuItem(
                            value: c['id']! as int,
                            child: Text(c['full_name']! as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => customerId = v!,
                  ),
                  ...quantities.keys.toList().map(
                    (id) => Row(
                      children: [
                        Expanded(child: Text(names[id] ?? 'Product')),
                        IconButton(
                          onPressed: quantities[id]! > 1
                              ? () => set(
                                  () => quantities[id] = quantities[id]! - 1,
                                )
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        Text('${quantities[id]}'),
                        IconButton(
                          onPressed: () =>
                              set(() => quantities[id] = quantities[id]! + 1),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          onPressed: () => set(() => quantities.remove(id)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                  if (products.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: addId,
                            decoration: const InputDecoration(
                              labelText: 'Add correct product',
                            ),
                            items: products
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p['id']! as int,
                                    child: Text(p['name']! as String),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => addId = v,
                          ),
                        ),
                        IconButton(
                          onPressed: () => set(() {
                            if (addId != null) {
                              quantities.update(
                                addId!,
                                (v) => v + 1,
                                ifAbsent: () => 1,
                              );
                            }
                          }),
                          icon: const Icon(Icons.add_circle),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    decoration: InputDecoration(
                      labelText: 'Correction reason',
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Owner PIN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (quantities.isEmpty || reason.text.trim().isEmpty) {
                        set(
                          () => error =
                              'At least one item and a reason are required.',
                        );
                        return;
                      }
                      set(() => saving = true);
                      try {
                        final authorized =
                            await AuthService(db).verify(pin.text) ==
                            UserRole.owner;
                        await CorrectionRepository(db).correctUtang(
                          originalId: transactionId,
                          corrected: UtangDraft(
                            customerId: customerId,
                            items: quantities.entries
                                .map(
                                  (e) => UtangItemDraft(
                                    productId: e.key,
                                    quantity: e.value,
                                  ),
                                )
                                .toList(),
                          ),
                          reason: reason.text,
                          ownerPinAuthorized: authorized,
                        );
                        if (dialog.mounted) Navigator.pop(dialog, true);
                      } catch (e) {
                        if (dialog.mounted) {
                          set(() {
                            saving = false;
                            error = e is CorrectionException
                                ? e.message
                                : 'Could not correct UTANG sale.';
                          });
                        }
                      }
                    },
              child: const Text('Confirm Correction'),
            ),
          ],
        ),
      ),
    );
    if (done == true && context.mounted) Navigator.pop(context);
  }

  String _snapshotQuantity(Map<String, Object?> x) {
    final value =
        (x['selling_quantity_value'] as int?) ?? x['quantity']! as int;
    final scale = (x['selling_quantity_scale'] as int?) ?? 1;
    return scale == 1
        ? '$value'
        : (value / scale)
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
  }

  String _snapshotSubtitle(Map<String, Object?> x) {
    if (x['selling_quantity_value'] == null) {
      return '${x['quantity']} × ${_money(x['unit_price_centavos']! as int)}';
    }
    return '${_snapshotQuantity(x)} ${x['selling_option_name_snapshot'] ?? 'Piece'} × ${_money((x['selling_unit_price_centavos'] as int?) ?? x['unit_price_centavos']! as int)}';
  }

  String _money(int centavos) => '₱${(centavos / 100).toStringAsFixed(2)}';

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
