import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../repositories/operations_repository.dart';
import '../../../widgets/store_overview_panel.dart';
import '../../../widgets/store_summary_card.dart';
import '../../../widgets/product_image.dart';
import '../../../widgets/balanced_card_grid.dart';

class DailyClosingOverview extends StatelessWidget {
  const DailyClosingOverview({
    super.key,
    required this.summary,
    this.walletServicesAllowed = true,
  });
  final DailyClosingSummary summary;
  final bool walletServicesAllowed;
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
          value: '${x.transactionCount} recorded events',
          caption: 'Activity on this date, including recorded corrections and reversals.',
          icon: Icons.fact_check_outlined,
        ),
        const SizedBox(height: 16),
        grid([
          StoreSummaryCard(
            title: 'Total Sales',
            value: m(x.totalSales + x.newUtang),
            icon: Icons.bar_chart,
            accent: green,
            caption: 'Cash, GCash, Maya and new UTANG • net of corrections',
          ),
          StoreSummaryCard(
            title: 'New UTANG',
            value: m(x.newUtang),
            icon: Icons.people_outline,
            accent: orange,
            caption: 'Payments are separate collections',
          ),
          StoreSummaryCard(
            title: 'Operating Expenses',
            value: m(x.operatingExpenses),
            icon: Icons.account_balance_wallet_outlined,
            accent: red,
            caption: 'Net of corrections • excludes supplier and loan payouts',
          ),
        ]),
        const SizedBox(height: 16),
        grid([
          panel('Recorded Cash In', Icons.south_west, green, [
            row('Cash Sales', x.cashSales),
            row('UTANG Payments in Cash', x.cashPayments),
            if (walletServicesAllowed) ...[
              row('GCash Services — Cash Received', x.gcashServiceCashReceived),
              row('Maya Services — Cash Received', x.mayaServiceCashReceived),
            ] else
              row(
                'E-Wallet Services — Cash Received',
                x.gcashServiceCashReceived + x.mayaServiceCashReceived,
              ),
            row('5/6 Loans Received in Cash', x.loanCashReceived),
            const Divider(),
            row('Net Cash In', x.cashReceived, color: green, strong: true),
          ]),
          panel('Recorded Cash Out', Icons.north_east, red, [
            row('Operating Expenses in Cash', x.cashExpenses),
            if (walletServicesAllowed) ...[
              row('GCash Services — Cash Paid Out', x.gcashServiceCashPaid),
              row('Maya Services — Cash Paid Out', x.mayaServiceCashPaid),
            ] else
              row(
                'E-Wallet Services — Cash Paid Out',
                x.gcashServiceCashPaid + x.mayaServiceCashPaid,
              ),
            row('Supplier Payments in Cash', x.cashRemittances),
            row('5/6 Loan Payments in Cash', x.loanCashPayments),
            if (x.loanCashPaymentReversals != 0)
              row('Reversed 5/6 Loan Payments', -x.loanCashPaymentReversals),
            const Divider(),
            row('Net Cash Out', x.cashPaid, color: red, strong: true),
          ]),
          panel('Net Recorded Cash', Icons.payments_outlined, green, [
            const SizedBox(height: 12),
            Text(
              m(x.cashDifference),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: green,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Recorded cash in minus recorded cash out, net of corrections.',
            ),
            const SizedBox(height: 10),
            const Text(
              'Reversals correct records; they do not prove cash physically moved. This is not a cash-drawer count or profit.',
            ),
          ]),
        ]),
        const SizedBox(height: 16),
        grid([
          panel('Payment Summary', Icons.credit_card_outlined, green, [
            const Text(
              'Product sales and UTANG collections, by payment method.',
            ),
            row('Cash', x.cashSales + x.cashPayments),
            row('GCash', x.gcashSales + x.gcashPayments),
            row('Maya', x.mayaSales + x.mayaPayments),
            const Divider(),
            row(
              'Total Customer Payments',
              x.totalSales + x.payments,
              color: green,
              strong: true,
            ),
          ]),
          panel('UTANG', Icons.people_outline, orange, [
            row('New UTANG', x.newUtang),
            row('UTANG Payments', x.payments),
            row('Paid in Cash', x.cashPayments),
            row('Paid with GCash', x.gcashPayments),
            row('Paid with Maya', x.mayaPayments),
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
            if (walletServicesAllowed)
              row('Service Fee Income', x.serviceFeeIncome),
            const Text('Includes recorded cancellations and fixes.'),
          ]),
          panel('Maya Wallet', Icons.account_balance_wallet_outlined, blue, [
            row('Starting Balance', x.mayaOpeningBalance),
            row('Maya Money In', x.mayaMoneyIn),
            row('Maya Money Out', x.mayaMoneyOut),
            row('Net Change', x.mayaMoneyIn - x.mayaMoneyOut),
            const Divider(),
            row(
              'Ending Balance',
              x.mayaEndingBalance,
              color: blue,
              strong: true,
            ),
            if (walletServicesAllowed) ...[
              row('Service Fee Income', x.mayaServiceFeeIncome),
              row('Maya Sales', x.mayaSales),
              row('UTANG Payments with Maya', x.mayaPayments),
              row('Expenses paid with Maya', x.mayaExpenses),
              row('Supplier Payments with Maya', x.mayaRemittances),
              row('5/6 Loans Received with Maya', x.loanMayaReceived),
              row('5/6 Loan Payments with Maya', x.loanMayaPayments),
              if (x.loanMayaPaymentReversals != 0)
                row('Reversed 5/6 Loan Payments', -x.loanMayaPaymentReversals),
            ],
            const Text('Maya is separate from physical cash and GCash.'),
          ]),
          panel('E-Wallet Fees Earned', Icons.payments_outlined, green, [
            if (walletServicesAllowed) ...[
              row('GCash Fees', x.serviceFeeIncome),
              row('Maya Fees', x.mayaServiceFeeIncome),
              const Divider(),
            ],
            row(
              'Total Fees',
              x.serviceFeeIncome + x.mayaServiceFeeIncome,
              color: green,
              strong: true,
            ),
          ]),
          panel('Consignment', Icons.inventory_2_outlined, purple, [
            row('Consignment Sales', x.consignmentSales),
            row('Amount Owed from These Sales', x.supplierPayable),
            row(
              'Supplier Payments This Day',
              x.cashRemittances + x.gcashRemittances + x.mayaRemittances,
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
                    'Events',
                    green,
                  ),
                  (Icons.warning_amber, '${x.lowStock}', 'Low Stock', orange),
                  (Icons.error_outline, '${x.outOfStock}', 'Out of Stock', red),
                  (
                    Icons.description_outlined,
                    x.expenseCount?.toString() ?? '—',
                    'Expense entries',
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
            const Text('Ranked by number of sales containing each product.'),
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
          title: Text(
            walletServicesAllowed
                ? 'Additional Expense & GCash Details'
                : 'Additional Expense Details',
          ),
          children: [
            row('Expenses Paid in Cash', x.cashExpenses),
            row('Expenses Paid with GCash', x.gcashExpenses),
            if (walletServicesAllowed) ...[
              StoreValueRow('Cash-In Transactions', '${x.cashInServiceCount}'),
              StoreValueRow(
                'Cash-Out Transactions',
                '${x.cashOutServiceCount}',
              ),
              row('Cash-In Fees', x.cashInServiceFees),
              row('Cash-Out Fees', x.cashOutServiceFees),
            ],
          ],
        ),
      ],
    );
  }
}
