import 'package:flutter/material.dart';

import '../../repositories/transaction_history_repository.dart';
import '../../widgets/app_state_view.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key, required this.repository});
  final TransactionHistoryRepository repository;
  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  String filter = 'ALL', search = '';
  final Set<String> expanded = {};
  String _key(DateTime value) {
    final d = value.toLocal();
    return '${d.year}-${d.month}-${d.day}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transaction History')),
    body: FutureBuilder<List<TransactionHistoryEntry>>(
      future: widget.repository.recent(type: filter),
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return AppStateView.error(
            title: 'Could not load transaction history',
            onAction: () => setState(() {}),
          );
        }
        if (!snapshot.hasData) {
          return const AppLoadingView(label: 'Loading transaction history…');
        }
        final entries = snapshot.data!
            .where((x) => x.title.toLowerCase().contains(search.toLowerCase()))
            .toList();
        final groups = <String, List<TransactionHistoryEntry>>{};
        for (final entry in entries) {
          (groups[_key(entry.occurredAt)] ??= []).add(entry);
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: (v) => setState(() => search = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search transactions...',
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final x in const [
                    ('ALL', 'All'),
                    ('CASH', 'Cash'),
                    ('UTANG', 'UTANG'),
                    ('PAYMENT', 'Payments'),
                    ('EXPENSE', 'Expenses'),
                    ('CONSIGNMENT', 'Consignment'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(x.$2),
                        selected: filter == x.$1,
                        onSelected: (_) => setState(() => filter = x.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: groups.isEmpty
                  ? const AppStateView.empty(title: 'No transactions found')
                  : ListView(
                      children: groups.entries.map((group) {
                        final open = expanded.contains(group.key),
                            day = group.value.first.occurredAt.toLocal();
                        return Card(
                          margin: const EdgeInsets.fromLTRB(16, 5, 16, 5),
                          child: Column(
                            children: [
                              ListTile(
                                onTap: () => setState(
                                  () => open
                                      ? expanded.remove(group.key)
                                      : expanded.add(group.key),
                                ),
                                title: Text(
                                  MaterialLocalizations.of(context)
                                      .formatFullDate(day),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text(
                                  '${group.value.length} transactions',
                                ),
                                trailing: Icon(
                                  open ? Icons.expand_less : Icons.expand_more,
                                ),
                              ),
                              AnimatedCrossFade(
                                duration: const Duration(milliseconds: 180),
                                crossFadeState: open
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                firstChild: const SizedBox.shrink(),
                                secondChild: Column(
                                  children: group.value
                                      .map(
                                        (entry) => ListTile(
                                          onTap: () => _showDetails(entry),
                                          leading: Icon(_icon(entry.type)),
                                          title: Text(entry.title),
                                          subtitle: Text(
                                            '${TimeOfDay.fromDateTime(entry.occurredAt.toLocal()).format(context)} • ${entry.status}',
                                          ),
                                          trailing: Text(
                                            '₱${(entry.amountCentavos / 100).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        );
      },
    ),
  );

  IconData _icon(String type) => switch (type) {
    'CASH' => Icons.payments_outlined,
    'UTANG' => Icons.people_outline,
    'PAYMENT' => Icons.account_balance_wallet_outlined,
    'EXPENSE' => Icons.receipt_long_outlined,
    _ => Icons.inventory_2_outlined,
  };

  Future<void> _showDetails(TransactionHistoryEntry entry) async {
    Map<String, Object?> details;
    try {
      details = await widget.repository.details(entry);
    } catch (_) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Could Not Open Transaction'),
            content: const Text(
              'The transaction details could not be loaded. Please try again.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final items = (details['items'] as List<Map<String, Object?>>?) ?? const [];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(_icon(entry.type)),
            const SizedBox(width: 10),
            Expanded(child: Text(entry.title)),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${MaterialLocalizations.of(context).formatFullDate(entry.occurredAt.toLocal())} • ${TimeOfDay.fromDateTime(entry.occurredAt.toLocal()).format(context)}',
                ),
                const SizedBox(height: 12),
                if (entry.type == 'PAYMENT')
                  Text('Payment received from ${details['full_name']}'),
                if (entry.type == 'EXPENSE') ...[
                  Text(
                    '${details['category_name_snapshot']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('${details['description']}'),
                ],
                if (entry.type == 'CONSIGNMENT') ...[
                  Text(
                    '${details['product_name']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('From ${details['consignor_name']}'),
                  Text('${details['units_received']} units received'),
                ],
                if (items.isNotEmpty) ...[
                  const Divider(height: 26),
                  const Text(
                    'PRODUCTS',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  ...items.map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${item['product_name_snapshot']}'),
                      subtitle: Text(_itemQuantity(item)),
                      trailing: Text(
                        _money(item['line_total_centavos']! as int),
                      ),
                    ),
                  ),
                ],
                const Divider(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _money(entry.amountCentavos),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(entry.status, textAlign: TextAlign.right),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _itemQuantity(Map<String, Object?> item) {
    final value =
        (item['selling_quantity_value'] as int?) ?? item['quantity']! as int;
    final scale = (item['selling_quantity_scale'] as int?) ?? 1;
    final quantity = scale == 1
        ? '$value'
        : (value / scale)
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '');
    final option = item['selling_option_name_snapshot'] ?? 'Piece';
    final price =
        (item['selling_unit_price_centavos'] as int?) ??
        item['unit_price_centavos']! as int;
    return '$quantity $option × ${_money(price)}';
  }

  String _money(int centavos) => '₱${(centavos / 100).toStringAsFixed(2)}';
}
