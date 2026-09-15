import 'package:flutter/material.dart';

import '../../../widgets/overview_banner.dart';

import '../../../core/formatters/number_format.dart';
import '../../../repositories/operations_repository.dart';
import '../../help/help_button.dart';
import '../../help/help_content.dart';

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
    data = widget.repository.summaryForDate(date);
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
        const HelpButton(topic: HelpTopicId.dailyClosing),
        TextButton.icon(
          onPressed: _confirmCloseDay,
          icon: const Icon(Icons.lock_clock_outlined),
          label: const Text('Close Day'),
        ),
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
              MaterialLocalizations.of(context).formatFullDate(date),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            FutureBuilder<DailyClosingSnapshot?>(
              future: widget.repository.snapshotFor(date),
              builder: (_, snapshot) => Text(
                snapshot.data == null
                    ? 'Live transaction summary. It does not compare your actual cash count.'
                    : 'Saved Daily Closing — ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(snapshot.data!.closedAt))}. Later changes stay in transaction history.',
              ),
            ),
            const SizedBox(height: 16),
            OverviewBanner(
              title:
                  date.year == DateTime.now().year &&
                      date.month == DateTime.now().month &&
                      date.day == DateTime.now().day
                  ? "Today's Earnings"
                  : 'Earnings for Selected Date',
              value: m(x.totalEarnings),
              caption:
                  'Product sales ${m(x.totalSales)} • GCash fees ${m(x.serviceFeeIncome)} • ${x.transactionCount} transactions\nBefore product costs and expenses',
              icon: Icons.insights_outlined,
            ),
            const SizedBox(height: 16),
            _section('PHYSICAL CASH', Icons.payments_outlined, [
              _metric('Cash Received', m(x.cashReceived), strong: true),
              _metric('Cash Paid Out', m(x.cashPaid), strong: true),
              _metric(
                'Difference (Received − Paid Out)',
                _signed(x.cashDifference),
                strong: true,
              ),
              _metric('Cash Sales (${x.cashSaleCount})', '+${m(x.cashSales)}'),
              _metric('UTANG Payments in Cash', '+${m(x.cashPayments)}'),
              _metric(
                'GCash Cash-In received',
                '+${m(x.gcashServiceCashReceived)}',
              ),
              _metric('GCash Cash-Out paid', '-${m(x.gcashServiceCashPaid)}'),
              _metric('Expenses paid in Cash', '-${m(x.cashExpenses)}'),
              _metric(
                'Supplier Payments with Cash',
                '-${m(x.cashRemittances)}',
              ),
            ]),
            const SizedBox(height: 14),
            _section('GCASH', Icons.account_balance_wallet_outlined, [
              _metric('Starting GCash Balance', m(x.gcashOpeningBalance)),
              _metric('GCash Received', m(x.gcashMoneyIn), strong: true),
              _metric('GCash Sent', m(x.gcashMoneyOut), strong: true),
              _metric(
                'Difference (Received − Sent)',
                _signed(x.gcashDifference),
                strong: true,
              ),
              _metric(
                'Expected GCash Balance',
                m(x.gcashEndingBalance),
                strong: true,
              ),
              _metric(
                'GCash Sales (${x.gcashSaleCount})',
                '+${m(x.gcashSales)}',
              ),
              _metric('UTANG Payments with GCash', '+${m(x.gcashPayments)}'),
              _metric(
                'GCash Cash-Out received',
                '+${m(x.gcashServiceWalletReceived)}',
              ),
              _metric('GCash Cash-In sent', '-${m(x.gcashServiceWalletSent)}'),
              _metric('Expenses paid via GCash', '-${m(x.gcashExpenses)}'),
              _metric(
                'Supplier Payments with GCash',
                '-${m(x.gcashRemittances)}',
              ),
            ]),
            const SizedBox(height: 14),
            _section('GCASH SERVICES', Icons.phone_android_outlined, [
              _metric(
                'Cash-In Amount (${x.cashInServiceCount})',
                m(x.cashInServicePrincipal),
              ),
              _metric(
                'Cash-Out Amount (${x.cashOutServiceCount})',
                m(x.cashOutServicePrincipal),
              ),
              _metric('Cash-In Fees', m(x.cashInServiceFees)),
              _metric('Cash-Out Fees', m(x.cashOutServiceFees)),
              _metric('Total Fees Earned', m(x.serviceFeeIncome), strong: true),
              _metric(
                'Physical Cash Effect',
                _signed(x.gcashServicePhysicalCashChange),
              ),
              _metric('GCash Movement', _signed(x.gcashServiceWalletChange)),
            ]),
            const SizedBox(height: 14),
            _section('NEW UTANG', Icons.people_alt_outlined, [
              _metric('New UTANG', m(x.newUtang), strong: true),
              _metric('UTANG Payments Collected', m(x.payments)),
              _metric('Paid in Cash', m(x.cashPayments)),
              _metric('Paid with GCash', m(x.gcashPayments)),
            ]),
            const SizedBox(height: 14),
            _section('EXPENSES', Icons.receipt_long_outlined, [
              _metric('Paid with Cash', m(x.cashExpenses)),
              _metric('Paid with GCash', m(x.gcashExpenses)),
              _metric('Total Expenses', m(x.operatingExpenses), strong: true),
            ]),
            const SizedBox(height: 14),
            _section('CONSIGNMENT', Icons.handshake_outlined, [
              _metric('Consignment Sales', m(x.consignmentSales)),
              _metric('Amount Owed to Supplier', m(x.supplierPayable)),
              _metric(
                'Consignment Earnings',
                m(x.consignmentMargin),
                strong: true,
              ),
            ]),
            const SizedBox(height: 14),
            _section("TODAY'S MONEY SUMMARY", Icons.summarize_outlined, [
              _metric(
                'Physical Cash Difference',
                _signed(x.cashDifference),
                strong: true,
              ),
              _metric(
                'GCash Difference',
                _signed(x.gcashDifference),
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'DAILY CLOSING HISTORY',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: pick,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Choose date'),
                ),
              ],
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
                          .take(5)
                          .map(
                            (d) => Card(
                              child: ListTile(
                                title: Text(
                                  MaterialLocalizations.of(context)
                                      .formatMediumDate(d),
                                ),
                                subtitle: const Text('Open daily summary'),
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
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: PageStorageKey('closing-$title'),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      subtitle: const Text('Tap to view breakdown'),
      childrenPadding: const EdgeInsets.all(18),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 16, runSpacing: 20, children: metrics),
        ),
      ],
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
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );

  String _signed(int amount) => '${amount >= 0 ? '+' : '-'}${m(amount.abs())}';

  Future<void> _confirmCloseDay() async {
    final saved = await widget.repository.snapshotFor(date);
    if (!mounted) return;
    if (saved != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This day is already closed and read-only.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_clock_outlined),
        title: const Text('Close this day?'),
        content: const Text(
          'This saves the displayed Daily Closing summary as a read-only record. Later cancellations or fixes remain visible in transaction history, but will not change this closed record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close Day'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.closeDay(date);
    if (!mounted) return;
    setState(reload);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Daily Closing saved as a read-only snapshot.'),
      ),
    );
  }

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
                      fontWeight: FontWeight.w700,
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
    final snapshot = await widget.repository.snapshotFor(day);
    final summary = snapshot?.summary ?? await widget.repository.daily(day);
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
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  snapshot == null
                      ? 'Live transaction summary'
                      : 'Saved Daily Closing • ${MaterialLocalizations.of(c).formatTimeOfDay(TimeOfDay.fromDateTime(snapshot.closedAt))}',
                  textAlign: TextAlign.center,
                  style: Theme.of(c).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                _hero('EARNINGS FOR SELECTED DATE', m(summary.totalEarnings)),
                const SizedBox(height: 12),
                _section('PHYSICAL CASH', Icons.payments_outlined, [
                  _metric('Cash Received', m(summary.cashReceived)),
                  _metric('Cash Paid Out', m(summary.cashPaid)),
                  _metric(
                    'Difference',
                    _signed(summary.cashDifference),
                    strong: true,
                  ),
                ]),
                _section('GCASH', Icons.account_balance_wallet_outlined, [
                  _metric(
                    'Starting GCash Balance',
                    m(summary.gcashOpeningBalance),
                  ),
                  _metric('GCash Received', m(summary.gcashMoneyIn)),
                  _metric('GCash Sent', m(summary.gcashMoneyOut)),
                  _metric(
                    'Difference',
                    _signed(summary.gcashDifference),
                    strong: true,
                  ),
                  _metric(
                    'Expected GCash Balance',
                    m(summary.gcashEndingBalance),
                  ),
                ]),
                _section('GCASH SERVICES', Icons.phone_android_outlined, [
                  _metric(
                    'Cash-In Amount (${summary.cashInServiceCount})',
                    m(summary.cashInServicePrincipal),
                  ),
                  _metric(
                    'Cash-Out Amount (${summary.cashOutServiceCount})',
                    m(summary.cashOutServicePrincipal),
                  ),
                  _metric(
                    'Total Fees Earned',
                    m(summary.serviceFeeIncome),
                    strong: true,
                  ),
                  _metric(
                    'Physical Cash Effect',
                    _signed(summary.gcashServicePhysicalCashChange),
                  ),
                  _metric(
                    'GCash Effect',
                    _signed(summary.gcashServiceWalletChange),
                  ),
                ]),
                _section('NEW UTANG', Icons.people_alt_outlined, [
                  _metric('New UTANG', m(summary.newUtang)),
                  _metric('UTANG Payments Collected', m(summary.payments)),
                ]),
                _section('EXPENSES', Icons.receipt_long, [
                  _metric('Paid with Cash', m(summary.cashExpenses)),
                  _metric('Paid with GCash', m(summary.gcashExpenses)),
                  _metric('Total Expenses', m(summary.operatingExpenses)),
                ]),
                _section('CONSIGNMENT', Icons.handshake_outlined, [
                  _metric('Consignment Sales', m(summary.consignmentSales)),
                  _metric(
                    'Amount Owed to Supplier',
                    m(summary.supplierPayable),
                  ),
                  _metric('Consignment Earnings', m(summary.consignmentMargin)),
                ]),
                _section("TODAY'S MONEY SUMMARY", Icons.summarize_outlined, [
                  _metric(
                    'Physical Cash Difference',
                    _signed(summary.cashDifference),
                    strong: true,
                  ),
                  _metric(
                    'GCash Difference',
                    _signed(summary.gcashDifference),
                    strong: true,
                  ),
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
