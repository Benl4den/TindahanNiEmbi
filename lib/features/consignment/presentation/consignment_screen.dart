import 'package:flutter/material.dart';

import '../../../models/consignment.dart';
import '../../../models/product.dart';
import '../../../repositories/consignment_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../services/product_photo_service.dart';
import '../../products/presentation/product_form_screen.dart';
import '../../../widgets/summary_card.dart';

class ConsignmentScreen extends StatefulWidget {
  const ConsignmentScreen({
    super.key,
    required this.repository,
    required this.products,
    required this.categories,
    required this.photoService,
  });
  final ConsignmentRepository repository;
  final ProductRepository products;
  final CategoryRepository categories;
  final ProductPhotoService photoService;
  @override
  State<ConsignmentScreen> createState() => _ConsignmentScreenState();
}

class _AddConsignorDialog extends StatefulWidget {
  const _AddConsignorDialog({required this.repository});
  final ConsignmentRepository repository;
  @override
  State<_AddConsignorDialog> createState() => _AddConsignorDialogState();
}

class _AddConsignorDialogState extends State<_AddConsignorDialog> {
  final name = TextEditingController(), contact = TextEditingController();
  String? error;
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    contact.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Company or consignor name is required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.createConsignor(
        name.text,
        contactDetails: contact.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is InvalidConsignmentOperation
              ? e.message
              : 'Could not save the consignor. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Consignor'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Company / Name',
              border: const OutlineInputBorder(),
              errorText: error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: contact,
            decoration: const InputDecoration(
              labelText: 'Contact details (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: name.text.trim().isEmpty || saving ? null : save,
        child: saving
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Save'),
      ),
    ],
  );
}

class _RemittanceDialog extends StatefulWidget {
  const _RemittanceDialog({
    required this.repository,
    required this.parties,
    required this.balances,
  });
  final ConsignmentRepository repository;
  final List<Consignor> parties;
  final Map<int, int> balances;
  @override
  State<_RemittanceDialog> createState() => _RemittanceDialogState();
}

class _RemittanceDialogState extends State<_RemittanceDialog> {
  late int party;
  final amount = TextEditingController(), notes = TextEditingController();
  String? error;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    party = widget.parties
        .firstWhere((p) => (widget.balances[p.id] ?? 0) > 0)
        .id;
  }

  @override
  void dispose() {
    amount.dispose();
    notes.dispose();
    super.dispose();
  }

  String money(int n) => '₱${(n / 100).toStringAsFixed(2)}';
  Future<void> save() async {
    final cents = ((double.tryParse(amount.text.trim()) ?? 0) * 100).round(),
        balance = widget.balances[party] ?? 0;
    if (cents <= 0) {
      setState(() => error = 'Enter a remittance amount greater than zero.');
      return;
    }
    if (cents > balance) {
      setState(() => error = 'Amount cannot exceed ${money(balance)}.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.remit(
        consignorId: party,
        amountCentavos: cents,
        notes: notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is InvalidConsignmentOperation
              ? e.message
              : 'Could not record the remittance. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = widget.balances[party] ?? 0;
    return AlertDialog(
      title: const Text('Record Remittance'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<int>(
              initialValue: party,
              decoration: const InputDecoration(
                labelText: 'Consignor',
                border: OutlineInputBorder(),
              ),
              items: widget.parties
                  .where((p) => (widget.balances[p.id] ?? 0) > 0)
                  .map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (v) => setState(() {
                      party = v!;
                      error = null;
                    }),
            ),
            const SizedBox(height: 14),
            Text(
              'Outstanding Payable: ${money(balance)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Remittance Amount',
                prefixText: '₱ ',
                border: const OutlineInputBorder(),
                errorText: error,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: notes,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: saving
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Record Remittance'),
        ),
      ],
    );
  }
}

class _ConsignmentScreenState extends State<ConsignmentScreen> {
  int? selectedConsignorId;
  late Future<
    ({
      ConsignmentSummary? summary,
      List<Map<String, Object?>> cards,
      List<Map<String, Object?>> companies,
    })
  >
  _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _load();
  }

  Future<
    ({
      ConsignmentSummary? summary,
      List<Map<String, Object?>> cards,
      List<Map<String, Object?>> companies,
    })
  >
  _load() async {
    final companies = await widget.repository.companyCards();
    final id = selectedConsignorId;
    if (id == null) {
      return (
        summary: null,
        cards: <Map<String, Object?>>[],
        companies: companies,
      );
    }
    return (
      summary: await widget.repository.summaryForConsignor(id),
      cards: await widget.repository.productCardsForConsignor(id),
      companies: companies,
    );
  }

  String money(int value) => '₱${(value / 100).toStringAsFixed(2)}';
  Future<void> _addConsignor() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AddConsignorDialog(repository: widget.repository),
    );
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _receive() async {
    final parties = await widget.repository.consignors(),
        products = await widget.products.searchActive();
    if (!mounted) return;
    if (parties.isEmpty) {
      _message('Add a consignor before receiving consignment.');
      return;
    }
    final createNew = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Receive Consignment'),
        content: const Text('Choose how to identify the delivered product.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Select Existing Product'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Create New Product'),
          ),
        ],
      ),
    );
    if (createNew == null) return;
    if (!createNew && products.isEmpty) {
      _message('No products are available. Choose Create New Product.');
      return;
    }
    ProductDraft? newProduct;
    if (createNew) {
      final categories = await widget.categories.getActive();
      if (!mounted) return;
      final completed = await showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 900),
            child: ProductFormScreen(
              repository: widget.products,
              photoService: widget.photoService,
              categories: categories,
              allowStartingStock: false,
              onDraft: (draft) => newProduct = draft,
            ),
          ),
        ),
      );
      if (completed != true || newProduct == null) return;
    }
    if (!mounted) return;
    int party = parties.first.id,
        product = products.isEmpty ? -1 : products.first.id;
    final boxes = TextEditingController(),
        units = TextEditingController(),
        cost = TextEditingController(),
        sell = TextEditingController(),
        notes = TextEditingController();
    String? error;
    var saving = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (x) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Receive Consignment'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: party,
                    decoration: const InputDecoration(labelText: 'Consignor'),
                    items: parties
                        .map(
                          (v) => DropdownMenuItem(
                            value: v.id,
                            child: Text(v.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => set(() => party = v!),
                  ),
                  if (!createNew)
                    DropdownButtonFormField<int>(
                      initialValue: product,
                      decoration: const InputDecoration(
                        labelText: 'Existing Product',
                      ),
                      items: products
                          .map(
                            (v) => DropdownMenuItem(
                              value: v.id,
                              child: Text(v.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => set(() => product = v!),
                    ),
                  ...[
                    (boxes, 'Boxes received'),
                    (units, 'Units per box'),
                    (cost, 'Cost per unit'),
                    (sell, 'Selling price per unit'),
                    (notes, 'Notes (optional)'),
                  ].map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: f.$1,
                        onChanged: (_) => set(() {}),
                        keyboardType: f.$1 == notes
                            ? TextInputType.text
                            : TextInputType.number,
                        decoration: InputDecoration(
                          labelText: f.$2,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final boxCount = int.tryParse(boxes.text) ?? 0;
                      final perBox = int.tryParse(units.text) ?? 0;
                      final unitCost = double.tryParse(cost.text) ?? 0;
                      final selling = double.tryParse(sell.text) ?? 0;
                      final total = boxCount * perBox;
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Total Units: $total\nMargin / Unit: ₱${(selling - unitCost).toStringAsFixed(2)}\nTotal Consigned Value: ₱${(total * unitCost).toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      );
                    },
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final receipt = ConsignmentReceiptDraft(
                        consignorId: party,
                        productId: product,
                        boxes: int.tryParse(boxes.text) ?? 0,
                        unitsPerBox: int.tryParse(units.text) ?? 0,
                        unitCostCentavos:
                            ((double.tryParse(cost.text) ?? -1) * 100).round(),
                        sellingPriceCentavos:
                            ((double.tryParse(sell.text) ?? -1) * 100).round(),
                        notes: notes.text,
                      );
                      if (receipt.boxes <= 0 ||
                          receipt.unitsPerBox <= 0 ||
                          receipt.unitCostCentavos < 0 ||
                          receipt.sellingPriceCentavos < 0) {
                        set(
                          () => error = 'Enter valid boxes, units, cost, and selling price.',
                        );
                        return;
                      }
                      set(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        if (newProduct == null) {
                          await widget.repository.receive(receipt);
                        } else {
                          await widget.repository.receiveNewProduct(
                            product: newProduct!,
                            consignorId: party,
                            boxes: receipt.boxes,
                            unitsPerBox: receipt.unitsPerBox,
                            unitCostCentavos: receipt.unitCostCentavos,
                            sellingPriceCentavos: receipt.sellingPriceCentavos,
                            notes: receipt.notes,
                          );
                        }
                        if (x.mounted) Navigator.pop(x, true);
                      } catch (e) {
                        if (x.mounted) {
                          set(() {
                            saving = false;
                            error = _friendly(e);
                          });
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Receive'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) setState(_reload);
  }

  String _friendly(Object error) => error is InvalidConsignmentOperation
      ? error.message
      : 'Could not save. Please check the details and try again.';
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _remit() async {
    final parties = await widget.repository.consignors();
    if (!mounted) return;
    if (parties.isEmpty) {
      _message('Add a consignor before recording a remittance.');
      return;
    }
    final balances = await widget.repository.payableByConsignor();
    if (!mounted) return;
    if (!balances.values.any((value) => value > 0)) {
      _message('There is no outstanding supplier payable to remit.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _RemittanceDialog(
        repository: widget.repository,
        parties: parties,
        balances: balances,
      ),
    );
    if (ok == true && mounted) setState(_reload);
  }

  Future<void> _details(Map<String, Object?> product) async {
    final rows = await widget.repository.productHistory(
      product['product_id']! as int,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
          child: Column(
            children: [
              ListTile(
                title: Text(
                  product['name']! as String,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                subtitle: Text(
                  '${product['consignor_name']} • Read-only history',
                ),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) {
                    final x = rows[i];
                    final payable = x['payable_centavos']! as int;
                    return ListTile(
                      title: Text(
                        '${x['event_type']} • ${x['quantity']} units',
                      ),
                      subtitle: Text(
                        '${DateTime.parse(x['occurred_at']! as String).toLocal()}\nCost ${money(x['unit_cost_centavos']! as int)} • Selling ${money(x['selling_price_centavos']! as int)}',
                      ),
                      trailing: payable == 0
                          ? null
                          : Text(
                              'Payable ${money(payable)}\nMargin ${money(x['margin_centavos']! as int)}',
                              textAlign: TextAlign.end,
                            ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _returnStock(product);
                        },
                        icon: const Icon(Icons.undo),
                        label: const Text('Return Unsold Stock'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
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

  Future<void> _archiveConsignor(String name) async {
    final id = selectedConsignorId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Archive Consignor?'),
        content: Text(
          '$name will no longer appear in normal Consignment selections. All receipts, products, remittances, payable entries, and historical records will remain unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Archive Consignor'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.archiveConsignor(id);
      if (!mounted) return;
      setState(() {
        selectedConsignorId = null;
        _reload();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Consignor archived. Historical records were preserved.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The consignor could not be archived. Please try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _returnStock(Map<String, Object?> product) async {
    final batches = await widget.repository.returnableBatches(
      product['product_id']! as int,
    );
    if (!mounted || batches.isEmpty) return;
    var batchId = batches.first['id']! as int;
    final quantity = TextEditingController(), notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Return Unsold Stock'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: batchId,
                  decoration: const InputDecoration(labelText: 'Receipt batch'),
                  items: batches
                      .map(
                        (b) => DropdownMenuItem(
                          value: b['id']! as int,
                          child: Text(
                            '${b['consignor_name']} • ${b['available']} available',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => set(() => batchId = v!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Units to return',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Confirm Return'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.repository.returnUnits(
        batchId: batchId,
        quantity: int.tryParse(quantity.text) ?? 0,
        notes: notes.text,
      );
      if (mounted) setState(_reload);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: selectedConsignorId == null
          ? null
          : IconButton(
              tooltip: 'Company List',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                selectedConsignorId = null;
                _reload();
              }),
            ),
      title: const Text('Consignment'),
    ),
    body: FutureBuilder(
      future: _data,
      builder: (_, s) {
        if (s.hasError) {
          return Center(child: Text('Could not load Consignment: ${s.error}'));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final summary = s.data!.summary,
            cards = s.data!.cards,
            companies = s.data!.companies;
        if (selectedConsignorId == null) {
          return ListView(
            key: const Key('consignor-company-list'),
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _addConsignor,
                    icon: const Icon(Icons.business),
                    label: const Text('Add Consignor'),
                  ),
                  FilledButton.icon(
                    onPressed: _receive,
                    icon: const Icon(Icons.add_box),
                    label: const Text('Receive Consignment'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Companies / Consignors',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (companies.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text('No consignors yet. Add a consignor to begin.'),
                  ),
                ),
              ...companies.map(
                (x) => Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(18),
                    leading: const CircleAvatar(child: Icon(Icons.business)),
                    title: Text(
                      x['name']! as String,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    subtitle: Text(
                      '${x['product_count']} products • ${money(x['payable_centavos']! as int)} payable\n'
                      'Last receipt: ${_shortDate(x['last_receipt_at'])} • Last remittance: ${_shortDate(x['last_remittance_at'])}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() {
                      selectedConsignorId = x['id']! as int;
                      _reload();
                    }),
                  ),
                ),
              ),
            ],
          );
        }
        if (summary == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final company = companies.firstWhere(
          (x) => x['id'] == selectedConsignorId,
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              company['name']! as String,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (company['contact_details'] != null)
              Text(company['contact_details']! as String),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    selectedConsignorId = null;
                    _reload();
                  }),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Company List'),
                ),
                FilledButton.icon(
                  onPressed: _receive,
                  icon: const Icon(Icons.add_box),
                  label: const Text('Receive Consignment'),
                ),
                OutlinedButton.icon(
                  onPressed: _remit,
                  icon: const Icon(Icons.payments),
                  label: const Text('Record Remittance'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                  onPressed: () =>
                      _archiveConsignor(company['name']! as String),
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Archive Consignor'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SummaryCard(
                  label: 'Outstanding Supplier Payable',
                  value: money(summary.payableCentavos),
                ),
                SummaryCard(
                  label: 'Remaining Consigned Stock',
                  value: '${summary.remainingUnits}',
                ),
                SummaryCard(
                  label: 'Consigned Inventory Value',
                  value: money(summary.inventoryValueCentavos),
                ),
                SummaryCard(
                  label: 'Store Margin Earned',
                  value: money(summary.marginCentavos),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Consigned Products',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (cards.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('No consignment receipts yet.')),
              ),
            ...cards.map(
              (x) => Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  title: Text(
                    x['name']! as String,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  subtitle: Text(
                    '${x['consignor_name']}\nReceived: ${x['received']}   Remaining: ${x['remaining']}   Sold: ${x['sold']}\nSelling: ${money(x['selling_price_centavos']! as int)}   Amount to Remit: ${money(x['payable_centavos']! as int)}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _details(x),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  String _shortDate(Object? value) => value == null
      ? 'None'
      : MaterialLocalizations.of(context)
            .formatShortDate(DateTime.parse(value as String).toLocal());
}
