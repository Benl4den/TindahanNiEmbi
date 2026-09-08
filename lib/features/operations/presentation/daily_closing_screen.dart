import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../repositories/operations_repository.dart';

class DailyClosingScreen extends StatefulWidget {
  const DailyClosingScreen({super.key, required this.repository});
  final OperationsRepository repository;
  @override
  State<DailyClosingScreen> createState() => _State();
}

class _State extends State<DailyClosingScreen> {
  DateTime date = DateTime.now();
  late Future<DailyClosingSummary> data;
  late Future<List<DateTime>> history;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    data = widget.repository.daily(date);
    history = widget.repository.closingDates();
  }

  String m(int n) => standardMoney(n);
  Future<void> pick() async {
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: date,
    );
    if (d != null) {
      setState(() {
        date = d;
        reload();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Daily Closing Summary'),
      actions: [
        TextButton.icon(
          onPressed: pick,
          icon: const Icon(Icons.calendar_month),
          label: Text('${date.month}/${date.day}/${date.year}'),
        ),
      ],
    ),
    body: FutureBuilder<DailyClosingSummary>(
      future: data,
      builder: (_, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final x = s.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'TODAY — ${MaterialLocalizations.of(context).formatMediumDate(DateTime.now())}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Transaction-based summary — not a physical cash-drawer reconciliation.',
            ),
            const SizedBox(height: 16),
            _section('CASH FLOW', Icons.payments_outlined, [
              _metric('Cash Sales (${x.cashSaleCount})', m(x.cashSales)),
              _metric('UTANG Payments', m(x.payments)),
              _metric('Recorded Cash In', m(x.recordedCashIn), strong: true),
            ]),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (_, box) {
                final width = box.maxWidth >= 700
                    ? (box.maxWidth - 14) / 2
                    : box.maxWidth;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    SizedBox(
                      width: width,
                      child: _accentCard(
                        'NEW CREDIT',
                        m(x.newUtang),
                        Icons.people_alt_outlined,
                        Colors.orange.shade800,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _accentCard(
                        'OPERATING EXPENSES',
                        m(x.operatingExpenses),
                        Icons.receipt_long_outlined,
                        Colors.red.shade700,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            _hero('NET RECORDED CASH AFTER EXPENSES', m(x.netRecordedCash)),
            const SizedBox(height: 14),
            _section('CONSIGNMENT', Icons.handshake_outlined, [
              _metric('Consignment Sales', m(x.consignmentSales)),
              _metric('Supplier Payable Generated', m(x.supplierPayable)),
              _metric(
                'Consignment Margin',
                m(x.consignmentMargin),
                strong: true,
              ),
            ]),
            const SizedBox(height: 14),
            _section('OPERATIONS', Icons.store_mall_directory_outlined, [
              _metric('Transactions', '${x.transactionCount}'),
              _metric(
                'Low Stock',
                '${x.lowStock}',
                color: Colors.orange.shade800,
              ),
              _metric(
                'Out of Stock',
                '${x.outOfStock}',
                color: Colors.red.shade700,
              ),
            ]),
            const SizedBox(height: 20),
            Text(
              'Top-selling Products',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            ...x.topProducts.indexed.map(
              (entry) => Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                  title: Text(entry.$2['name']! as String),
                  trailing: Text(
                    '${_soldQuantity(entry.$2)} sold',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const Divider(height: 40),
            Text(
              'DAILY CLOSING HISTORY',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            FutureBuilder<List<DateTime>>(
              future: history,
              builder: (_, h) => !h.hasData
                  ? const LinearProgressIndicator()
                  : Column(
                      children: h.data!
                          .where(
                            (d) =>
                                !(d.year == DateTime.now().year &&
                                    d.month == DateTime.now().month &&
                                    d.day == DateTime.now().day),
                          )
                          .map(
                            (d) => Card(
                              child: ListTile(
                                title: Text(
                                  MaterialLocalizations.of(context)
                                      .formatMediumDate(d),
                                ),
                                subtitle: const Text(
                                  'Transaction-based daily summary',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _showDay(d),
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        );
      },
    ),
  );

  Widget _section(String title, IconData icon, List<Widget> metrics) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Wrap(spacing: 12, runSpacing: 12, children: metrics),
        ],
      ),
    ),
  );

  Widget _metric(
    String label,
    String value, {
    bool strong = false,
    Color? color,
  }) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: strong ? 25 : 21,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _accentCard(String label, String value, IconData icon, Color color) =>
      Card(
        color: color.withValues(alpha: .08),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: color, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _hero(String label, String value) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              color: Colors.white,
              size: 42,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDay(DateTime day) async {
    final summary = await widget.repository.daily(day);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: CircleAvatar(
          radius: 26,
          backgroundColor: Theme.of(c).colorScheme.primaryContainer,
          child: Icon(
            Icons.calendar_month_outlined,
            color: Theme.of(c).colorScheme.primary,
          ),
        ),
        title: Text(
          MaterialLocalizations.of(c).formatFullDate(day),
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero('NET RECORDED CASH', m(summary.netRecordedCash)),
                const SizedBox(height: 12),
                _section('CASH & UTANG', Icons.payments_outlined, [
                  _metric('Cash Sales', m(summary.cashSales)),
                  _metric('UTANG Created', m(summary.newUtang)),
                  _metric('UTANG Payments', m(summary.payments)),
                  _metric('Recorded Cash In', m(summary.recordedCashIn)),
                ]),
                _section('EXPENSES & CONSIGNMENT', Icons.receipt_long, [
                  _metric('Operating Expenses', m(summary.operatingExpenses)),
                  _metric('Consignment Sales', m(summary.consignmentSales)),
                  _metric('Supplier Payable', m(summary.supplierPayable)),
                  _metric('Store Margin', m(summary.consignmentMargin)),
                ]),
                _section('STORE STATUS', Icons.storefront_outlined, [
                  _metric('Transactions', '${summary.transactionCount}'),
                  _metric('Low Stock', '${summary.lowStock}'),
                  _metric('Out of Stock', '${summary.outOfStock}'),
                ]),
                if (summary.topProducts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Top-selling Products',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                  ...summary.topProducts.indexed.map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                      title: Text(entry.$2['name']! as String),
                      trailing: Text('${_soldQuantity(entry.$2)} sold'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _soldQuantity(Map<String, Object?> row) => baseQuantityText(
    row['quantity']! as int,
    baseUnitCode: row['base_unit_code'] as String? ?? 'PIECE',
    baseUnitLabel: row['base_unit_label'] as String? ?? 'piece',
  );
}
