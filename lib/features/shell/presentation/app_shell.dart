import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../repositories/activity_log_repository.dart';
import '../../../repositories/cash_sale_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/dashboard_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/expense_repository.dart';
import '../../../repositories/payment_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/reports_repository.dart';
import '../../../repositories/operations_repository.dart';
import '../../../repositories/reversal_repository.dart';
import '../../../repositories/utang_repository.dart';
import '../../../repositories/consignment_repository.dart';
import '../../../repositories/special_inventory_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/backup_service.dart';
import '../../../services/product_photo_service.dart';
import '../../../services/data_integrity_service.dart';
import '../../../services/storage_management_service.dart';
import '../../activity_logs/presentation/activity_logs_screen.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../cash_sales/presentation/cash_sale_screen.dart';
import '../../categories/presentation/categories_screen.dart';
import '../../consignment/presentation/consignment_screen.dart';
import '../../inventory/presentation/inventory_screen.dart';
import '../../expenses/presentation/expenses_screen.dart';
import '../../operations/presentation/daily_closing_screen.dart';
import '../../operations/presentation/integrity_screen.dart';
import '../../operations/presentation/restock_screen.dart';
import '../../operations/presentation/storage_management_screen.dart';
import '../../products/presentation/products_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../special_inventory/presentation/selecta_screen.dart';
import '../../security/presentation/security_screen.dart';
import '../../utang/presentation/utang_flow.dart';
import '../../utang/presentation/utang_checkout.dart';
import '../../../database/app_database.dart';
import '../../../models/category.dart';
import '../../../models/product.dart';
import '../../../widgets/app_state_view.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.database,
    required this.appDatabase,
    required this.role,
    required this.lock,
  });
  final Database database;
  final AppDatabase appDatabase;
  final UserRole role;
  final VoidCallback lock;
  @override
  State<AppShell> createState() => _State();
}

class _State extends State<AppShell> {
  int selected = 0;
  int salesRevision = 0;
  bool railExpanded = true;
  String get role => widget.role == UserRole.owner ? 'OWNER' : 'STAFF';

  void _select(int destination) {
    setState(() {
      selected = destination;
      if (destination == 0) salesRevision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final destinations = const [
      NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Sales'),
      NavigationDestination(
        icon: Icon(Icons.icecream_outlined),
        label: 'Selecta Products',
      ),
      NavigationDestination(
        icon: Icon(Icons.handshake_outlined),
        label: 'Consignment',
      ),
      NavigationDestination(
        icon: Icon(Icons.inventory_2_outlined),
        label: 'Inventory',
      ),
      NavigationDestination(
        icon: Icon(Icons.add_shopping_cart),
        label: 'Restock',
      ),
      NavigationDestination(icon: Icon(Icons.inventory), label: 'Products'),
      NavigationDestination(
        icon: Icon(Icons.people_alt_outlined),
        label: 'Credit',
      ),
      NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Expenses'),
      NavigationDestination(icon: Icon(Icons.today), label: 'Daily Closing'),
      NavigationDestination(
        icon: Icon(Icons.assessment_outlined),
        label: 'Reports',
      ),
      NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
    ];
    final body = _body();
    return Scaffold(
      body: Row(
        children: [
          if (wide) _sidebar(destinations),
          if (wide) const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: const [0, 3, 6].contains(selected)
                  ? const [0, 3, 6].indexOf(selected)
                  : 3,
              onDestinationSelected: (i) => _select(i == 3 ? 10 : [0, 3, 6][i]),
              destinations: [
                destinations[0],
                destinations[3],
                destinations[6],
                destinations[10],
              ],
            ),
    );
  }

  Widget _body() => switch (selected) {
    0 => FutureBuilder<List<Object>>(
      future: Future.wait<Object>([
        SqliteProductRepository(widget.database).searchActive(),
        SqliteCategoryRepository(widget.database).getActive(),
        ReportsRepository(widget.database).frequentProducts(),
        SpecialInventoryRepository(widget.database).products('SELECTA'),
      ]),
      builder: (_, s) {
        if (s.hasError) {
          return AppStateView.error(
            title: 'Could not load Sales',
            message: 'Please check the store data and try again.',
            actionLabel: 'Try Again',
            onAction: () => setState(() {}),
          );
        }
        if (!s.hasData) return const AppLoadingView(label: 'Loading Sales…');
        return CashSaleScreen(
          key: ValueKey('sales-$salesRevision'),
          embedded: true,
          products: s.data![0] as List<Product>,
          categoryNames: {
            for (final c in s.data![1] as List<Category>) c.id: c.name,
          },
          frequentProductNames: {
            for (final x in s.data![2] as List<Map<String, Object?>>)
              x['name']! as String,
          },
          selectaProductIds: {
            for (final p in s.data![3] as List<Product>) p.id,
          },
          loadProducts: SqliteProductRepository(widget.database).searchActive,
          repository: CashSaleRepository(widget.database, actorRole: role),
          reversals: widget.role == UserRole.owner
              ? ReversalRepository(widget.database)
              : null,
          onUtang: (items) async {
            final ok = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (_) => Dialog(
                insetPadding: const EdgeInsets.all(16),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 820,
                    maxHeight: 860,
                  ),
                  child: UtangCheckoutPicker(
                    customers: SqliteCustomerRepository(widget.database),
                    utang: UtangRepository(widget.database, actorRole: role),
                    products: s.data![0] as List<Product>,
                    items: items,
                  ),
                ),
              ),
            );
            return ok == true;
          },
        );
      },
    ),
    1 => SelectaScreen(
      special: SpecialInventoryRepository(widget.database, actorRole: role),
      products: SqliteProductRepository(widget.database),
      inventory: InventoryRepository(widget.database, actorRole: role),
      categories: SqliteCategoryRepository(widget.database),
      photoService: LocalProductPhotoService(),
    ),
    2 => ConsignmentScreen(
      repository: ConsignmentRepository(widget.database, actorRole: role),
      products: SqliteProductRepository(widget.database),
      categories: SqliteCategoryRepository(widget.database),
      photoService: LocalProductPhotoService(),
    ),
    3 => InventoryScreen(
      repository: InventoryRepository(widget.database, actorRole: role),
      allowAdjustment: widget.role == UserRole.owner,
    ),
    4 =>
      widget.role == UserRole.owner
          ? RestockScreen(
              operations: OperationsRepository(widget.database),
              inventory: InventoryRepository(widget.database, actorRole: role),
              openConsignment: () => setState(() => selected = 2),
            )
          : _denied(),
    5 =>
      widget.role == UserRole.owner
          ? ProductsScreen(
              repository: SqliteProductRepository(
                widget.database,
                actorRole: role,
              ),
              categoryRepository: SqliteCategoryRepository(widget.database),
              photoService: LocalProductPhotoService(),
            )
          : _denied(),
    6 => UtangCustomerScreen(
      customers: SqliteCustomerRepository(widget.database),
      products: SqliteProductRepository(widget.database),
      utang: UtangRepository(widget.database, actorRole: role),
      payments: PaymentRepository(widget.database, actorRole: role),
      reversals: widget.role == UserRole.owner
          ? ReversalRepository(widget.database)
          : null,
    ),
    7 =>
      widget.role == UserRole.owner
          ? ExpensesScreen(
              repository: ExpenseRepository(widget.database, actorRole: role),
              auth: AuthService(widget.database),
            )
          : _denied(),
    8 =>
      widget.role == UserRole.owner
          ? DailyClosingScreen(
              repository: OperationsRepository(widget.database),
            )
          : _denied(),
    9 =>
      widget.role == UserRole.owner
          ? ReportsScreen(repository: ReportsRepository(widget.database))
          : _denied(),
    _ => _more(),
  };

  Widget _sidebar(List<NavigationDestination> destinations) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: railExpanded ? 236 : 76,
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                railExpanded ? 16 : 10,
                14,
                railExpanded ? 10 : 10,
                10,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.storefront,
                      color: Colors.white,
                      size: 27,
                    ),
                  ),
                  if (railExpanded) ...[
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TindahanNiEmbi',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Store Management',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: railExpanded
                    ? Alignment.centerRight
                    : Alignment.center,
                child: IconButton.filledTonal(
                  tooltip: railExpanded
                      ? 'Collapse navigation'
                      : 'Expand navigation',
                  onPressed: () => setState(() => railExpanded = !railExpanded),
                  icon: Icon(
                    railExpanded
                        ? Icons.keyboard_double_arrow_left
                        : Icons.keyboard_double_arrow_right,
                  ),
                ),
              ),
            ),
            const Divider(height: 18),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: destinations.length,
                itemBuilder: (_, i) {
                  final destination = destinations[i], active = selected == i;
                  final tile = InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _select(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      height: 52,
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: EdgeInsets.symmetric(
                        horizontal: railExpanded ? 13 : 16,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? colors.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          IconTheme(
                            data: IconThemeData(
                              size: 25,
                              color: active
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            child: destination.icon,
                          ),
                          if (railExpanded) ...[
                            const SizedBox(width: 13),
                            Expanded(
                              child: Text(
                                destination.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: active
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: active
                                      ? colors.primary
                                      : colors.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                  return railExpanded
                      ? tile
                      : Tooltip(message: destination.label, child: tile);
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Center(
                child: railExpanded
                    ? SizedBox(
                        width: 190,
                        child: OutlinedButton.icon(
                          onPressed: widget.lock,
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('Lock App'),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Lock App',
                        onPressed: widget.lock,
                        icon: const Icon(Icons.lock_outline),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _denied() => const AppStateView(
    icon: Icons.lock_outline,
    title: 'Owner permission required',
    message:
        'Lock the app and sign in with the owner PIN to open this section.',
  );
  Widget _more() {
    final owner = widget.role == UserRole.owner;
    final items =
        <({String label, IconData icon, Widget? page, VoidCallback? action})>[
          (
            label: 'Selecta Products',
            icon: Icons.icecream_outlined,
            page: SelectaScreen(
              special: SpecialInventoryRepository(
                widget.database,
                actorRole: role,
              ),
              products: SqliteProductRepository(widget.database),
              inventory: InventoryRepository(widget.database, actorRole: role),
              categories: SqliteCategoryRepository(widget.database),
              photoService: LocalProductPhotoService(),
            ),
            action: null,
          ),
          (
            label: 'Consignment',
            icon: Icons.handshake_outlined,
            page: ConsignmentScreen(
              repository: ConsignmentRepository(
                widget.database,
                actorRole: role,
              ),
              products: SqliteProductRepository(widget.database),
              categories: SqliteCategoryRepository(widget.database),
              photoService: LocalProductPhotoService(),
            ),
            action: null,
          ),
          if (owner)
            (
              label: 'Restock',
              icon: Icons.add_shopping_cart,
              page: RestockScreen(
                operations: OperationsRepository(widget.database),
                inventory: InventoryRepository(
                  widget.database,
                  actorRole: role,
                ),
                openConsignment: () {
                  Navigator.pop(context);
                  setState(() => selected = 2);
                },
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Daily Closing',
              icon: Icons.today,
              page: DailyClosingScreen(
                repository: OperationsRepository(widget.database),
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Check Data Integrity',
              icon: Icons.fact_check_outlined,
              page: IntegrityScreen(
                service: DataIntegrityService(widget.database),
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Storage Management',
              icon: Icons.storage_outlined,
              page: StorageManagementScreen(
                storage: StorageManagementService(widget.appDatabase),
                backups: BackupService(widget.appDatabase),
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Products',
              icon: Icons.inventory,
              page: ProductsScreen(
                repository: SqliteProductRepository(
                  widget.database,
                  actorRole: role,
                ),
                categoryRepository: SqliteCategoryRepository(widget.database),
                photoService: LocalProductPhotoService(),
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Categories',
              icon: Icons.category,
              page: CategoriesScreen(
                repository: SqliteCategoryRepository(widget.database),
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Reports',
              icon: Icons.assessment,
              page: ReportsScreen(
                repository: ReportsRepository(widget.database),
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Activity Logs',
              icon: Icons.history,
              page: ActivityLogsScreen(
                repository: ActivityLogRepository(widget.database),
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Backup & Restore',
              icon: Icons.backup,
              page: BackupScreen(
                service: BackupService(widget.appDatabase),
                onRestored: () => setState(() {}),
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Security',
              icon: Icons.security,
              page: SecurityScreen(auth: AuthService(widget.database)),
              action: null,
            ),
          (
            label: 'Lock App',
            icon: Icons.lock,
            page: null,
            action: widget.lock,
          ),
        ];
    void open(
      ({String label, IconData icon, Widget? page, VoidCallback? action}) x,
    ) {
      if (x.action != null) {
        x.action!();
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => x.page!),
        ).then((_) => setState(() {}));
      }
    }

    final management = items
        .where(
          (x) => const {
            'Selecta Products',
            'Consignment',
            'Restock',
            'Products',
            'Categories',
          }.contains(x.label),
        )
        .toList();
    final tools = items
        .where(
          (x) => const {
            'Daily Closing',
            'Check Data Integrity',
            'Storage Management',
            'Reports',
            'Activity Logs',
          }.contains(x.label),
        )
        .toList();
    final security = items
        .where((x) => const {'Security', 'Lock App'}.contains(x.label))
        .toList();
    final backup = items.where((x) => x.label == 'Backup & Restore').toList();
    Widget section(
      String title,
      String description,
      List<({String label, IconData icon, Widget? page, VoidCallback? action})>
      entries,
    ) {
      if (entries.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (_, box) => GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: box.maxWidth >= 850
                      ? 3
                      : box.maxWidth >= 540
                      ? 2
                      : 1,
                  mainAxisExtent: 92,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: entries.length,
                itemBuilder: (_, i) {
                  final x = entries[i];
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => open(x),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                x.icon,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                x.label,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('More — Control Center')),
      body: Column(
        children: [
          if (owner) _ownerAlerts(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                section(
                  'MANAGEMENT',
                  'Products, inventory groups, and suppliers',
                  management,
                ),
                section(
                  'SYSTEM & TOOLS',
                  'Operational checks, reports, and audit history',
                  tools,
                ),
                section(
                  'SECURITY',
                  'Access controls and app locking',
                  security,
                ),
                section(
                  'DATA & BACKUP',
                  'Protect and restore store records',
                  backup,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ownerAlerts() => FutureBuilder<List<Object?>>(
    future: Future.wait<Object?>([
      DashboardRepository(widget.database).summary(),
      BackupService(widget.appDatabase).lastSuccessfulBackup(),
    ]),
    builder: (_, snapshot) {
      if (!snapshot.hasData) return const SizedBox(height: 8);
      final s = snapshot.data![0] as DashboardSummary,
          backup = snapshot.data![1] as DateTime?;
      final old =
          backup == null || DateTime.now().difference(backup).inDays > 7;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Row(
          children: [
            ActionChip(
              label: Text('Low Stock ${s.lowStock}'),
              onPressed: () => setState(() => selected = 3),
            ),
            const SizedBox(width: 8),
            ActionChip(
              label: Text('Out of Stock ${s.outOfStock}'),
              onPressed: () => setState(() => selected = 3),
            ),
            const SizedBox(width: 8),
            ActionChip(
              label: Text(
                'Outstanding Credit ₱${(s.outstandingCentavos / 100).toStringAsFixed(2)}',
              ),
              onPressed: () => setState(() => selected = 6),
            ),
            const SizedBox(width: 8),
            ActionChip(
              label: Text(
                'Supplier Payable ₱${(s.supplierPayableCentavos / 100).toStringAsFixed(2)}',
              ),
              onPressed: () => setState(() => selected = 2),
            ),
            if (old) ...[
              const SizedBox(width: 8),
              const Chip(
                avatar: Icon(Icons.backup_outlined),
                label: Text('Backup Recommended'),
              ),
            ],
          ],
        ),
      );
    },
  );
}
