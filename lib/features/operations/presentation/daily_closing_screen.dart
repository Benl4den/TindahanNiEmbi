import 'package:flutter/material.dart';

import '../../../repositories/operations_repository.dart';
import '../../../widgets/summary_card.dart';

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

  String m(int n) => '₱${(n / 100).toStringAsFixed(2)}';
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
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SummaryCard(
                  label: 'Cash Sales (${x.cashSaleCount})',
                  value: m(x.cashSales),
                ),
                SummaryCard(label: 'New UTANG', value: m(x.newUtang)),
                SummaryCard(label: 'UTANG Payments', value: m(x.payments)),
                SummaryCard(
                  label: 'Recorded Cash In',
                  value: m(x.recordedCashIn),
                ),
                SummaryCard(
                  label: 'Consignment Sales',
                  value: m(x.consignmentSales),
                ),
                SummaryCard(
                  label: 'Supplier Payable Generated',
                  value: m(x.supplierPayable),
                ),
                SummaryCard(
                  label: 'Consignment Margin',
                  value: m(x.consignmentMargin),
                ),
                SummaryCard(
                  label: 'Transactions',
                  value: '${x.transactionCount}',
                ),
                SummaryCard(label: 'Low Stock', value: '${x.lowStock}'),
                SummaryCard(label: 'Out of Stock', value: '${x.outOfStock}'),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Top-selling Products',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            ...x.topProducts.map(
              (p) => ListTile(
                title: Text(p['name']! as String),
                trailing: Text('${p['quantity']} sold'),
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

  Future<void> _showDay(DateTime day) async {
    final summary = await widget.repository.daily(day);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(MaterialLocalizations.of(c).formatFullDate(day)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cash Sales: ${m(summary.cashSales)}'),
                Text('UTANG Created: ${m(summary.newUtang)}'),
                Text('UTANG Payments: ${m(summary.payments)}'),
                Text('Recorded Cash In: ${m(summary.recordedCashIn)}'),
                Text('Consignment Sales: ${m(summary.consignmentSales)}'),
                Text('Supplier Payable: ${m(summary.supplierPayable)}'),
                Text('Store Margin: ${m(summary.consignmentMargin)}'),
                Text('Transactions: ${summary.transactionCount}'),
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
}
