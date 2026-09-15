import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../repositories/operations_repository.dart';
import '../../../widgets/store_overview_panel.dart';
import '../../../widgets/store_summary_card.dart';
import '../../../widgets/product_image.dart';
import '../../../widgets/balanced_card_grid.dart';

class DailyClosingOverview extends StatelessWidget {
  const DailyClosingOverview({super.key, required this.summary});
  final DailyClosingSummary summary;
  @override
  Widget build(BuildContext context) {
    final x = summary;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final green = theme.colorScheme.primary;
    final orange = dark ? const Color(0xFFF39C4A) : const Color(0xFFA94F12);
    final red = dark ? const Color(0xFFF08080) : const Color(0xFFB42332);
    final blue = dark ? const Color(0xFF70B7EC) : const Color(0xFF17649A);
    final purple = dark ? const Color(0xFFBAA0E5) : const Color(0xFF6D4AA5);
    String m(int v) => standardMoney(v);
    Widget row(String label, int value, {Color? color, bool strong = false}) =>
        StoreValueRow(label, m(value), accent: color, strong: strong);
    Widget panel(
      String title,
      IconData icon,
      Color color,
      List<Widget> children,
    ) => StoreOverviewPanel(
      title: title,
      icon: icon,
      accent: color,
      children: children,
    );
    Widget grid(List<Widget> children, {int maxColumns = 3}) =>
        BalancedCardGrid(maxColumns: maxColumns, children: children);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoreSummaryHero(
          title: 'Store Day Summary',
          value: '${x.transactionCount} recorded transactions',
          caption: 'A summary of this day’s store activity • Simple to run. Built for your store.',
          icon: Icons.fact_check_outlined,
        ),
        const SizedBox(height: 16),
        grid([
          StoreSummaryCard(
            title: 'Total Sales',
            value: m(x.totalSales + x.newUtang),
            icon: Icons.bar_chart,
            accent: green,
            caption: 'Cash, GCash and new UTANG sales',
          ),
          StoreSummaryCard(
            title: 'New UTANG',
            value: m(x.newUtang),
            icon: Icons.people_outline,
            accent: orange,
            caption: 'Payments are separate collections',
          ),
          StoreSummaryCard(
            title: 'Total Expenses',
            value: m(x.operatingExpenses),
            icon: Icons.account_balance_wallet_outlined,
            accent: red,
            caption: x.expenseCount == null
                ? 'Cash and GCash expenses'
                : '${x.expenseCount} expenses',
          ),
        ]),
        const SizedBox(height: 16),
        grid([
          panel('Money In • Physical Cash', Icons.south_west, green, [
            row('Cash Sales', x.cashSales),
            row('UTANG Payments in Cash', x.cashPayments),
            row('GCash Services — Cash Received', x.gcashServiceCashReceived),
            const Divider(),
            row(
              'Total Cash Received',
              x.cashReceived,
              color: green,
              strong: true,
            ),
          ]),
          panel('Money Out • Physical Cash', Icons.north_east, red, [
            row('Operating Expenses in Cash', x.cashExpenses),
            row('GCash Services — Cash Paid Out', x.gcashServiceCashPaid),
            row('Supplier Payments in Cash', x.cashRemittances),
            const Divider(),
            row('Total Cash Paid Out', x.cashPaid, color: red, strong: true),
          ]),
          panel('Net Recorded Cash', Icons.payments_outlined, green, [
            const SizedBox(height: 12),
            Text(
              m(x.netRecordedCash),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: green,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text('Physical cash received minus physical cash paid out.'),
            const SizedBox(height: 10),
            const Text('Recorded movement—not a cash-drawer count or profit.'),
          ]),
        ]),
        const SizedBox(height: 16),
        grid([
          panel('UTANG', Icons.people_outline, orange, [
            row('New UTANG', x.newUtang),
            row('UTANG Payments', x.payments),
            row('Paid in Cash', x.cashPayments),
            row('Paid with GCash', x.gcashPayments),
            const Divider(),
            row(
              'Net Change',
              x.newUtang - x.payments,
              color: orange,
              strong: true,
            ),
          ]),
          panel('GCash Wallet', Icons.account_balance_wallet_outlined, blue, [
            row('Starting Balance', x.gcashOpeningBalance),
            row('GCash Money In', x.gcashMoneyIn),
            row('GCash Money Out', x.gcashMoneyOut),
            const Divider(),
            row(
              'Ending Balance',
              x.gcashEndingBalance,
              color: blue,
              strong: true,
            ),
            row('Service Fee Income', x.serviceFeeIncome),
            const Text('Includes recorded cancellations and fixes.'),
          ]),
          panel('Consignment', Icons.inventory_2_outlined, purple, [
            row('Consignment Sales', x.consignmentSales),
            row('Amount Owed from These Sales', x.supplierPayable),
            row(
              'Supplier Payments This Day',
              x.cashRemittances + x.gcashRemittances,
            ),
            const Divider(),
            row(
              'Consignment Earnings',
              x.consignmentMargin,
              color: purple,
              strong: true,
            ),
          ]),
        ]),
        const SizedBox(height: 16),
        grid([
          panel('Store Operations', Icons.bar_chart, green, [
            LayoutBuilder(
              builder: (_, box) {
                final width = box.maxWidth >= 600
                    ? (box.maxWidth - 36) / 4
                    : (box.maxWidth - 12) / 2;
                final items = [
                  (
                    Icons.receipt_long,
                    '${x.transactionCount}',
                    'Transactions',
                    green,
                  ),
                  (Icons.warning_amber, '${x.lowStock}', 'Low Stock', orange),
                  (Icons.error_outline, '${x.outOfStock}', 'Out of Stock', red),
                  (
                    Icons.description_outlined,
                    x.expenseCount?.toString() ?? '—',
                    'Expenses',
                    blue,
                  ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: items
                      .map(
                        (item) => SizedBox(
                          width: width,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(item.$1, color: item.$4),
                                const SizedBox(height: 8),
                                Text(
                                  item.$2,
                                  style: theme.textTheme.titleLarge,
                                ),
                                Text(item.$3, textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Live summaries show current stock alerts. Saved closings keep alerts recorded when closed.',
            ),
          ]),
          panel('Top 5 Sold Products', Icons.emoji_events_outlined, green, [
            if (x.topProducts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No completed product sales for this day.'),
              ),
            ...x.topProducts.indexed.map(
              (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: SizedBox(
                  width: 36,
                  height: 36,
                  child: ProductImage(
                    path: entry.$2['photo_path'] as String? ?? '',
                    borderRadius: 8,
                  ),
                ),
                title: Text('${entry.$1 + 1}. ${entry.$2['name']}'),
                subtitle: Text(
                  '${baseQuantityText(entry.$2['quantity'] as int, baseUnitCode: entry.$2['base_unit_code'] as String? ?? 'PIECE', baseUnitLabel: entry.$2['base_unit_label'] as String? ?? 'piece')} sold • ${standardMoney(entry.$2['sales_amount'] as int? ?? 0)}',
                ),
              ),
            ),
          ]),
        ], maxColumns: 2),
        const SizedBox(height: 16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Additional Expense & GCash Details'),
          children: [
            row('Expenses Paid in Cash', x.cashExpenses),
            row('Expenses Paid with GCash', x.gcashExpenses),
            StoreValueRow('Cash-In Transactions', '${x.cashInServiceCount}'),
            StoreValueRow('Cash-Out Transactions', '${x.cashOutServiceCount}'),
            row('Cash-In Fees', x.cashInServiceFees),
            row('Cash-Out Fees', x.cashOutServiceFees),
          ],
        ),
      ],
    );
  }
}
