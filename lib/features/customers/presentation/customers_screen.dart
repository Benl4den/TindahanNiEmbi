import 'package:flutter/material.dart';

import '../../../widgets/overview_banner.dart';

import '../../../core/formatters/number_format.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/customer.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/payment_repository.dart';
import 'customer_detail_screen.dart';
import 'customer_form_screen.dart';
import '../../../widgets/app_state_view.dart';
import '../../../widgets/app_search_field.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({
    super.key,
    required this.repository,
    required this.payments,
    this.canManage = true,
  });
  final CustomerRepository repository;
  final PaymentRepository payments;
  final bool canManage;
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _search = TextEditingController();
  late Future<List<Customer>> _items;
  String _filter = 'All';
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() => _items = widget.repository.searchActive(_search.text);

  Future<void> _form([Customer? customer]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          repository: widget.repository,
          customer: customer,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(_reload);
      _message(AppStrings.customerSaved);
    }
  }

  Future<void> _archive(Customer customer) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.archiveCustomer),
        content: Text(customer.fullName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStrings.confirmArchive),
          ),
        ],
      ),
    );
    if (yes == true) {
      await widget.repository.archive(customer.id);
      if (mounted) {
        setState(_reload);
        _message(AppStrings.customerArchived);
      }
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('UTANG'),
      actions: [
        IconButton(
          tooltip: 'Refresh accounts',
          onPressed: () => setState(_reload),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: FutureBuilder<List<Customer>>(
            future: _items,
            builder: (_, snapshot) {
              if (snapshot.hasError) return const SizedBox.shrink();
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final customers = snapshot.data ?? <Customer>[];
              return OverviewBanner(
                title:
                    'Total outstanding UTANG${_search.text.isEmpty ? '' : ' • Search results'}',
                value: standardMoney(
                  customers.fold<int>(0, (sum, c) => sum + c.balanceCentavos),
                ),
                caption:
                    '${customers.where((c) => c.balanceCentavos > 0).length} with balance • ${customers.where((c) => c.balanceCentavos == 0).length} settled • ${customers.length} accounts',
                icon: Icons.people_alt_outlined,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: AppSearchField(
            controller: _search,
            hintText: AppStrings.searchCustomers,
            onChanged: (_) => setState(_reload),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final label in ['All', 'With balance', 'Settled'])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == label,
                    onSelected: (_) => setState(() => _filter = label),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Customer>>(
            future: _items,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AppStateView.error(
                  title: 'Could not load customers',
                  actionLabel: 'Try Again',
                  onAction: () => setState(_reload),
                );
              }
              if (!snapshot.hasData) {
                return const AppLoadingView(label: 'Loading customers…');
              }
              final accounts = snapshot.data!
                  .where(
                    (c) =>
                        _filter == 'All' ||
                        (_filter == 'With balance'
                            ? c.balanceCentavos > 0
                            : c.balanceCentavos == 0),
                  )
                  .toList();
              if (accounts.isEmpty) {
                return AppStateView.empty(
                  title: 'No matching accounts',
                  message: 'Try another filter or search, or add an UTANGAN.',
                  actionLabel: AppStrings.newCustomer,
                  onAction: _form,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                itemCount: accounts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final customer = accounts[index];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    color: customer.balanceCentavos > 0
                        ? const Color(0xFFFFFCF7)
                        : const Color(0xFFF0F8F2),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (_, box) {
                        final narrow = box.maxWidth < 650;
                        return ListTile(
                          contentPadding: const EdgeInsets.all(18),
                          leading: CircleAvatar(
                            radius: 28,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            child: Text(
                              customer.fullName.trim().isEmpty
                                  ? '?'
                                  : customer.fullName
                                        .trim()
                                        .characters
                                        .first
                                        .toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 22,
                              ),
                            ),
                          ),
                          title: Text(
                            customer.fullName,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (customer.nickname?.trim().isNotEmpty ==
                                    true)
                                  Text(customer.nickname!),
                                Text(
                                  standardMoney(customer.balanceCentavos),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: customer.balanceCentavos > 0
                                        ? const Color(0xFFA65314)
                                        : const Color(0xFF17683E),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  customer.balanceCentavos > 0
                                      ? 'Outstanding balance • Tap to view account ›'
                                      : 'Settled • Tap to view account ›',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CustomerDetailScreen(
                                  repository: widget.repository,
                                  payments: widget.payments,
                                  customerId: customer.id,
                                ),
                              ),
                            );
                            if (mounted) setState(_reload);
                          },
                          trailing: widget.canManage
                              ? narrow
                                    ? PopupMenuButton<String>(
                                        tooltip: 'Customer actions',
                                        onSelected: (value) => value == 'edit'
                                            ? _form(customer)
                                            : _archive(customer),
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text(AppStrings.edit),
                                          ),
                                          PopupMenuItem(
                                            value: 'archive',
                                            child: Text(AppStrings.archive),
                                          ),
                                        ],
                                      )
                                    : Wrap(
                                        spacing: 8,
                                        children: [
                                          OutlinedButton(
                                            onPressed: () => _form(customer),
                                            child: const Text(AppStrings.edit),
                                          ),
                                          OutlinedButton(
                                            onPressed: () => _archive(customer),
                                            child: const Text(
                                              AppStrings.archive,
                                            ),
                                          ),
                                        ],
                                      )
                              : null,
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _form,
      icon: const Icon(Icons.person_add),
      label: const Text(AppStrings.newCustomer),
    ),
  );
}
