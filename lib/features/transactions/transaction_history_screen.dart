import 'package:flutter/material.dart';

import '../../core/formatters/display_labels.dart';

import '../../core/formatters/number_format.dart';

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
  int limit = 500;
  DateTime? selectedDay;
  late Future<List<TransactionHistoryEntry>> data;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => data = widget.repository.recent(
    type: filter,
    search: search,
    limit: limit,
    day: selectedDay,
  );
  final Set<String> expanded = {};
  String _key(DateTime value) {
    final d = value.toLocal();
    return '${d.year}-${d.month}-${d.day}';
  }

  String _displayStatus(String status) => DisplayLabels.status(status);

  Future<void> _pickDay() async {
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: selectedDay ?? DateTime.now(),
    );
    if (day != null && mounted) {
      setState(() {
        selectedDay = day;
        expanded.clear();
        reload();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Transaction History')),
    body: FutureBuilder<List<TransactionHistoryEntry>>(
      future: data,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return AppStateView.error(
            title: 'Could not load transaction history',
            onAction: () => setState(reload),
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() {
                        search = v;
                        reload();
                      }),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search transactions...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Choose date',
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_month_outlined),
                  ),
                ],
              ),
            ),
            if (selectedDay != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text(
                      MaterialLocalizations.of(context)
                          .formatMediumDate(selectedDay!),
                    ),
                    onDeleted: () => setState(() {
                      selectedDay = null;
                      expanded.clear();
                      reload();
                    }),
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
                    ('CASH', 'Sales'),
                    ('UTANG', 'UTANG'),
                    ('PAYMENT', 'Payments'),
                    ('EXPENSE', 'Expenses'),
                    ('CONSIGNMENT', 'Consignment'),
                    ('GCASH_SERVICE', 'GCash Services'),
                    ('MAYA_SERVICE', 'Maya Services'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(x.$2),
                        selected: filter == x.$1,
                        onSelected: (_) => setState(() {
                          filter = x.$1;
                          limit = 500;
                          reload();
                        }),
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
                      children: groups.entries.take(selectedDay == null ? 5 : groups.length).map((
                        group,
                      ) {
                        final open = expanded.contains(group.key),
                            day = group.value.first.occurredAt.toLocal();
                        return Card(
                          key: ValueKey('history-day-${group.key}'),
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
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  '${group.value.length} ${group.value.length == 1 ? 'transaction' : 'transactions'}',
                                ),
                                trailing: Icon(
                                  open ? Icons.expand_less : Icons.expand_more,
                                ),
                              ),
                              if (open)
                                Column(
                                  children: group.value
                                      .map(
                                        (entry) => Card(
                                          color: _entryColor(
                                            context,
                                            entry.type,
                                          ),
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          child: ExpansionTile(
                                            key: PageStorageKey(
                                              'transaction-${entry.type}-${entry.id}',
                                            ),
                                            leading: CircleAvatar(
                                              backgroundColor: _entryAccent(
                                                context,
                                                entry.type,
                                              ).withValues(alpha: .16),
                                              child: Icon(
                                                _icon(entry.type),
                                                color: _entryAccent(
                                                  context,
                                                  entry.type,
                                                ),
                                              ),
                                            ),
                                            title: Text(entry.title),
                                            subtitle: Text(
                                              standardMoney(
                                                entry.amountCentavos,
                                              ),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            children: [
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      20,
                                                      0,
                                                      20,
                                                      12,
                                                    ),
                                                child: Wrap(
                                                  spacing: 16,
                                                  runSpacing: 8,
                                                  crossAxisAlignment:
                                                      WrapCrossAlignment.center,
                                                  children: [
                                                    Text(
                                                      '${TimeOfDay.fromDateTime(entry.occurredAt.toLocal()).format(context)} • ${_displayStatus(entry.status)}',
                                                    ),
                                                    Text('By ${entry.actor}'),
                                                    TextButton.icon(
                                                      onPressed: () =>
                                                          _showDetails(entry),
                                                      icon: const Icon(
                                                        Icons
                                                            .receipt_long_outlined,
                                                      ),
                                                      label: const Text(
                                                        'Open full details',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
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
    'GCASH_SERVICE' => Icons.phone_android_outlined,
    'MAYA_SERVICE' => Icons.phone_android_outlined,
    _ => Icons.inventory_2_outlined,
  };

  Color _entryAccent(BuildContext context, String type) => switch (type) {
    'EXPENSE' => Theme.of(context).colorScheme.error,
    'UTANG' => const Color(0xFFF39C4A),
    'GCASH_SERVICE' => Theme.of(context).colorScheme.primary,
    'MAYA_SERVICE' => Theme.of(context).colorScheme.primary,
    _ => Theme.of(context).colorScheme.primary,
  };

  Color _entryColor(BuildContext context, String type) =>
      _entryAccent(context, type).withValues(alpha: .055);

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
                if (entry.type == 'GCASH_SERVICE' ||
                    entry.type == 'MAYA_SERVICE') ...[
                  if (entry.type == 'MAYA_SERVICE') Text('Wallet: Maya'),
                  Text('Reference: ${details['reference']}'),
                  Text(
                    'Amount: ${standardMoney(details['principal_centavos']! as int)}',
                  ),
                  Text(
                    'Service fee: ${standardMoney(details['fee_centavos']! as int)}',
                  ),
                  Text(
                    'Fee Option: ${details['fee_option'] == 'ADDED' ? 'Fee Added' : 'Fee Deducted'}',
                  ),
                  Text(
                    '${entry.title.contains('Cash-In') ? 'Customer Pays Cash' : 'Customer Sends ${entry.type == 'MAYA_SERVICE' ? 'Maya' : 'GCash'}'}: ${standardMoney(details['customer_total_centavos']! as int)}',
                  ),
                  Text(
                    'Cash Movement: ${standardMoney(details['physical_cash_change_centavos']! as int)}',
                  ),
                  Text(
                    '${entry.type == 'MAYA_SERVICE' ? 'Maya' : 'GCash'} Movement: ${standardMoney(details[entry.type == 'MAYA_SERVICE' ? 'wallet_change_centavos' : 'gcash_change_centavos']! as int)}',
                  ),
                  if (details['gcash_reference'] != null)
                    Text('GCash reference: ${details['gcash_reference']}'),
                  if (details['wallet_reference'] != null)
                    Text('Maya reference: ${details['wallet_reference']}'),
                  if (details['notes'] != null) Text('${details['notes']}'),
                ],
                if (items.isNotEmpty) ...[
                  const Divider(height: 26),
                  const Text(
                    'PRODUCTS',
                    style: TextStyle(fontWeight: FontWeight.w700),
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
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _money(entry.amountCentavos),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
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

  String _money(int centavos) => standardMoney(centavos);
}
