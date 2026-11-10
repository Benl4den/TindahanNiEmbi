import 'package:flutter/material.dart';

import '../../../core/formatters/display_labels.dart';
import '../../../core/formatters/number_format.dart';
import '../../../repositories/cash_sale_repository.dart';

Future<void> showSalesHistoryDialog(
  BuildContext context,
  CashSaleRepository repository, {
  bool todayOnly = false,
  required Future<void> Function(SalesHistoryEntry) onSelected,
}) async {
  var filter = 'ALL';
  await showDialog<void>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (_, setModal) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        todayOnly ? "Today's Sales" : 'All Transactions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialog),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final x in const [
                        ('ALL', 'All'),
                        ('CASH', 'Cash'),
                        ('GCASH', 'GCash'),
                        ('MAYA', 'Maya'),
                        ('UTANG', 'UTANG'),
                      ])
                        ChoiceChip(
                          label: Text(x.$2),
                          selected: filter == x.$1,
                          onSelected: (_) => setModal(() => filter = x.$1),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: FutureBuilder<List<SalesHistoryEntry>>(
                  future: repository.history(type: filter),
                  builder: (_, s) {
                    final entries = (s.data ?? const <SalesHistoryEntry>[])
                        .where((e) {
                          if (!todayOnly) return true;
                          final d = e.occurredAt.toLocal(),
                              now = DateTime.now();
                          return d.year == now.year &&
                              d.month == now.month &&
                              d.day == now.day;
                        })
                        .toList();
                    return !s.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : entries.isEmpty
                        ? const Center(child: Text('No transactions found.'))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              indent: 76,
                              endIndent: 20,
                            ),
                            itemBuilder: (_, i) {
                              final e = entries[i],
                                  local = e.occurredAt.toLocal();
                              return ListTile(
                                leading: Icon(
                                  e.isUtang ? Icons.people_alt : Icons.payments,
                                ),
                                title: Text(
                                  '${e.isUtang ? 'UTANG Sale' : '${e.paymentMethod.label} Sale'} • ${e.reference}',
                                ),
                                subtitle: Text(
                                  '${e.customerName == null ? '' : '${e.customerName} • '}${MaterialLocalizations.of(context).formatMediumDate(local)} • ${TimeOfDay.fromDateTime(local).format(context)}\n'
                                  '${e.itemCount} items • ${e.correctedById != null
                                      ? DisplayLabels.status('CORRECTED')
                                      : e.status == 'REVERSED'
                                      ? DisplayLabels.status('REVERSED')
                                      : DisplayLabels.status('POSTED')}'
                                  '${e.correctionOfId == null ? '' : '\nFix for #${e.correctionOfId}'}',
                                ),
                                trailing: Text(
                                  standardMoney(e.totalCentavos),
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: e.isUtang
                                        ? Colors.orange.shade800
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(dialog);
                                  WidgetsBinding.instance.addPostFrameCallback(
                                    (_) => onSelected(e),
                                  );
                                },
                              );
                            },
                          );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
