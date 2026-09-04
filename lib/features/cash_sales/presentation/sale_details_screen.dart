import 'package:flutter/material.dart';

import '../../../repositories/cash_sale_repository.dart';
import '../../../repositories/reversal_repository.dart';
import '../../../repositories/correction_repository.dart';
import '../../../models/utang_draft.dart';
import '../../../services/auth_service.dart';

class SaleDetailsScreen extends StatelessWidget {
  const SaleDetailsScreen({
    super.key,
    required this.repository,
    required this.saleId,
    this.reversals,
  });
  final CashSaleRepository repository;
  final int saleId;
  final ReversalRepository? reversals;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sale Details')),
    body: FutureBuilder<CashSaleDetails>(
      future: repository.details(saleId),
      builder: (_, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final d = s.data!, local = d.sale.occurredAt.toLocal();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              d.sale.reference,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${MaterialLocalizations.of(context).formatFullDate(local)} • ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
            ),
            const SizedBox(height: 20),
            ...d.items.map(
              (x) => ListTile(
                title: Text(x['product_name_snapshot']! as String),
                subtitle: Text(
                  '${_quantity(x)} ${x['selling_option_name_snapshot'] ?? 'Piece'} × ₱${(((x['selling_unit_price_centavos'] as int?) ?? x['unit_price_centavos']! as int) / 100).toStringAsFixed(2)}',
                ),
                trailing: Text(
                  '₱${((x['line_total_centavos']! as int) / 100).toStringAsFixed(2)}',
                ),
              ),
            ),
            const Divider(),
            Text('${d.sale.itemCount} items', textAlign: TextAlign.right),
            Text(
              'Total: ₱${(d.sale.totalCentavos / 100).toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (d.sale.status == 'REVERSED')
              const Chip(label: Text('REVERSED')),
            FutureBuilder<Map<String, Object?>?>(
              future: CorrectionRepository(repository.db)
                  .relationship('CASH_SALE', saleId),
              builder: (_, relation) {
                final r = relation.data;
                if (r == null) return const SizedBox.shrink();
                final original = r['original_entity_id'] == saleId;
                return ListTile(
                  leading: const Icon(Icons.rule),
                  title: Text(
                    original ? 'CORRECTED' : 'COMPLETED — CORRECTION',
                  ),
                  subtitle: Text(
                    original
                        ? 'Corrected by SALE-${(r['replacement_entity_id']! as int).toString().padLeft(6, '0')}\nReason: ${r['reason']}\n${r['occurred_at']}'
                        : 'Correction of SALE-${(r['original_entity_id']! as int).toString().padLeft(6, '0')}\nReason: ${r['reason']}',
                  ),
                );
              },
            ),
            if (reversals != null && d.sale.status == 'POSTED') ...[
              const SizedBox(height: 24),
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
                onPressed: () => _reverse(context),
                icon: const Icon(Icons.undo),
                label: const Text('Reverse Only'),
              ),
            ],
          ],
        );
      },
    ),
  );

  String _quantity(Map<String, Object?> x) {
    final value =
        (x['selling_quantity_value'] as int?) ?? x['quantity']! as int;
    final scale = (x['selling_quantity_scale'] as int?) ?? 1;
    if (scale == 1) return '$value';
    return (value / scale)
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  Future<void> _correct(BuildContext context, CashSaleDetails details) async {
    final products = await repository.db.query(
      'products',
      where: 'is_archived=0',
      orderBy: 'name COLLATE NOCASE',
    );
    if (!context.mounted) return;
    final quantities = <int, int>{
      for (final x in details.items)
        x['product_id']! as int: x['quantity']! as int,
    };
    final prices = <int, int>{
      for (final x in details.items)
        x['product_id']! as int: x['unit_price_centavos']! as int,
    };
    final names = <int, String>{
      for (final x in products) x['id']! as int: x['name']! as String,
    };
    for (final x in details.items) {
      names[x['product_id']! as int] = x['product_name_snapshot']! as String;
    }
    final reason = TextEditingController(), pin = TextEditingController();
    int? addId = products.isEmpty ? null : products.first['id']! as int;
    String? error;
    var saving = false;
    final corrected = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, set) {
          final total = quantities.entries.fold<int>(
            0,
            (sum, e) =>
                sum +
                e.value *
                    (prices[e.key] ??
                        (products.firstWhere(
                              (p) => p['id'] == e.key,
                            )['selling_price_centavos']!
                            as int)),
          );
          return AlertDialog(
            title: const Text('Correct Transaction'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ORIGINAL — ${details.sale.reference}\n${details.sale.itemCount} items • ₱${(details.sale.totalCentavos / 100).toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Divider(),
                    const Text(
                      'CORRECTED',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
                            tooltip: 'Remove',
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
                              items: products
                                  .map(
                                    (p) => DropdownMenuItem(
                                      value: p['id']! as int,
                                      child: Text(p['name']! as String),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => addId = v,
                              decoration: const InputDecoration(
                                labelText: 'Add product',
                              ),
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
                                prices[addId!] =
                                    products.firstWhere(
                                          (p) => p['id'] == addId,
                                        )['selling_price_centavos']!
                                        as int;
                              }
                            }),
                            icon: const Icon(Icons.add_circle),
                          ),
                        ],
                      ),
                    Text(
                      'Corrected total: ₱${(total / 100).toStringAsFixed(2)}\nDifference: ${total - details.sale.totalCentavos >= 0 ? '+' : '-'}₱${((total - details.sale.totalCentavos).abs() / 100).toStringAsFixed(2)}',
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
                              await AuthService(repository.db)
                                  .verify(pin.text) ==
                              UserRole.owner;
                          await CorrectionRepository(repository.db)
                              .correctCashSale(
                                originalId: saleId,
                                correctedItems: quantities.entries
                                    .map(
                                      (e) => UtangItemDraft(
                                        productId: e.key,
                                        quantity: e.value,
                                      ),
                                    )
                                    .toList(),
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
                                  : 'Could not correct this transaction.';
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Saving…' : 'Confirm Correction'),
              ),
            ],
          );
        },
      ),
    );
    if (corrected == true && context.mounted) Navigator.pop(context, true);
  }

  Future<void> _reverse(BuildContext context) async {
    final reason = TextEditingController();
    final pin = TextEditingController();
    String? error;
    var saving = false;
    final done = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          title: const Text('Reverse Only?'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This will cancel the effects of this completed sale. The original transaction will remain in history.',
                ),
                const SizedBox(height: 12),
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
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: saving
                  ? null
                  : () async {
                      if (reason.text.trim().isEmpty) {
                        set(() => error = 'Reason is required.');
                        return;
                      }
                      set(() => saving = true);
                      try {
                        final authorized =
                            await AuthService(reversals!.db).verify(pin.text) ==
                            UserRole.owner;
                        if (!authorized) {
                          throw const ReversalException('Incorrect Owner PIN.');
                        }
                        await reversals!.reverseCashSale(
                          saleId,
                          reason.text,
                          ownerPinAuthorized: true,
                        );
                        if (dialog.mounted) Navigator.pop(dialog, true);
                      } catch (e) {
                        if (dialog.mounted) {
                          set(() {
                            saving = false;
                            error = e is ReversalException
                                ? e.message
                                : 'Could not reverse this sale.';
                          });
                        }
                      }
                    },
              child: const Text('Confirm Reversal'),
            ),
          ],
        ),
      ),
    );
    if (done == true && context.mounted) Navigator.pop(context, true);
  }
}
