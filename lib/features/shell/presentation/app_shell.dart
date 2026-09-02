import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../repositories/activity_log_repository.dart';
import '../../../repositories/cash_sale_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/dashboard_repository.dart';
import '../../../repositories/inventory_repository.dart';
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
  bool railExpanded = true;
  String get role => widget.role == UserRole.owner ? 'OWNER' : 'STAFF';
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
        label: 'UTANG',
      ),
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
          if (wide)
            NavigationRail(
              extended: railExpanded,
              selectedIndex: selected,
              onDestinationSelected: (i) => setState(() => selected = i),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    const Icon(Icons.storefront, size: 36),
                    IconButton(
                      tooltip: railExpanded
                          ? 'Collapse navigation'
                          : 'Expand navigation',
                      onPressed: () =>
                          setState(() => railExpanded = !railExpanded),
                      icon: Icon(
                        railExpanded ? Icons.chevron_left : Icons.chevron_right,
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: railExpanded
                        ? TextButton.icon(
                            onPressed: widget.lock,
                            icon: const Icon(Icons.lock),
                            label: const Text('Lock App'),
                          )
                        : IconButton(
                            tooltip: 'Lock App',
                            onPressed: widget.lock,
                            icon: const Icon(Icons.lock),
                          ),
                  ),
                ),
              ),
              destinations: destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: d.icon,
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
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
              onDestinationSelected: (i) =>
                  setState(() => selected = i == 3 ? 9 : [0, 3, 6][i]),
              destinations: [
                destinations[0],
                destinations[3],
                destinations[6],
                destinations[9],
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
      builder: (_, s) => !s.hasData
          ? const Center(child: CircularProgressIndicator())
          : CashSaleScreen(
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
              loadProducts: SqliteProductRepository(widget.database)
                  .searchActive,
              repository: CashSaleRepository(widget.database, actorRole: role),
              reversals: widget.role == UserRole.owner
                  ? ReversalRepository(widget.database)
                  : null,
              onUtang: (items) async {
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UtangCheckoutPicker(
                      customers: SqliteCustomerRepository(widget.database),
                      utang: UtangRepository(widget.database, actorRole: role),
                      products: s.data![0] as List<Product>,
                      items: items,
                    ),
                  ),
                );
                return ok == true;
              },
            ),
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
          ? DailyClosingScreen(
              repository: OperationsRepository(widget.database),
            )
          : _denied(),
    8 =>
      widget.role == UserRole.owner
          ? ReportsScreen(repository: ReportsRepository(widget.database))
          : _denied(),
    _ => _more(),
  };

  Widget _denied() => const Center(child: Text('Owner permission required.'));
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
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: Column(
        children: [
          if (owner) _ownerAlerts(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                mainAxisExtent: 120,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final x = items[i];
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (x.action != null) {
                        x.action!();
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => x.page!),
                        ).then((_) => setState(() {}));
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Icon(x.icon, size: 34),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              x.label,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
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
                'Outstanding UTANG ₱${(s.outstandingCentavos / 100).toStringAsFixed(2)}',
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
