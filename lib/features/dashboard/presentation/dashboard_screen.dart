import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/formatters/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../repositories/dashboard_repository.dart';
import '../../../repositories/operations_repository.dart';
import '../../../services/app_refresh_controller.dart';
import '../../../widgets/store_summary_card.dart';
import '../../../widgets/balanced_card_grid.dart';
import '../../../widgets/product_image.dart';
import '../../../widgets/store_overview_panel.dart';
import '../../help/help_button.dart';
import '../../help/help_content.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.database,
    required this.navigate,
    this.refreshRevision = 0,
  });
  final Database database;
  final void Function(int) navigate;
  final int refreshRevision;
  @override
  State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends State<DashboardScreen> {
  int period = 0;
  late Future<List<Object>> data;
  late DateTime start, end;
  DateTime? updatedAt;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    reload();
    AppRefreshController.instance.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(reload);
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshRevision != widget.refreshRevision ||
        oldWidget.database != widget.database) {
      reload();
    }
  }

  @override
  void dispose() {
    AppRefreshController.instance.removeListener(_refresh);
    super.dispose();
  }

  void reload() {
    final request = ++_request;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    start = period == 1
        ? DateTime(today.year, today.month, today.day - today.weekday + 1)
        : period == 2
        ? DateTime(today.year, today.month)
        : today;
    end = DateTime(today.year, today.month, today.day + 1);
    data =
        Future.wait<Object>([
          OperationsRepository(widget.database).daily(start, endDate: end),
          DashboardRepository(widget.database).summary(),
          widget.database.rawQuery(
            'SELECT COALESCE(SUM(amount_change_centavos),0) balance FROM gcash_ledger_entries',
          ),
          widget.database.rawQuery(
            'SELECT name,photo_path,current_quantity,base_unit_code,base_unit_label FROM products WHERE is_archived=0 AND current_quantity<=minimum_stock_level ORDER BY current_quantity ASC,name COLLATE NOCASE LIMIT 5',
          ),
          widget.database.rawQuery(
            'SELECT event_type,description,created_at,actor_name FROM activity_logs ORDER BY created_at DESC,id DESC LIMIT 5',
          ),
          widget.database.rawQuery(
            'SELECT COUNT(*) count FROM cash_sales WHERE status=\'POSTED\' AND occurred_at>=? AND occurred_at<? UNION ALL SELECT COUNT(*) FROM utang_transactions WHERE status=\'POSTED\' AND occurred_at>=? AND occurred_at<?',
            [
              start.toUtc().toIso8601String(),
              end.toUtc().toIso8601String(),
              start.toUtc().toIso8601String(),
              end.toUtc().toIso8601String(),
            ],
          ),
        ]).then((result) {
          if (mounted && request == _request) updatedAt = DateTime.now();
          return result;
        });
  }

  Color accent(String type) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (type) {
      'utang' => dark ? const Color(0xFFF39C4A) : const Color(0xFFA94F12),
      'expense' => dark ? const Color(0xFFF08080) : const Color(0xFFB42332),
      'gcash' => dark ? const Color(0xFF70B7EC) : const Color(0xFF17649A),
      'consignment' => dark ? const Color(0xFFBAA0E5) : const Color(0xFF6D4AA5),
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  String quantity(Map<String, Object?> row) => baseQuantityText(
    row['quantity'] as int? ?? row['current_quantity']! as int,
    baseUnitCode: row['base_unit_code'] as String? ?? 'PIECE',
    baseUnitLabel: row['base_unit_label'] as String? ?? 'piece',
  );
  Widget _header({required bool loaded, required bool failed}) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
    child: LayoutBuilder(
      builder: (_, box) {
        final theme = Theme.of(context);
        final localizations = MaterialLocalizations.of(context);
        final description = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dashboard',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const HelpButton(topic: HelpTopicId.dashboard),
              ],
            ),
            Text(
              'Your quick store overview. Keep track of sales, expenses, inventory and more.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 3),
            Text(
              loaded && updatedAt != null
                  ? 'Updated at ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(updatedAt!))}'
                  : failed
                  ? 'Could not update overview'
                  : 'Updating…',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
        return description;
      },
    ),
  );

  Widget _periodControls() {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final last = DateTime(end.year, end.month, end.day - 1);
    final sameDay =
        start.year == last.year &&
        start.month == last.month &&
        start.day == last.day;
    final date = sameDay
        ? localizations.formatMediumDate(start)
        : '${localizations.formatMediumDate(start)} – ${localizations.formatMediumDate(last)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(color: Color(0xFF85B9A2), height: 1),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < 3; i++)
              ChoiceChip(
                label: Text(['Today', 'This Week', 'This Month'][i]),
                selected: period == i,
                selectedColor: const Color(0xFFD9F3DE),
                backgroundColor: const Color(0xFF194F3B),
                checkmarkColor: const Color(0xFF0B4930),
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  color: period == i ? const Color(0xFF0B4930) : Colors.white,
                ),
                side: BorderSide(
                  color: period == i
                      ? const Color(0xFFD9F3DE)
                      : const Color(0xFF85B9A2),
                ),
                onSelected: (_) => setState(() {
                  period = i;
                  reload();
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          date,
          key: const ValueKey('dashboard-period-date'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFFE1F1E8),
          ),
        ),
      ],
    );
  }

  Widget _frame(Widget child, {bool loaded = false, bool failed = false}) =>
      Column(
        children: [
          _header(loaded: loaded, failed: failed),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<List<Object>>(
      future: data,
      builder: (_, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _frame(
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [CircularProgressIndicator(), SizedBox(height: 12)],
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return _frame(
            Center(
              child: TextButton(
                onPressed: () => setState(reload),
                child: const Text('Could not load overview. Try again'),
              ),
            ),
            failed: true,
          );
        }
        if (!snapshot.hasData) {
          return _frame(const Center(child: CircularProgressIndicator()));
        }
        final x = snapshot.data![0] as DailyClosingSummary;
        final current = snapshot.data![1] as DashboardSummary;
        final wallet = snapshot.data![2] as List<Map<String, Object?>>;
        final alerts = snapshot.data![3] as List<Map<String, Object?>>;
        final activity = snapshot.data![4] as List<Map<String, Object?>>;
        final counts = snapshot.data![5] as List<Map<String, Object?>>;
        final salesCount = counts.fold<int>(
          0,
          (sum, row) => sum + (row['count']! as int),
        );
        final label = ['Today', 'This Week', 'This Month'][period];
        return _frame(
          RefreshIndicator(
            onRefresh: () async {
              setState(reload);
              try {
                await data;
              } catch (_) {
                // FutureBuilder presents the retry state for failed refreshes.
              }
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                StoreSummaryHero(
                  footer: _periodControls(),
                  title: 'Total Sales • $label',
                  value: standardMoney(x.totalSales + x.newUtang),
                  caption:
                      '$salesCount sales transactions\nCash ${standardMoney(x.cashSales)} • GCash ${standardMoney(x.gcashSales)} • UTANG ${standardMoney(x.newUtang)}',
                  icon: Icons.bar_chart_outlined,
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (_, box) {
                    final cards = <Widget>[
                      metric(
                        'New UTANG',
                        standardMoney(x.newUtang),
                        Icons.people_outline,
                        accent('utang'),
                      ),
                      metric(
                        'UTANG Payments',
                        standardMoney(x.payments),
                        Icons.payments_outlined,
                        accent(''),
                      ),
                      metric(
                        'Expenses',
                        standardMoney(x.operatingExpenses),
                        Icons.receipt_long_outlined,
                        accent('expense'),
                      ),
                      metric(
                        'Current GCash Balance',
                        standardMoney(wallet.single['balance']! as int),
                        Icons.account_balance_wallet_outlined,
                        accent('gcash'),
                      ),
                      metric(
                        'Currently Owed to Suppliers',
                        standardMoney(current.supplierPayableCentavos),
                        Icons.handshake_outlined,
                        accent('consignment'),
                      ),
                      metric(
                        'Recorded Transactions',
                        '$label • ${x.transactionCount}',
                        Icons.history,
                        accent(''),
                      ),
                    ];
                    return BalancedCardGrid(children: cards);
                  },
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (_, box) {
                    return BalancedCardGrid(
                      minimumCardWidth: 300,
                      children: [
                        StoreOverviewPanel(
                          title: 'Top-Selling Products',
                          icon: Icons.bar_chart,
                          action: viewAll(9),
                          children: [
                            const Text(
                              'Ranked by number of sales containing each product.',
                            ),
                            if (x.topProducts.isEmpty)
                              const Text(
                                'No completed product sales in this period.',
                              ),
                            ...x.topProducts.indexed.map(
                              (entry) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: ProductImage(
                                    path:
                                        entry.$2['photo_path'] as String? ?? '',
                                    borderRadius: 8,
                                  ),
                                ),
                                title: Text(
                                  '${entry.$1 + 1}. ${entry.$2['name']}',
                                ),
                                subtitle: Text(
                                  '${quantity(entry.$2)} sold • ${standardMoney(entry.$2['sales_amount'] as int? ?? 0)}',
                                ),
                              ),
                            ),
                          ],
                        ),
                        StoreOverviewPanel(
                          title: 'Current Stock Alerts',
                          icon: Icons.warning_amber_outlined,
                          action: viewAll(4),
                          children: [
                            if (alerts.isEmpty)
                              const Text(
                                'Stock is healthy. No products need replenishment.',
                              ),
                            ...alerts.map(
                              (row) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: ProductImage(
                                    path: row['photo_path'] as String? ?? '',
                                    borderRadius: 8,
                                  ),
                                ),
                                title: Text(row['name']! as String),
                                subtitle: Text(
                                  '${quantity(row)} remaining',
                                  style: TextStyle(
                                    color:
                                        (row['current_quantity']! as int) == 0
                                        ? accent('expense')
                                        : (Theme.of(context)
                                                  .extension<
                                                    AppSemanticColors
                                                  >()
                                                  ?.warning ??
                                              const Color(0xFFB36B00)),
                                  ),
                                ),
                                onTap: () => widget.navigate(4),
                              ),
                            ),
                          ],
                        ),
                        StoreOverviewPanel(
                          title: 'Recent Activity',
                          icon: Icons.history,
                          action: viewAll(11),
                          children: [
                            if (activity.isEmpty)
                              const Text(
                                'Your store activity will appear here.',
                              ),
                            ...activity.map((row) {
                              final local = DateTime.parse(
                                row['created_at']! as String,
                              ).toLocal();
                              final description =
                                  (row['description']! as String)
                                      .replaceAll(
                                        RegExp(r'\b[A-Z]{2,}-\d+\b'),
                                        '',
                                      )
                                      .replaceAll(RegExp(r'\s+'), ' ')
                                      .trim();
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(description),
                                    Text(
                                      '${MaterialLocalizations.of(context).formatShortDate(local)} • ${TimeOfDay.fromDateTime(local).format(context)} • ${row['actor_name'] ?? 'Not recorded'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                Text(
                  'Quick Actions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => widget.navigate(0),
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Start Sale'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.navigate(7),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Expense'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.navigate(2),
                      icon: const Icon(Icons.handshake_outlined),
                      label: const Text('Receive Consignment'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.navigate(9),
                      icon: const Icon(Icons.assessment_outlined),
                      label: const Text('View Reports'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'UTANG payments are collections, not new sales. Transaction counts include sales, payments, expenses, supplier payments and GCash services.',
                ),
              ],
            ),
          ),
          loaded: true,
        );
      },
    ),
  );
  Widget viewAll(int target) => TextButton(
    onPressed: () => widget.navigate(target),
    child: const Text('View All'),
  );
  Widget metric(String title, String value, IconData icon, Color color) =>
      StoreSummaryCard(title: title, icon: icon, accent: color, value: value);
}
