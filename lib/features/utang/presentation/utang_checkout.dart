import 'package:flutter/material.dart';

import '../../../models/customer.dart';
import '../../../models/product.dart';
import '../../../models/utang_draft.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/utang_repository.dart';
import '../../customers/presentation/customer_form_screen.dart';
import 'utang_customer_card.dart';

class UtangCheckoutPicker extends StatefulWidget {
  const UtangCheckoutPicker({
    super.key,
    required this.customers,
    required this.utang,
    required this.products,
    required this.items,
  });
  final CustomerRepository customers;
  final UtangRepository utang;
  final List<Product> products;
  final List<UtangItemDraft> items;
  @override
  State<UtangCheckoutPicker> createState() => _State();
}

class _State extends State<UtangCheckoutPicker> {
  final search = TextEditingController();
  late Future<List<Customer>> data;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => data = widget.customers.searchActive(search.text);
  Future<void> select(Customer customer) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => UtangCheckoutReview(
          customer: customer,
          customers: widget.customers,
          utang: widget.utang,
          products: widget.products,
          items: widget.items,
        ),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  Future<void> create() async {
    final before = (await widget.customers.searchActive())
        .map((x) => x.id)
        .toSet();
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(repository: widget.customers),
      ),
    );
    if (ok == true) {
      final all = await widget.customers.searchActive();
      final created = all.where((x) => !before.contains(x.id));
      if (created.isNotEmpty && mounted) await select(created.first);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MGA UTANGAN')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    hintText: 'Search UTANGAN...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(reload),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: create,
                icon: const Icon(Icons.person_add),
                label: const Text('Add New UTANGAN'),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Customer>>(
            future: data,
            builder: (_, s) {
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.data!.isEmpty) {
                return const Center(
                  child: Text(
                    'No UTANGAN Yet.\nAdd a customer to start tracking UTANG.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: s.data!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final c = s.data![i];
                  return UtangCustomerCard(customer: c, onTap: () => select(c));
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

class UtangCheckoutReview extends StatefulWidget {
  const UtangCheckoutReview({
    super.key,
    required this.customer,
    required this.customers,
    required this.utang,
    required this.products,
    required this.items,
  });
  final Customer customer;
  final CustomerRepository customers;
  final UtangRepository utang;
  final List<Product> products;
  final List<UtangItemDraft> items;
  @override
  State<UtangCheckoutReview> createState() => _ReviewState();
}

class _ReviewState extends State<UtangCheckoutReview> {
  bool saving = false;
  int get total => widget.items.fold(
    0,
    (n, x) =>
        n +
        widget.products
                .firstWhere((p) => p.id == x.productId)
                .sellingPriceCentavos *
            x.quantity,
  );
  Future<void> confirm() async {
    setState(() => saving = true);
    try {
      await widget.utang.save(
        UtangDraft(customerId: widget.customer.id, items: widget.items),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The UTANG could not be completed. Your cart has been kept. Please try again.',
            ),
          ),
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
      final previous = s.data!.customer.balanceCentavos;
      return Scaffold(
        appBar: AppBar(title: const Text('Review UTANG')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Customer'),
            Text(
              widget.customer.fullName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            Text('Products', style: Theme.of(context).textTheme.titleLarge),
            ...widget.items.map((x) {
              final p = widget.products.firstWhere((p) => p.id == x.productId);
              return ListTile(
                title: Text(p.name),
                subtitle: Text(
                  '${x.quantity} × ₱${(p.sellingPriceCentavos / 100).toStringAsFixed(2)}',
                ),
                trailing: Text(
                  '₱${(p.sellingPriceCentavos * x.quantity / 100).toStringAsFixed(2)}',
                ),
              );
            }),
            const Divider(),
            _amount('Previous UTANG', previous),
            _amount('New UTANG', total),
            _amount('Total UTANG', previous + total, important: true),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: saving ? null : confirm,
                    child: const Text('Confirm UTANG'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  Widget _amount(String label, int cents, {bool important = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          '₱${(cents / 100).toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: important ? 24 : 18,
            fontWeight: important ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
