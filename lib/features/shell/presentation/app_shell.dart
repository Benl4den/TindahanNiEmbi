import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../repositories/activity_log_repository.dart';
import '../../../repositories/cash_sale_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/payment_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/reports_repository.dart';
import '../../../repositories/utang_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/backup_service.dart';
import '../../../services/product_photo_service.dart';
import '../../activity_logs/presentation/activity_logs_screen.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../cash_sales/presentation/cash_sale_screen.dart';
import '../../categories/presentation/categories_screen.dart';
import '../../inventory/presentation/inventory_screen.dart';
import '../../products/presentation/products_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../security/presentation/security_screen.dart';
import '../../utang/presentation/utang_flow.dart';
import '../../utang/presentation/utang_checkout.dart';
import '../../../database/app_database.dart';

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
  String get role => widget.role == UserRole.owner ? 'OWNER' : 'STAFF';
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final destinations = const [
      NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Sales'),
      NavigationDestination(
        icon: Icon(Icons.inventory_2_outlined),
        label: 'Inventory',
      ),
      NavigationDestination(
        icon: Icon(Icons.people_alt_outlined),
        label: 'UTANG',
      ),
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
              extended: MediaQuery.sizeOf(context).width >= 1200,
              selectedIndex: selected,
              onDestinationSelected: (i) => setState(() => selected = i),
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Icon(Icons.storefront, size: 36),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: TextButton.icon(
                      onPressed: widget.lock,
                      icon: const Icon(Icons.lock),
                      label: const Text('Lock App'),
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
              selectedIndex: selected == 4 ? 3 : selected.clamp(0, 2),
              onDestinationSelected: (i) =>
                  setState(() => selected = i == 3 ? 4 : i),
              destinations: [
                destinations[0],
                destinations[1],
                destinations[2],
                destinations[4],
              ],
            ),
    );
  }

  Widget _body() => switch (selected) {
    0 => FutureBuilder(
      future: SqliteProductRepository(widget.database).searchActive(),
      builder: (_, s) => !s.hasData
          ? const Center(child: CircularProgressIndicator())
          : CashSaleScreen(
              embedded: true,
              products: s.data!,
              loadProducts: SqliteProductRepository(widget.database)
                  .searchActive,
              repository: CashSaleRepository(widget.database, actorRole: role),
              onUtang: (items) async {
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UtangCheckoutPicker(
                      customers: SqliteCustomerRepository(widget.database),
                      utang: UtangRepository(widget.database, actorRole: role),
                      products: s.data!,
                      items: items,
                    ),
                  ),
                );
                return ok == true;
              },
            ),
    ),
    1 => InventoryScreen(
      repository: InventoryRepository(widget.database, actorRole: role),
      allowAdjustment: widget.role == UserRole.owner,
    ),
    2 => UtangCustomerScreen(
      customers: SqliteCustomerRepository(widget.database),
      products: SqliteProductRepository(widget.database),
      utang: UtangRepository(widget.database, actorRole: role),
      payments: PaymentRepository(widget.database, actorRole: role),
    ),
    3 =>
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
      body: GridView.builder(
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
    );
  }
}
