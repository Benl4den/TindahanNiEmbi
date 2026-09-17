import '../../../widgets/brand_logo.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/app_back_navigation.dart';

import '../../../widgets/gcash_icon.dart';

import 'package:sqflite/sqflite.dart';

import '../../../core/formatters/number_format.dart';

import '../../../repositories/activity_log_repository.dart';
import '../../../repositories/staff_activity_repository.dart';
import '../../../repositories/cash_sale_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/dashboard_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/expense_repository.dart';
import '../../../repositories/payment_repository.dart';
import '../../../repositories/payment_accounting_repository.dart';
import '../../../repositories/gcash_service_repository.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/reports_repository.dart';
import '../../../repositories/operations_repository.dart';
import '../../../repositories/reversal_repository.dart';
import '../../../repositories/utang_repository.dart';
import '../../../repositories/consignment_repository.dart';
import '../../../repositories/special_inventory_repository.dart';
import '../../../repositories/sale_draft_repository.dart';
import '../../../repositories/transaction_history_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/backup_service.dart';
import '../../../services/product_photo_service.dart';
import '../../../services/data_integrity_service.dart';
import '../../../services/storage_management_service.dart';
import '../../../services/app_refresh_controller.dart';
import '../../../services/settings_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../activity_logs/presentation/activity_logs_screen.dart';
import '../../activity_logs/presentation/staff_activity_screen.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../cash_sales/presentation/cash_sale_screen.dart';
import '../../categories/presentation/categories_screen.dart';
import '../../consignment/presentation/consignment_screen.dart';
import '../../inventory/presentation/inventory_screen.dart';
import '../../expenses/presentation/expenses_screen.dart';
import '../../gcash/presentation/gcash_screen.dart';
import '../../help/help_guide_screen.dart';
import '../../operations/presentation/daily_closing_screen.dart';
import '../../operations/presentation/integrity_screen.dart';
import '../../operations/presentation/restock_screen.dart';
import '../../operations/presentation/storage_management_screen.dart';
import '../../products/presentation/products_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../special_inventory/presentation/managed_brands_screen.dart';
import '../../security/presentation/security_screen.dart';
import '../../utang/presentation/utang_flow.dart';
import '../../utang/presentation/utang_checkout.dart';
import '../../transactions/transaction_history_screen.dart';
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
    required this.onThemePreferenceChanged,
    required this.onDatabaseRestored,
  });
  final Database database;
  final AppDatabase appDatabase;
  final UserRole role;
  final VoidCallback lock;
  final Future<void> Function(AppThemePreference) onThemePreferenceChanged;
  final VoidCallback onDatabaseRestored;
  @override
  State<AppShell> createState() => _State();
}

class _State extends State<AppShell> {
  final _backController = SectionBackController();
  bool _handlingBack = false;
  int selected = 0;
  bool dashboardAddExpense = false;
  int salesRevision = 0;
  int restockCount = 0;
  int productCount = 0;
  int? pendingConsignorId;
  int? pendingConsignmentProductId;
  bool railExpanded = true;
  String get role => widget.role == UserRole.owner ? 'OWNER' : 'STAFF';

  Future<void> _showAppearanceDialog() async {
    var selectedPreference = await SettingsService(widget.database)
        .themePreference;
    if (!mounted) return;
    var saving = false;
    String? saveError;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          scrollable: true,
          icon: const Icon(Icons.dark_mode_outlined),
          title: const Text('Appearance'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose how TindaSari PH looks.'),
                const SizedBox(height: 12),
                if (saveError != null)
                  Text(
                    saveError!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                if (saving) const LinearProgressIndicator(),
                RadioGroup<AppThemePreference>(
                  groupValue: selectedPreference,
                  onChanged: (value) async {
                    if (value == null ||
                        saving ||
                        value == selectedPreference) {
                      return;
                    }
                    setDialogState(() {
                      saving = true;
                      saveError = null;
                    });
                    try {
                      await widget.onThemePreferenceChanged(value);
                      if (dialogContext.mounted) {
                        setDialogState(() => selectedPreference = value);
                      }
                    } catch (_) {
                      if (dialogContext.mounted) {
                        setDialogState(
                          () => saveError =
                              'Could not save appearance. Please try again.',
                        );
                      }
                    } finally {
                      if (dialogContext.mounted) {
                        setDialogState(() => saving = false);
                      }
                    }
                  },
                  child: Column(
                    children: [
                      for (final option in AppThemePreference.values)
                        RadioListTile<AppThemePreference>(
                          contentPadding: EdgeInsets.zero,
                          value: option,
                          title: Text(switch (option) {
                            AppThemePreference.system => 'System Default',
                            AppThemePreference.light => 'Light',
                            AppThemePreference.dark => 'Dark',
                          }),
                          subtitle: Text(switch (option) {
                            AppThemePreference.system =>
                              'Use your device setting',
                            AppThemePreference.light =>
                              'A clean and bright experience',
                            AppThemePreference.dark =>
                              'A focused, easy-on-the-eyes experience',
                          }),
                          secondary: Icon(switch (option) {
                            AppThemePreference.system =>
                              Icons.desktop_windows_outlined,
                            AppThemePreference.light =>
                              Icons.light_mode_outlined,
                            AppThemePreference.dark => Icons.dark_mode_outlined,
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    AppRefreshController.instance.addListener(_dataChanged);
    _refreshRestockCount();
  }

  void _dataChanged() {
    if (mounted) {
      setState(() {});
      _refreshRestockCount();
    }
  }

  Future<void> _refreshRestockCount() async {
    try {
      final count = (await OperationsRepository(
        widget.database,
      ).restock()).length;
      final activeCount =
          Sqflite.firstIntValue(
            await widget.database.rawQuery(
              'SELECT COUNT(*) FROM products WHERE is_archived=0',
            ),
          ) ??
          0;
      if (mounted) {
        setState(() {
          restockCount = count;
          productCount = activeCount;
        });
      }
    } catch (_) {
      // Keep navigation usable if the indicator query cannot be loaded.
    }
  }

  @override
  void dispose() {
    AppRefreshController.instance.removeListener(_dataChanged);
    super.dispose();
  }

  void _select(int destination) {
    setState(() {
      pendingConsignorId = null;
      pendingConsignmentProductId = null;
      selected = destination;
      if (destination == 13) dashboardRevision++;
      if (destination != 7) dashboardAddExpense = false;
      if (destination == 0) salesRevision++;
    });
  }

  Future<void> _handleDeviceBack() async {
    if (_handlingBack) return;
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusScope.of(context).unfocus();
      return;
    }
    _handlingBack = true;
    try {
      if (await _backController.handleBack() || !mounted) return;
      if (selected != 0) {
        _select(0);
      } else {
        await SystemNavigator.pop();
      }
    } finally {
      _handlingBack = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final bodyDestinations = [
      const NavigationDestination(
        icon: Icon(Icons.point_of_sale),
        label: 'Sales',
      ),
      const NavigationDestination(
        icon: Icon(Icons.sell_outlined),
        label: 'Brands',
      ),
      const NavigationDestination(
        icon: Icon(Icons.handshake_outlined),
        label: 'Consignment',
      ),
      const NavigationDestination(
        icon: Icon(Icons.inventory_2_outlined),
        label: 'Inventory',
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: restockCount > 0,
          label: Text('$restockCount'),
          child: const Icon(Icons.add_shopping_cart),
        ),
        label: 'Restock',
      ),
      NavigationDestination(
        icon: Badge(
          label: Text('$productCount'),
          child: const Icon(Icons.inventory),
        ),
        label: 'Products',
      ),
      const NavigationDestination(
        icon: Icon(Icons.people_alt_outlined),
        label: 'UTANG',
      ),
      const NavigationDestination(
        icon: Icon(Icons.receipt_long),
        label: 'Expenses',
      ),
      const NavigationDestination(
        icon: Icon(Icons.today),
        label: 'Daily Closing',
      ),
      const NavigationDestination(
        icon: Icon(Icons.assessment_outlined),
        label: 'Reports',
      ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        label: 'Settings',
      ),
      const NavigationDestination(
        icon: Icon(Icons.history),
        label: 'Transaction History',
      ),
      const NavigationDestination(icon: GCashIcon(), label: 'GCash'),
    ];
    bodyDestinations.add(
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        label: 'Dashboard',
      ),
    );
    const navTargets = [13, 0, 6, 12, 5, 3, 4, 1, 2, 11, 7, 8, 9, 10];
    final allowedTargets = widget.role == UserRole.owner
        ? navTargets
        : navTargets
              .where((target) => const {0, 3, 4, 6, 7, 11, 12}.contains(target))
              .toList();
    final destinations = [
      for (final target in allowedTargets) bodyDestinations[target],
    ];
    final body = _body();
    final scaffold = Scaffold(
      body: Row(
        children: [
          if (wide)
            StatefulBuilder(
              builder: (_, updateSidebar) =>
                  _sidebar(destinations, allowedTargets, updateSidebar),
            ),
          if (wide) const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: const [0, 6, 3].contains(selected)
                  ? const [0, 6, 3].indexOf(selected)
                  : 3,
              onDestinationSelected: (i) => _select(i == 3 ? 10 : [0, 6, 3][i]),
              destinations: [
                bodyDestinations[0],
                bodyDestinations[6],
                bodyDestinations[3],
                bodyDestinations[10],
              ],
            ),
    );
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleDeviceBack();
      },
      child: SectionBackScope(controller: _backController, child: scaffold),
    );
  }

  int dashboardRevision = 0;

  Widget _body() => switch (selected) {
    13 =>
      widget.role == UserRole.owner
          ? DashboardScreen(
              refreshRevision: dashboardRevision,
              database: widget.database,
              navigate: (target) {
                dashboardAddExpense = target == 7;
                _select(target);
              },
            )
          : _denied(),
    0 => FutureBuilder<List<Object>>(
      future: Future.wait<Object>([
        SqliteProductRepository(widget.database).searchActive(),
        SqliteCategoryRepository(widget.database).getActive(),
        ReportsRepository(widget.database).frequentProductIds(),
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
          frequentProductIds: s.data![2] as List<int>,
          selectaProductIds: {
            for (final p in s.data![3] as List<Product>) p.id,
          },
          loadProducts: SqliteProductRepository(widget.database).searchActive,
          repository: CashSaleRepository(widget.database, actorRole: role),
          reversals: widget.role == UserRole.owner
              ? ReversalRepository(widget.database)
              : null,
          drafts: SaleDraftRepository(widget.database),
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
    1 =>
      widget.role == UserRole.owner
          ? ManagedBrandsScreen(
              special: SpecialInventoryRepository(
                widget.database,
                actorRole: role,
              ),
              products: SqliteProductRepository(widget.database),
              inventory: InventoryRepository(widget.database, actorRole: role),
              categories: SqliteCategoryRepository(widget.database),
              photoService: LocalProductPhotoService(),
            )
          : _denied(),
    2 =>
      widget.role == UserRole.owner
          ? ConsignmentScreen(
              repository: ConsignmentRepository(
                widget.database,
                actorRole: role,
              ),
              products: SqliteProductRepository(widget.database),
              categories: SqliteCategoryRepository(widget.database),
              photoService: LocalProductPhotoService(),
              initialConsignorId: pendingConsignorId,
              initialReceiveProductId: pendingConsignmentProductId,
            )
          : _denied(),
    3 => InventoryScreen(
      repository: InventoryRepository(widget.database, actorRole: role),
    ),
    4 => RestockScreen(
      operations: OperationsRepository(widget.database),
      inventory: InventoryRepository(widget.database, actorRole: role),
      openConsignment: (consignorId, productId) => setState(() {
        pendingConsignorId = consignorId;
        pendingConsignmentProductId = productId;
        selected = 2;
      }),
    ),
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
    7 => ExpensesScreen(
      openAdd: dashboardAddExpense,
      repository: ExpenseRepository(widget.database, actorRole: role),
      auth: AuthService(widget.database),
    ),
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
    11 => TransactionHistoryScreen(
      repository: TransactionHistoryRepository(widget.database),
    ),
    12 => GCashScreen(
      repository: PaymentAccountingRepository(widget.database, actorRole: role),
      services: GCashServiceRepository(widget.database, actorRole: role),
      auth: AuthService(widget.database),
    ),
    _ => _more(),
  };

  Widget _sidebar(
    List<NavigationDestination> destinations,
    List<int> navTargets,
    StateSetter updateSidebar,
  ) {
    final colors = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    Widget toggle() => IconButton.filledTonal(
      tooltip: railExpanded ? 'Collapse navigation' : 'Expand navigation',
      style: IconButton.styleFrom(backgroundColor: colors.primaryContainer),
      onPressed: () => updateSidebar(() => railExpanded = !railExpanded),
      icon: AnimatedRotation(
        turns: railExpanded ? 0 : .5,
        duration: const Duration(milliseconds: 250),
        child: Icon(Icons.keyboard_double_arrow_left, color: colors.primary),
      ),
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      width: railExpanded ? 292 : 88,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: semantic.sidebar,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .08),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Use the animated width, not the destination width, to prevent overflow.
            final expanded = constraints.maxWidth >= 260;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                  child: Row(
                    children: [
                      if (expanded) ...[
                        const Expanded(
                          child: BrandLogo(horizontal: true, size: 56),
                        ),
                        toggle(),
                      ] else
                        const BrandLogo(size: 48),
                    ],
                  ),
                ),
                if (!expanded) toggle(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 20),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: destinations.length,
                    itemBuilder: (_, i) {
                      final destination = destinations[i];
                      final target = navTargets[i];
                      final active = selected == target;
                      final sectionStart =
                          i == 0 ||
                          _navSection(navTargets[i - 1]) != _navSection(target);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (sectionStart) ...[
                            if (i > 0) const Divider(height: 26),
                            if (expanded)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 3, 0, 9),
                                child: Text(
                                  _navSection(target).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    letterSpacing: 1,
                                    fontWeight: FontWeight.w700,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Tooltip(
                              message: expanded ? '' : destination.label,
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: TextStyle(
                                color: colors.onSurface,
                                fontSize: 14,
                              ),
                              child: Material(
                                color: active
                                    ? colors.primaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => _select(target),
                                  child: SizedBox(
                                    height: 52,
                                    child: Row(
                                      mainAxisAlignment: expanded
                                          ? MainAxisAlignment.start
                                          : MainAxisAlignment.center,
                                      children: [
                                        if (expanded) const SizedBox(width: 14),
                                        IconTheme(
                                          data: IconThemeData(
                                            size: 27,
                                            color: active
                                                ? colors.primary
                                                : colors.onSurface,
                                          ),
                                          child: destination.icon,
                                        ),
                                        if (expanded) ...[
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              destination.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: active
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                                color: colors.onSurface,
                                              ),
                                            ),
                                          ),
                                          if (active)
                                            Icon(
                                              Icons.chevron_right,
                                              size: 21,
                                              color: colors.primary,
                                            ),
                                          const SizedBox(width: 12),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Material(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: widget.lock,
                      child: Tooltip(
                        message: expanded ? '' : 'Lock App',
                        child: SizedBox(
                          height: 66,
                          child: Row(
                            mainAxisAlignment: expanded
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            children: [
                              if (expanded) const SizedBox(width: 16),
                              Icon(
                                Icons.lock_outline,
                                size: 29,
                                color: colors.onSurface,
                              ),
                              if (expanded) ...[
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Lock App',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: colors.onSurface,
                                        ),
                                      ),
                                      Text(
                                        'Keep your store secure',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: colors.onSurface,
                                ),
                                const SizedBox(width: 12),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _navSection(int target) => switch (target) {
    13 || 0 || 6 || 12 => 'Daily Selling',
    5 || 3 || 4 => 'Stock & Products',
    1 || 2 => 'Supplier Products',
    11 || 7 || 8 || 9 => 'Store Records',
    _ => 'Administration',
  };

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
            label: 'About TindaSari PH',
            icon: Icons.info_outline,
            page: null,
            action: () => showAboutDialog(
              context: context,
              applicationName: 'TindaSari PH',
              applicationIcon: const BrandLogo(size: 64),
              children: [const Text('Simple to run. Built for your store.')],
            ),
          ),
          (
            label: 'Help & Guide',
            icon: Icons.help_outline,
            page: const HelpGuideScreen(),
            action: null,
          ),
          if (owner)
            (
              label: 'Appearance',
              icon: Icons.dark_mode_outlined,
              page: null,
              action: _showAppearanceDialog,
            ),
          if (owner)
            (
              label: 'Brands',
              icon: Icons.sell_outlined,
              page: ManagedBrandsScreen(
                special: SpecialInventoryRepository(
                  widget.database,
                  actorRole: role,
                ),
                products: SqliteProductRepository(widget.database),
                inventory: InventoryRepository(
                  widget.database,
                  actorRole: role,
                ),
                categories: SqliteCategoryRepository(widget.database),
                photoService: LocalProductPhotoService(),
              ),
              action: null,
            ),
          if (owner)
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
                initialConsignorId: pendingConsignorId,
                initialReceiveProductId: pendingConsignmentProductId,
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
                openConsignment: (consignorId, productId) {
                  Navigator.pop(context);
                  setState(() {
                    pendingConsignorId = consignorId;
                    pendingConsignmentProductId = productId;
                    selected = 2;
                  });
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
              label: 'Staff Activity Summary',
              icon: Icons.groups_2_outlined,
              page: StaffActivityScreen(
                repository: StaffActivityRepository(widget.database),
              ),
              action: null,
            ),
          if (owner)
            (
              label: 'Backup & Restore',
              icon: Icons.backup,
              page: BackupScreen(
                service: BackupService(widget.appDatabase),
                onRestored: widget.onDatabaseRestored,
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
            'Brands',
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
            'Staff Activity Summary',
          }.contains(x.label),
        )
        .toList();
    final security = items
        .where((x) => const {'Security', 'Lock App'}.contains(x.label))
        .toList();
    final appearance = items.where((x) => x.label == 'Appearance').toList();
    final help = items.where((x) => x.label == 'Help & Guide').toList();
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
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          if (owner) SizedBox(height: 96, child: _ownerAlerts()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
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
                if (owner)
                  section(
                    'APPEARANCE',
                    'Choose the light, dark, or device theme',
                    appearance,
                  ),
                section('HELP', 'Simple guides for using TindaSari PH', help),
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
      BackupService(widget.appDatabase).health(),
    ]),
    builder: (_, snapshot) {
      if (!snapshot.hasData) return const SizedBox(height: 8);
      final s = snapshot.data![0] as DashboardSummary,
          backup = snapshot.data![1] as BackupHealth;
      final old = backup.status != 'Recent';
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Row(
          children: [
            ActionChip(
              label: Text('Low Stock (${s.lowStock})'),
              onPressed: () => setState(() => selected = 3),
            ),
            const SizedBox(width: 8),
            ActionChip(
              label: Text('Out of Stock (${s.outOfStock})'),
              onPressed: () => setState(() => selected = 3),
            ),
            const SizedBox(width: 8),
            ActionChip(
              label: Text(
                'Outstanding UTANG ${standardMoney(s.outstandingCentavos)}',
              ),
              onPressed: () => setState(() => selected = 6),
            ),
            const SizedBox(width: 8),
            ActionChip(
              label: Text(
                'Supplier Payable ${standardMoney(s.supplierPayableCentavos)}',
              ),
              onPressed: () => setState(() => selected = 2),
            ),
            if (old) ...[
              const SizedBox(width: 8),
              Chip(
                avatar: Icon(Icons.backup_outlined),
                label: Text(
                  backup.status == 'Backup Overdue'
                      ? 'Backup Overdue'
                      : 'Backup Recommended',
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}
