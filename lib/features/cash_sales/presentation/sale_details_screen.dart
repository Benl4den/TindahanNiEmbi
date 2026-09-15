import 'package:flutter/material.dart';

import '../../../core/formatters/display_labels.dart';

import '../../../core/formatters/number_format.dart';

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
        if (s.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not load this sale. Go back and open it again.',
              ),
            ),
          );
        }
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
                  '${_quantity(x)} ${x['selling_option_name_snapshot'] ?? 'Piece'} × ${standardMoney((x['selling_unit_price_centavos'] as int?) ?? x['unit_price_centavos']! as int)}',
                ),
                trailing: Text(standardMoney(x['line_total_centavos']! as int)),
              ),
            ),
            const Divider(),
            Text('${d.sale.itemCount} items', textAlign: TextAlign.right),
            Text(
              'Total: ${standardMoney(d.sale.totalCentavos)}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (d.sale.status == 'REVERSED')
              Chip(label: Text(DisplayLabels.status(d.sale.status))),
            if (d.sale.status == 'REVERSED')
              FutureBuilder<Map<String, Object?>?>(
                future: reversals?.cancellation(cashSaleId: saleId),
                builder: (_, snapshot) {
                  final cancellation = snapshot.data;
                  if (cancellation == null) return const SizedBox.shrink();
                  return ListTile(
                    leading: const Icon(Icons.cancel_outlined),
                    title: Text(
                      'Cancelled by: ${cancellation['actor_name'] ?? 'Not recorded'}',
                    ),
                    subtitle: Text(
                      'Cancelled at: ${cancellation['occurred_at']}\nReason: ${cancellation['reason']}',
                    ),
                  );
                },
              ),
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
                    original
                        ? DisplayLabels.status('CORRECTED')
                        : '${DisplayLabels.status('POSTED')} — Updated Record',
                  ),
                  subtitle: Text(
                    original
                        ? 'Fixed by SALE-${(r['replacement_entity_id']! as int).toString().padLeft(6, '0')}\nRecorded by: ${r['actor_name'] ?? 'Not recorded'}\nFixed at: ${r['occurred_at']}\nReason: ${r['reason']}'
                        : 'Fix for SALE-${(r['original_entity_id']! as int).toString().padLeft(6, '0')}\nReason: ${r['reason']}',
                  ),
                );
              },
            ),
            if (reversals != null && d.sale.status == 'POSTED') ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _correct(context, d),
                icon: const Icon(Icons.edit_note),
                label: const Text('Fix Sale Details'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
                onPressed: () => _reverse(context),
                icon: const Icon(Icons.undo),
                label: const Text('Cancel Sale'),
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
            title: const Text('Fix Sale Details'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ORIGINAL — ${details.sale.reference}\n${details.sale.itemCount} items • ${standardMoney(details.sale.totalCentavos)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Divider(),
                    const Text(
                      'UPDATED SALE',
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
                      'Updated total: ${standardMoney(total)}\nDifference: ${total - details.sale.totalCentavos >= 0 ? '+' : '-'}${standardMoney((total - details.sale.totalCentavos).abs())}',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reason,
                      decoration: InputDecoration(
                        labelText: 'Reason for this fix',
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
                                  : 'Could not save these changes.';
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Saving…' : 'Save Changes'),
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
          title: const Text('Cancel Sale?'),
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
                                : 'Could not cancel this sale.';
                          });
                        }
                      }
                    },
              child: const Text('Confirm Cancellation'),
            ),
          ],
        ),
      ),
    );
    if (done == true && context.mounted) Navigator.pop(context, true);
  }
}
