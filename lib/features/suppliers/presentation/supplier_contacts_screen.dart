import 'package:flutter/material.dart';

import '../../../repositories/supplier_contacts_repository.dart';
import '../../../widgets/app_search_field.dart';

class SupplierContactsScreen extends StatefulWidget {
  const SupplierContactsScreen({super.key, required this.repository});
  final SupplierContactsRepository repository;
  @override
  State<SupplierContactsScreen> createState() => _SupplierContactsScreenState();
}

class _SupplierContactsScreenState extends State<SupplierContactsScreen> {
  final search = TextEditingController();
  bool archived = false;
  Future<void> edit([SupplierContact? item]) async {
    final name = TextEditingController(text: item?.name),
        contact = TextEditingController(text: item?.contactNumber);
    final result = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(item == null ? 'Add Supplier' : 'Edit Supplier'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Supplier name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contact,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contact number (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await widget.repository.save(
                id: item?.id,
                name: name.text,
                contactNumber: contact.text,
              );
              if (d.mounted) Navigator.pop(d, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Supplier Contacts'),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(
            onPressed: () => edit(),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add Supplier'),
          ),
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep supplier names and numbers ready when you need to order stock.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  controller: search,
                  hintText: 'Search suppliers',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: Text(archived ? 'Archived' : 'Active'),
                selected: true,
                onSelected: (_) => setState(() => archived = !archived),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<SupplierContact>>(
              future: widget.repository.list(
                query: search.text,
                archived: archived,
              ),
              builder: (_, s) {
                if (s.hasError) {
                  return const Center(
                    child: Text(
                      'Could not load suppliers. Reopen this section.',
                    ),
                  );
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = s.data!;
                if (data.isEmpty) {
                  return Center(
                    child: Text(
                      archived
                          ? 'No archived suppliers.'
                          : 'No supplier contacts yet.',
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: data.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final x = data[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            archived
                                ? Icons.inventory_2_outlined
                                : Icons.local_shipping_outlined,
                          ),
                        ),
                        title: Text(x.name),
                        subtitle: Text(
                          x.contactNumber ?? 'No contact number saved',
                        ),
                        onTap: () => edit(x),
                        trailing: IconButton(
                          tooltip: archived
                              ? 'Restore supplier'
                              : 'Archive supplier',
                          icon: Icon(
                            archived ? Icons.restore : Icons.archive_outlined,
                          ),
                          onPressed: () async {
                            await widget.repository.archive(
                              x.id,
                              archived: !archived,
                            );
                            if (mounted) setState(() {});
                          },
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
}
