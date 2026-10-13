import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/formatters/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../repositories/dashboard_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/operations_repository.dart';
import '../../../services/app_refresh_controller.dart';
import '../../../services/settings_service.dart';
import '../../../widgets/store_summary_card.dart';
import '../../../widgets/balanced_card_grid.dart';
import '../../../widgets/product_image.dart';
import '../../../widgets/store_overview_panel.dart';
import '../../../widgets/brand_logo.dart';
import '../../help/help_button.dart';
import '../../help/help_content.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.database,
    required this.navigate,
    this.refreshRevision = 0,
    this.walletServicesAllowed = true,
  });
  final Database database;
  final void Function(int) navigate;
  final int refreshRevision;
  final bool walletServicesAllowed;
  @override
  State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends State<DashboardScreen> {
  int period = 0;
  late Future<List<Object>> data;
  late Future<String> storeName;
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
        oldWidget.database != widget.database ||
        oldWidget.walletServicesAllowed != widget.walletServicesAllowed) {
      reload();
    }
  }

  @override
  void dispose() {
    AppRefreshController.instance.removeListener(_refresh);
    super.dispose();
  }

  void reload() {
    storeName = SettingsService(widget.database).storeName;
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
          widget.walletServicesAllowed
              ? widget.database.rawQuery(
                  'SELECT COALESCE(SUM(amount_change_centavos),0) balance FROM gcash_ledger_entries',
                )
              : Future<List<Map<String, Object?>>>.value(const []),
          widget.walletServicesAllowed
              ? widget.database.rawQuery(
                  'SELECT COALESCE(SUM(amount_change_centavos),0) balance FROM maya_ledger_entries',
                )
              : Future<List<Map<String, Object?>>>.value(const []),
          widget.database.rawQuery(
            'SELECT name,photo_path,current_quantity,base_unit_code,base_unit_label FROM products WHERE is_archived=0 AND current_quantity<=minimum_stock_level ORDER BY current_quantity ASC,name COLLATE NOCASE LIMIT 5',
          ),
          widget.database.rawQuery('''SELECT a.event_type,
            CASE WHEN a.event_type='SPECIAL_INVENTORY_ASSIGNED' THEN
              COALESCE((SELECT substr(a.description,1,length(a.description)-length(g.code)) || g.name
                FROM inventory_groups g
                WHERE substr(a.description,-length(' assigned to ' || g.code))=' assigned to ' || g.code
                ORDER BY LENGTH(g.code) DESC LIMIT 1),a.description)
            ELSE a.description END description,
            a.created_at,a.actor_name FROM
              (SELECT id,event_type,description,created_at,actor_name
               FROM activity_logs
               WHERE ${widget.walletServicesAllowed ? '1=1' : "COALESCE(related_entity_type,'') NOT IN ('GCASH_SERVICE','MAYA_SERVICE','GCASH_LEDGER','MAYA_LEDGER') AND event_type NOT LIKE 'GCASH_%' AND event_type NOT LIKE 'MAYA_%'"}
               ORDER BY created_at DESC,id DESC LIMIT 5) a
            ORDER BY a.created_at DESC,a.id DESC'''),
          widget.database.rawQuery(
            'SELECT COUNT(*) count FROM cash_sales WHERE status=\'POSTED\' AND occurred_at>=? AND occurred_at<? UNION ALL SELECT COUNT(*) FROM utang_transactions WHERE status=\'POSTED\' AND COALESCE(is_existing_balance,0)=0 AND occurred_at>=? AND occurred_at<?',
            [
              start.toUtc().toIso8601String(),
              end.toUtc().toIso8601String(),
              start.toUtc().toIso8601String(),
              end.toUtc().toIso8601String(),
            ],
          ),
          InventoryRepository(widget.database).ownedHealth(),
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
    key: const ValueKey('dashboard-header'),
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
    child: LayoutBuilder(
      builder: (_, box) {
        final theme = Theme.of(context);
        final status = loaded && updatedAt != null
            ? 'Updated at ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(updatedAt!))}'
            : failed
            ? 'Could not update overview'
            : 'Updating…';
        final wide =
            box.maxWidth >= 720 &&
            MediaQuery.textScalerOf(context).scale(14) <= 18;
        if (!wide) {
          return Column(
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
              _storeNameLabel(theme),
              Text(
                'Your quick store overview. Keep track of sales, expenses, inventory and more.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 3),
              Text(status, style: theme.textTheme.bodySmall),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Dashboard',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  _storeNameLabel(theme),
                  Text(
                    'Your quick store overview. Keep track of sales, expenses, inventory and more.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(status, style: theme.textTheme.bodySmall),
            const SizedBox(width: 8),
            const HelpButton(topic: HelpTopicId.dashboard),
          ],
        );
      },
    ),
  );

  Widget _storeNameLabel(ThemeData theme) => FutureBuilder<String>(
    future: storeName,
    builder: (_, snapshot) => snapshot.hasData
        ? Text(
            snapshot.data!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          )
        : const SizedBox.shrink(),
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
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Today')),
              ButtonSegment(value: 1, label: Text('This Week')),
              ButtonSegment(value: 2, label: Text('This Month')),
            ],
            selected: {period},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => setState(() {
              period = selection.single;
              reload();
            }),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFF0B4930)
                    : Colors.white,
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? const Color(0xFFD9F3DE)
                    : const Color(0xFF194F3B),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: Color(0xFFE1F1E8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date,
                key: const ValueKey('dashboard-period-date'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFE1F1E8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _frame(Widget child, {bool loaded = false, bool failed = false}) =>
      SafeArea(
        top: MediaQuery.sizeOf(context).width < 900,
        bottom: false,
        child: Column(
          children: [
            _header(loaded: loaded, failed: failed),
            const Divider(height: 1),
            Expanded(child: child),
          ],
        ),
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
        final mayaWallet = snapshot.data![3] as List<Map<String, Object?>>;
        final alerts = snapshot.data![4] as List<Map<String, Object?>>;
        final activity = snapshot.data![5] as List<Map<String, Object?>>;
        final counts = snapshot.data![6] as List<Map<String, Object?>>;
        final salesCount = counts.fold<int>(
          0,
          (sum, row) => sum + (row['count']! as int),
        );
        final label = ['Today', 'This Week', 'This Month'][period];
        final periodDescription = ['today', 'this week', 'this month'][period];
        final salesBreakdown = [
          'Cash ${standardMoney(x.cashSales)}',
          'GCash ${standardMoney(x.gcashSales)}',
          if (x.mayaSales != 0) 'Maya ${standardMoney(x.mayaSales)}',
          'UTANG ${standardMoney(x.newUtang)}',
        ].join(' • ');
        if (MediaQuery.sizeOf(context).width < 600) {
          return _phoneDashboard(
            x,
            snapshot.data![7] as OwnedInventoryHealth,
            counts,
          );
        }
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
                      '$salesCount ${salesCount == 1 ? 'sale transaction' : 'sale transactions'}\n$salesBreakdown',
                  icon: Icons.bar_chart_outlined,
                ),
                const SizedBox(height: 16),
                _quickActions(),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Store Overview',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(width: 6),
                    const Tooltip(
                      message: 'A quick view of the selected period and current balances.',
                      child: Icon(Icons.info_outline, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
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
                      if (widget.walletServicesAllowed) ...[
                        metric(
                          'Current GCash Balance',
                          standardMoney(wallet.single['balance']! as int),
                          Icons.account_balance_wallet_outlined,
                          accent('gcash'),
                        ),
                        metric(
                          'Current Maya Balance',
                          standardMoney(mayaWallet.single['balance']! as int),
                          Icons.account_balance_wallet_outlined,
                          accent('gcash'),
                        ),
                      ],
                      metric(
                        'Amount Owed to Suppliers',
                        standardMoney(current.supplierPayableCentavos),
                        Icons.handshake_outlined,
                        accent('consignment'),
                      ),
                      if (widget.walletServicesAllowed)
                        metric(
                          '${x.transactionCount} ${x.transactionCount == 1 ? 'transaction' : 'transactions'} $periodDescription',
                          '',
                          Icons.history,
                          accent(''),
                          caption: 'Includes sales, payments, expenses, supplier payments, e-wallet services, and loan activity.',
                        ),
                    ];
                    return BalancedCardGrid(children: cards);
                  },
                ),
                const SizedBox(height: 18),
                _stockAlertsPanel(alerts),
                const SizedBox(height: 14),
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
                            if (x.topProducts.isEmpty)
                              const Text(
                                'No completed product sales in this period.',
                              ),
                            ...x.topProducts
                                .take(3)
                                .indexed
                                .map(
                                  (entry) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: ProductImage(
                                        path:
                                            entry.$2['photo_path'] as String? ??
                                            '',
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
                                        RegExp(r'\b[A-Z][A-Z0-9_]*[_-]\d+\b'),
                                        '',
                                      )
                                      .replaceAll(RegExp(r'\s+'), ' ')
                                      .trim();
                              final recordedActor =
                                  (row['actor_name'] as String?)?.trim();
                              final actor =
                                  recordedActor == null ||
                                      recordedActor.isEmpty ||
                                      recordedActor.toLowerCase() ==
                                          'not recorded'
                                  ? 'System'
                                  : recordedActor;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(description),
                                    Text(
                                      '${MaterialLocalizations.of(context).formatShortDate(local)} • ${TimeOfDay.fromDateTime(local).format(context)} • $actor',
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
              ],
            ),
          ),
          loaded: true,
        );
      },
    ),
  );

  Widget _phoneDashboard(
    DailyClosingSummary summary,
    OwnedInventoryHealth inventory,
    List<Map<String, Object?>> counts,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();
    final date =
        '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][now.weekday - 1]}, ${MaterialLocalizations.of(context).formatMediumDate(now)}';
    final salesCount = counts.fold<int>(
      0,
      (total, row) => total + (row['count'] as int? ?? 0),
    );
    final utangCount = counts.length > 1 ? counts[1]['count'] as int? ?? 0 : 0;
    const headerGreen = Color(0xFF07553B);
    final warning = context.semanticColors.warning;
    final danger = context.semanticColors.danger;

    Widget metricCard(
      String key,
      String label,
      String value,
      String caption,
      IconData icon,
      Color accent,
    ) => Container(
      key: ValueKey('phone-metric-$key'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 31,
                height: 31,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );

    Widget actionCard(
      String key,
      String label,
      IconData icon,
      Color accent,
      VoidCallback action,
    ) => Material(
      key: ValueKey('phone-quick-$key'),
      color: colors.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 21, color: accent),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget stockCard(
      String key,
      String label,
      int value,
      IconData icon,
      Color accent,
    ) => Container(
      key: ValueKey('phone-stock-$key'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 23),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 2,
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: theme.textTheme.titleMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: headerGreen,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF139C68),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: BrandLogo(size: 34, dark: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FutureBuilder<String>(
                            future: storeName,
                            builder: (_, snapshot) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  snapshot.data ??
                                      SettingsService.fallbackStoreName,
                                  key: const ValueKey(
                                    'phone-dashboard-store-name',
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'TindaSari PH',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: const Color(0xFFDDF4E8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.notifications_none_outlined,
                          color: Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Good day!',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      date,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFDDF4E8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(reload);
                try {
                  await data;
                } catch (_) {
                  /* Retry UI shows the error. */
                }
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
                            child: Material(
                              color: period == i
                                  ? colors.primary
                                  : colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                key: ValueKey('phone-period-$i'),
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => setState(() {
                                  period = i;
                                  reload();
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 9,
                                  ),
                                  child: Text(
                                    const [
                                      'Today',
                                      'This Week',
                                      'This Month',
                                    ][i],
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: period == i
                                          ? colors.onPrimary
                                          : colors.onSurface,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (_, box) => GridView.count(
                      crossAxisCount: 2,
                      childAspectRatio: box.maxWidth < 300
                          ? 1.1
                          : box.maxWidth < 340
                          ? 1.3
                          : 1.55,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        metricCard(
                          'sales',
                          'Total Sales',
                          standardMoney(summary.totalSales + summary.newUtang),
                          '$salesCount ${salesCount == 1 ? 'transaction' : 'transactions'}',
                          Icons.shopping_cart_outlined,
                          colors.primary,
                        ),
                        metricCard(
                          'gcash',
                          'GCash Fees',
                          widget.walletServicesAllowed
                              ? standardMoney(
                                  summary.cashInServiceFees +
                                      summary.cashOutServiceFees,
                                )
                              : '—',
                          widget.walletServicesAllowed
                              ? '${summary.cashInServiceCount + summary.cashOutServiceCount} services'
                              : 'PRO',
                          Icons.account_balance_wallet_outlined,
                          const Color(0xFF2368D3),
                        ),
                        metricCard(
                          'utang',
                          'New UTANG',
                          standardMoney(summary.newUtang),
                          '$utangCount ${utangCount == 1 ? 'transaction' : 'transactions'}',
                          Icons.receipt_long_outlined,
                          danger,
                        ),
                        metricCard(
                          'expenses',
                          'Expenses',
                          standardMoney(summary.operatingExpenses),
                          '${summary.expenseCount ?? 0} expenses',
                          Icons.receipt_outlined,
                          warning,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 17),
                  Text(
                    'Quick Actions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 9),
                  LayoutBuilder(
                    builder: (_, box) {
                      final columns = box.maxWidth >= 308 ? 4 : 2;
                      final actions = [
                        actionCard(
                          'sale',
                          'Start Sale',
                          Icons.shopping_cart_checkout,
                          colors.primary,
                          () => widget.navigate(0),
                        ),
                        actionCard(
                          'expense',
                          'Add Expense',
                          Icons.receipt_long_outlined,
                          const Color(0xFFB341A4),
                          () => widget.navigate(7),
                        ),
                        actionCard(
                          'consignment',
                          'Receive Consignment',
                          Icons.inventory_2_outlined,
                          const Color(0xFF6550BB),
                          () => widget.navigate(2),
                        ),
                        actionCard(
                          'reports',
                          'View Reports',
                          Icons.assessment_outlined,
                          const Color(0xFF1785C7),
                          () => widget.navigate(9),
                        ),
                      ];
                      return GridView.count(
                        crossAxisCount: columns,
                        childAspectRatio: columns == 4 ? .86 : 1.25,
                        mainAxisSpacing: 7,
                        crossAxisSpacing: 7,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: actions,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Inventory Summary',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Open Inventory',
                        onPressed: () => widget.navigate(3),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  LayoutBuilder(
                    builder: (_, box) => GridView.count(
                      crossAxisCount: 3,
                      childAspectRatio: box.maxWidth < 300
                          ? .78
                          : box.maxWidth < 340
                          ? .9
                          : 1.05,
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        stockCard(
                          'active',
                          'Active Products',
                          inventory.activeProducts,
                          Icons.inventory_2_outlined,
                          colors.primary,
                        ),
                        stockCard(
                          'low',
                          'Low Stock',
                          inventory.lowStock,
                          Icons.warning_amber_outlined,
                          warning,
                        ),
                        stockCard(
                          'out',
                          'Out of Stock',
                          inventory.outOfStock,
                          Icons.cancel_outlined,
                          danger,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (_, box) {
          final columns = box.maxWidth < 500
              ? 1
              : (box.maxWidth >= 900 ? 4 : 2);
          const spacing = 12.0;
          final width = (box.maxWidth - spacing * (columns - 1)) / columns;
          Widget action(Widget button) => SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: button,
            ),
          );
          return Wrap(
            spacing: spacing,
            runSpacing: 10,
            children: [
              action(
                FilledButton.icon(
                  onPressed: () => widget.navigate(0),
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Start Sale'),
                ),
              ),
              action(
                OutlinedButton.icon(
                  onPressed: () => widget.navigate(7),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Expense'),
                ),
              ),
              action(
                OutlinedButton.icon(
                  onPressed: () => widget.navigate(2),
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Receive Consignment'),
                ),
              ),
              action(
                OutlinedButton.icon(
                  onPressed: () => widget.navigate(9),
                  icon: const Icon(Icons.assessment_outlined),
                  label: const Text('View Reports'),
                ),
              ),
            ],
          );
        },
      ),
    ],
  );

  Widget _stockAlertsPanel(List<Map<String, Object?>> alerts) {
    final warning =
        Theme.of(context).extension<AppSemanticColors>()?.warning ??
        const Color(0xFFB36B00);
    return StoreOverviewPanel(
      title: 'Current Stock Alerts',
      icon: alerts.isEmpty
          ? Icons.check_circle_outline
          : Icons.warning_amber_outlined,
      accent: alerts.isEmpty ? Theme.of(context).colorScheme.primary : warning,
      action: viewAll(4),
      children: alerts.isEmpty
          ? [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .16),
                  child: const Icon(Icons.check),
                ),
                title: const Text('Stock is healthy!'),
                subtitle: const Text('No low-stock or out-of-stock products.'),
              ),
            ]
          : alerts.take(3).map((row) {
              final out = (row['current_quantity']! as int) == 0;
              return ListTile(
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
                  '${out ? 'Out of Stock' : 'Low Stock'} • ${quantity(row)} remaining',
                  style: TextStyle(color: out ? accent('expense') : warning),
                ),
                onTap: () => widget.navigate(4),
              );
            }).toList(),
    );
  }

  Widget viewAll(int target) => TextButton(
    onPressed: () => widget.navigate(target),
    child: const Text('View All'),
  );
  Widget metric(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? caption,
  }) => StoreSummaryCard(
    title: title,
    icon: icon,
    accent: color,
    value: value,
    caption: caption,
  );
}
