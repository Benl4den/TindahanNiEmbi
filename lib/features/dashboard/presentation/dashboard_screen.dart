import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../widgets/dashboard_action_card.dart';
import '../../../widgets/summary_card.dart';
import '../../../repositories/dashboard_repository.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.onCategoriesTap,
    required this.onProductsTap,
    required this.onInventoryTap,
    required this.onStockInTap,
    required this.onCustomersTap,
    required this.onUtangTap,
    required this.onCashSaleTap,
    required this.onReportsTap,
    required this.loadSummary,
    required this.onBackupTap,
    required this.onSecurityTap,
    required this.onLockTap,
  });

  final VoidCallback onCategoriesTap;
  final VoidCallback onProductsTap;
  final VoidCallback onInventoryTap;
  final VoidCallback onStockInTap;
  final VoidCallback onCustomersTap;
  final VoidCallback onUtangTap;
  final VoidCallback onCashSaleTap;
  final VoidCallback onReportsTap;
  final Future<DashboardSummary> Function() loadSummary;
  final VoidCallback onBackupTap;
  final VoidCallback onSecurityTap;
  final VoidCallback onLockTap;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 900 ? 4 : 2;
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            onPressed: widget.onLockTap,
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.welcome,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.overview,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  FutureBuilder<DashboardSummary>(
                    future: widget.loadSummary(),
                    builder: (_, snapshot) {
                      final s = snapshot.data;
                      return GridView.count(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.55,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          SummaryCard(
                            label: AppStrings.products,
                            value: '${s?.products ?? 0}',
                          ),
                          SummaryCard(
                            label: AppStrings.lowStock,
                            value: '${s?.lowStock ?? 0}',
                          ),
                          SummaryCard(
                            label: AppStrings.outOfStock,
                            value: '${s?.outOfStock ?? 0}',
                          ),
                          SummaryCard(
                            label: AppStrings.totalUtang,
                            value:
                                '₱${((s?.outstandingCentavos ?? 0) / 100).toStringAsFixed(2)}',
                          ),
                          SummaryCard(
                            label: 'Items Sold Today',
                            value: '${s?.stockOutToday ?? 0}',
                          ),
                          SummaryCard(
                            label: AppStrings.inventoryValue,
                            value:
                                '₱${((s?.inventoryValueCentavos ?? 0) / 100).toStringAsFixed(2)}',
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  GridView.count(
                    crossAxisCount: columns,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.35,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      DashboardActionCard(
                        label: AppStrings.products,
                        icon: Icons.shopping_basket_outlined,
                        onTap: widget.onProductsTap,
                      ),
                      DashboardActionCard(
                        label: AppStrings.categories,
                        icon: Icons.category_outlined,
                        onTap: widget.onCategoriesTap,
                      ),
                      DashboardActionCard(
                        label: AppStrings.inventory,
                        icon: Icons.inventory_2_outlined,
                        onTap: widget.onInventoryTap,
                      ),
                      DashboardActionCard(
                        label: AppStrings.utang,
                        icon: Icons.people_alt_outlined,
                        onTap: widget.onUtangTap,
                      ),
                      DashboardActionCard(
                        label: AppStrings.customers,
                        icon: Icons.people_outline,
                        onTap: widget.onCustomersTap,
                      ),
                      DashboardActionCard(
                        label: AppStrings.addStock,
                        icon: Icons.add_box_outlined,
                        onTap: widget.onStockInTap,
                      ),
                      DashboardActionCard(
                        label: AppStrings.reports,
                        icon: Icons.bar_chart_outlined,
                        onTap: widget.onReportsTap,
                      ),
                      DashboardActionCard(
                        label: 'Sales',
                        icon: Icons.point_of_sale,
                        onTap: widget.onCashSaleTap,
                      ),
                      DashboardActionCard(
                        label: 'Backup & Restore',
                        icon: Icons.backup_outlined,
                        onTap: widget.onBackupTap,
                      ),
                      DashboardActionCard(
                        label: 'Security',
                        icon: Icons.security,
                        onTap: widget.onSecurityTap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
