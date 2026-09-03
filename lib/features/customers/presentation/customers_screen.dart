import 'package:flutter/material.dart';

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
    appBar: AppBar(title: const Text(AppStrings.customers)),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: AppSearchField(
            controller: _search,
            hintText: AppStrings.searchCustomers,
            onChanged: (_) => setState(_reload),
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
              if (snapshot.data!.isEmpty) {
                return AppStateView.empty(
                  title: AppStrings.noCustomers,
                  message: 'Add a customer to begin managing accounts.',
                  actionLabel: AppStrings.newCustomer,
                  onAction: _form,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: snapshot.data!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) {
                  final customer = snapshot.data![index];
                  return Card(
                    child: LayoutBuilder(
                      builder: (_, box) {
                        final narrow = box.maxWidth < 650;
                        return ListTile(
                          contentPadding: const EdgeInsets.all(18),
                          leading: const CircleAvatar(
                            radius: 28,
                            child: Icon(Icons.person, size: 32),
                          ),
                          title: Text(
                            customer.fullName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          subtitle: Text(
                            '${customer.nickname ?? ''}\n${AppStrings.totalUtang}: ₱${(customer.balanceCentavos / 100).toStringAsFixed(2)}',
                          ),
                          isThreeLine: true,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerDetailScreen(
                                repository: widget.repository,
                                payments: widget.payments,
                                customerId: customer.id,
                              ),
                            ),
                          ),
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
