import '../../../widgets/brand_logo.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../../widgets/app_back_navigation.dart';

import '../../../widgets/wallet_nav_logo.dart';

import 'package:sqflite/sqflite.dart';

import '../../../repositories/activity_log_repository.dart';
import '../../../repositories/staff_activity_repository.dart';
import '../../../repositories/cash_sale_repository.dart';
import '../../../repositories/category_repository.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/inventory_repository.dart';
import '../../../repositories/expense_repository.dart';
import '../../../repositories/payment_repository.dart';
import '../../../repositories/payment_accounting_repository.dart';
import '../../../repositories/gcash_service_repository.dart';
import '../../../models/payment_method.dart';
import '../../../repositories/product_repository.dart';
import '../../../repositories/reports_repository.dart';
import '../../../repositories/operations_repository.dart';
import '../../../repositories/reversal_repository.dart';
import '../../../repositories/utang_repository.dart';
import '../../../repositories/consignment_repository.dart';
import '../../../repositories/special_inventory_repository.dart';
import '../../../repositories/brand_analytics_repository.dart';
import '../../../repositories/supplier_contacts_repository.dart';
import '../../../repositories/loan_repository.dart';
import '../../../repositories/sale_draft_repository.dart';
import '../../../repositories/transaction_history_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/backup_service.dart';
import '../../../services/product_photo_service.dart';
import '../../../services/data_integrity_service.dart';
import '../../../services/storage_management_service.dart';
import '../../../services/app_refresh_controller.dart';
import '../../../services/settings_service.dart';
import '../../../services/feature_access_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../activity_logs/presentation/activity_logs_screen.dart';
import '../../activity_logs/presentation/staff_activity_screen.dart';
import '../../backup/presentation/backup_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../store_profile/presentation/tindahan_profile_screen.dart';
import '../../cash_sales/presentation/cash_sale_screen.dart';
import '../../cash_sales/presentation/cash_services_shortcut.dart';
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
import '../../suppliers/presentation/supplier_contacts_screen.dart';
import '../../loans/presentation/loan_management_screen.dart';
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
  bool _phoneLandingSet = false;
  bool _staffHomeSelected = false;
  bool _phoneOpenedFromMore = false;
  final ValueNotifier<bool> _phoneSaleDetailVisible = ValueNotifier(false);
  bool dashboardAddExpense = false;
  int salesRevision = 0;
  Future<List<Object>>? _salesFuture;
  int restockCount = 0;
  int productCount = 0;
  int? pendingConsignorId;
  int? pendingConsignmentProductId;
  bool railExpanded = true;
  bool _savingDevelopmentPlan = false;
  String? _developmentPlanError;
  Future<AppPlan>? _developmentPlanLoad;
  String get role => widget.role == UserRole.owner ? 'OWNER' : 'STAFF';
  bool get _walletServicesAllowed =>
      FeatureAccessService(widget.database)
          .allowsCurrent(ProFeature.gcashServices);

  Widget _developerPlanSection() {
    final controller = AppPlanController.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => FutureBuilder<AppPlan>(
              future: _developmentPlanLoad ??= controller.load(),
              builder: (context, snapshot) {
                final plan = controller.plan;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'DEVELOPER TOOLS',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (snapshot.hasData)
                          Chip(label: Text('DEV • ${plan.name.toUpperCase()}')),
                      ],
                    ),
                    const Text('Development builds only'),
                    const SizedBox(height: 16),
                    Text(
                      'Test Plan',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const LinearProgressIndicator(),
                    if (snapshot.hasData)
                      SegmentedButton<AppPlan>(
                        segments: const [
                          ButtonSegment(
                            value: AppPlan.free,
                            label: Text('FREE'),
                          ),
                          ButtonSegment(value: AppPlan.pro, label: Text('PRO')),
                        ],
                        selected: {plan},
                        onSelectionChanged: _savingDevelopmentPlan
                            ? null
                            : (selection) async {
                                setState(() {
                                  _savingDevelopmentPlan = true;
                                  _developmentPlanError = null;
                                });
                                try {
                                  await controller.setDevelopmentPlan(
                                    selection.single,
                                  );
                                } catch (_) {
                                  if (mounted) {
                                    setState(
                                      () => _developmentPlanError = 'Could not save the test plan. Please try again.',
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(
                                      () => _savingDevelopmentPlan = false,
                                    );
                                  }
                                }
                              },
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use this setting to test Free and Pro experiences during development. Store records are not changed.',
                    ),
                    if (snapshot.hasError || _developmentPlanError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _developmentPlanError ??
                            'Could not load the test plan.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      if (snapshot.hasError)
                        TextButton(
                          onPressed: () => setState(
                            () => _developmentPlanLoad = controller.load(),
                          ),
                          child: const Text('Retry'),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

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
    AppPlanController.instance.addListener(_planChanged);
    AppPlanController.instance.load();
    _refreshRestockCount();
  }

  void _planChanged() {
    if (mounted) setState(() {});
  }

  void _dataChanged() {
    if (mounted) {
      setState(() {});
      _refreshRestockCount();
    }
  }

  Future<void> _refreshRestockCount() async {
    int? activeCount;
    int? count;
    try {
      activeCount =
          Sqflite.firstIntValue(
            await widget.database.rawQuery(
              'SELECT COUNT(*) FROM products WHERE is_archived=0',
            ),
          ) ??
          0;
    } catch (_) {
      // Keep the previous count if products cannot be queried.
    }
    try {
      count = (await OperationsRepository(widget.database).restock()).length;
    } catch (_) {
      // Restock may fail independently of the active-product count.
    }
    if (mounted && (activeCount != null || count != null)) {
      setState(() {
        if (activeCount != null) productCount = activeCount;
        if (count != null) restockCount = count;
      });
    }
  }

  @override
  void dispose() {
    AppRefreshController.instance.removeListener(_dataChanged);
    AppPlanController.instance.removeListener(_planChanged);
    _phoneSaleDetailVisible.dispose();
    super.dispose();
  }

  void _select(int destination) {
    setState(() {
      if (selected == -1 && destination != -1) {
        _phoneOpenedFromMore = true;
      } else if (destination == -1 || const {0, 6, 13}.contains(destination)) {
        _phoneOpenedFromMore = false;
      }
      _staffHomeSelected = false;
      _phoneSaleDetailVisible.value = false;
      pendingConsignorId = null;
      pendingConsignmentProductId = null;
      selected = destination;
      if (destination == 13) dashboardRevision++;
      if (destination != 7) dashboardAddExpense = false;
      if (destination == 0) {
        salesRevision++;
        _salesFuture = null;
      }
    });
  }

  Future<List<Object>> _loadSalesData() =>
      _salesFuture ??= Future.wait<Object>([
        SqliteProductRepository(widget.database).searchActive(),
        SqliteCategoryRepository(widget.database).getActive(),
        ReportsRepository(widget.database).frequentProductIds(),
        SpecialInventoryRepository(widget.database).products('SELECTA'),
      ]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_phoneLandingSet) {
      _phoneLandingSet = true;
      if (MediaQuery.sizeOf(context).width < 900 &&
          widget.role == UserRole.owner) {
        selected = 13;
      }
    }
  }

  void _selectPhoneTab(int index) {
    if (widget.role != UserRole.owner &&
        selected == 0 &&
        (index == 0 || index == 1)) {
      setState(() => _staffHomeSelected = index == 0);
      return;
    }
    if ((index == 0 && selected == 13) ||
        (index == 1 && selected == 0 && !_staffHomeSelected) ||
        (index == 2 && selected == 6) ||
        (index == 3 && selected == -1)) {
      return;
    }
    if (index == 0 && widget.role != UserRole.owner) {
      if (selected == 0) {
        setState(() => _staffHomeSelected = true);
      } else {
        _select(0);
        _staffHomeSelected = true;
      }
      return;
    }
    _select(switch (index) {
      0 => 13,
      1 => 0,
      2 => 6,
      _ => -1,
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
      if (_phoneOpenedFromMore &&
          MediaQuery.sizeOf(context).width < 900 &&
          selected != -1) {
        _select(-1);
        return;
      }
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
      const NavigationDestination(
        icon: Icon(Icons.inventory),
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
      const NavigationDestination(
        icon: WalletNavLogo(maya: false),
        label: 'GCash Services',
      ),
    ];
    bodyDestinations.add(
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        label: 'Dashboard',
      ),
    );
    bodyDestinations.addAll(const [
      NavigationDestination(
        icon: Icon(Icons.contact_phone_outlined),
        label: 'Supplier Contacts',
      ),
      NavigationDestination(
        icon: Icon(Icons.account_balance_outlined),
        label: '5/6 Loan Management',
      ),
    ]);
    bodyDestinations.add(
      const NavigationDestination(
        icon: WalletNavLogo(maya: true),
        label: 'Maya Services',
      ),
    );
    bodyDestinations.addAll(const [
      NavigationDestination(
        icon: Icon(Icons.category_outlined),
        label: 'Categories',
      ),
      NavigationDestination(
        icon: Icon(Icons.history_toggle_off_outlined),
        label: 'Activity Logs',
      ),
      NavigationDestination(
        icon: Icon(Icons.groups_2_outlined),
        label: 'Staff Activity Summary',
      ),
      NavigationDestination(
        icon: Icon(Icons.help_outline),
        label: 'Help & Guide',
      ),
    ]);
    const navTargets = [
      13,
      0,
      6,
      12,
      16,
      5,
      3,
      17,
      4,
      1,
      2,
      14,
      11,
      7,
      8,
      9,
      18,
      19,
      15,
      10,
      20,
    ];
    final allowedTargets = widget.role == UserRole.owner
        ? navTargets
        : navTargets
              .where(
                (target) =>
                    const {0, 3, 4, 6, 7, 10, 11, 12, 16, 20}.contains(target),
              )
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
          Expanded(
            child: wide
                ? body
                : Column(
                    children: [
                      if (selected == 0)
                        ValueListenableBuilder<bool>(
                          valueListenable: _phoneSaleDetailVisible,
                          builder: (_, hidden, _) => hidden
                              ? const SizedBox.shrink()
                              : _phoneSalesHeader(),
                        ),
                      Expanded(child: body),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : ValueListenableBuilder<bool>(
              valueListenable: _phoneSaleDetailVisible,
              builder: (_, hidden, _) => hidden
                  ? const SizedBox.shrink()
                  : NavigationBar(
                      selectedIndex: _staffHomeSelected
                          ? 0
                          : selected == 13
                          ? 0
                          : selected == 0
                          ? 1
                          : selected == 6
                          ? 2
                          : 3,
                      onDestinationSelected: _selectPhoneTab,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: 'Home',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.point_of_sale_outlined),
                          selectedIcon: Icon(Icons.point_of_sale),
                          label: 'Sales',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.people_alt_outlined),
                          selectedIcon: Icon(Icons.people_alt),
                          label: 'UTANG',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.more_horiz),
                          label: 'More',
                        ),
                      ],
                    ),
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

  Widget _managedBrands() => ManagedBrandsScreen(
    special: SpecialInventoryRepository(widget.database, actorRole: role),
    products: SqliteProductRepository(widget.database),
    inventory: InventoryRepository(widget.database, actorRole: role),
    categories: SqliteCategoryRepository(widget.database),
    photoService: LocalProductPhotoService(),
    analytics: BrandAnalyticsRepository(widget.database),
    access: FeatureAccessService(widget.database),
  );

  Widget _walletScreen(PaymentMethod provider, {String? initialServiceType}) =>
      GCashScreen(
        key: ValueKey('${provider.dbValue}-wallet-screen'),
        repository: PaymentAccountingRepository(
          widget.database,
          actorRole: role,
          provider: provider,
        ),
        services: GCashServiceRepository(
          widget.database,
          actorRole: role,
          provider: provider,
        ),
        auth: AuthService(widget.database),
        access: FeatureAccessService(widget.database),
        initialServiceType: initialServiceType,
      );

  Widget _body() => switch (selected) {
    -1 => _phoneMoreHub(),
    13 =>
      widget.role == UserRole.owner
          ? DashboardScreen(
              refreshRevision: dashboardRevision,
              database: widget.database,
              walletServicesAllowed: _walletServicesAllowed,
              navigate: (target) {
                dashboardAddExpense = target == 7;
                _select(target);
              },
            )
          : _denied(),
    0 => FutureBuilder<List<Object>>(
      future: _loadSalesData(),
      builder: (_, s) {
        if (s.hasError) {
          return AppStateView.error(
            title: 'Could not load Sales',
            message: 'Please check the store data and try again.',
            actionLabel: 'Try Again',
            onAction: () => setState(() => _salesFuture = null),
          );
        }
        if (!s.hasData) return const AppLoadingView(label: 'Loading Sales…');
        return CashSaleScreen(
          key: ValueKey('sales-$salesRevision'),
          embedded: true,
          onPhoneDetailVisibilityChanged: (visible) =>
              _phoneSaleDetailVisible.value = visible,
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
          cashServicesLauncher: CashServicesShortcut(
            access: FeatureAccessService(widget.database),
            gcash: PaymentAccountingRepository(
              widget.database,
              actorRole: role,
            ),
            maya: PaymentAccountingRepository(
              widget.database,
              actorRole: role,
              provider: PaymentMethod.maya,
            ),
            onService: (provider, serviceType) => Navigator.of(context)
                .push<bool>(
                  MaterialPageRoute(
                    builder: (_) => _walletScreen(
                      provider,
                      initialServiceType: serviceType,
                    ),
                  ),
                ),
            onHistory: (provider) async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => _walletScreen(provider)),
              );
            },
          ),
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
    1 => widget.role == UserRole.owner ? _managedBrands() : _denied(),
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
      access: FeatureAccessService(widget.database),
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
              access: FeatureAccessService(widget.database),
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
              walletServicesAllowed: _walletServicesAllowed,
            )
          : _denied(),
    9 =>
      widget.role == UserRole.owner
          ? ReportsScreen(
              repository: ReportsRepository(widget.database),
              walletServicesAllowed: _walletServicesAllowed,
            )
          : _denied(),
    14 =>
      widget.role == UserRole.owner
          ? SupplierContactsScreen(
              repository: SupplierContactsRepository(widget.database),
            )
          : _denied(),
    15 =>
      widget.role == UserRole.owner
          ? LoanManagementScreen(
              repository: LoanRepository(widget.database, actorRole: role),
              access: FeatureAccessService(widget.database),
            )
          : _denied(),
    11 => TransactionHistoryScreen(
      repository: TransactionHistoryRepository(widget.database),
      access: FeatureAccessService(widget.database),
    ),
    12 => _walletScreen(PaymentMethod.gcash),
    16 => _walletScreen(PaymentMethod.maya),
    17 =>
      widget.role == UserRole.owner
          ? CategoriesScreen(
              repository: SqliteCategoryRepository(widget.database),
            )
          : _denied(),
    18 =>
      widget.role == UserRole.owner
          ? ActivityLogsScreen(
              repository: ActivityLogRepository(widget.database),
              walletServicesAllowed: _walletServicesAllowed,
            )
          : _denied(),
    19 =>
      widget.role == UserRole.owner
          ? StaffActivityScreen(
              repository: StaffActivityRepository(widget.database),
              walletServicesAllowed: _walletServicesAllowed,
            )
          : _denied(),
    20 => const HelpGuideScreen(),
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
                      final proLocked =
                          widget.role == UserRole.owner &&
                          AppPlanController.instance.plan == AppPlan.free &&
                          const {1, 2, 12, 15, 16}.contains(target);
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
                              message: expanded
                                  ? ''
                                  : '${destination.label}${target == 5 && productCount > 0 ? ' • $productCount total' : ''}${proLocked ? ' • PRO' : ''}',
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
                                          child: !expanded && target == 5
                                              ? Badge(
                                                  isLabelVisible:
                                                      productCount > 0,
                                                  label: Text('$productCount'),
                                                  backgroundColor: colors
                                                      .surfaceContainerHighest,
                                                  textColor:
                                                      colors.onSurfaceVariant,
                                                  child: destination.icon,
                                                )
                                              : !expanded && proLocked
                                              ? Badge(
                                                  label: const Text(
                                                    'PRO',
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                    ),
                                                  ),
                                                  backgroundColor: const Color(
                                                    0xFFFFD879,
                                                  ),
                                                  textColor: const Color(
                                                    0xFF312100,
                                                  ),
                                                  child: destination.icon,
                                                )
                                              : destination.icon,
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
                                          if (target == 5 && productCount > 0)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: colors
                                                    .surfaceContainerHighest,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                '$productCount',
                                                style: TextStyle(
                                                  color:
                                                      colors.onSurfaceVariant,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          if (proLocked)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFD879),
                                                borderRadius:
                                                    BorderRadius.circular(7),
                                              ),
                                              child: const Text(
                                                'PRO',
                                                style: TextStyle(
                                                  color: Color(0xFF312100),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
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
    13 || 0 || 6 || 12 || 16 => 'Daily Selling',
    5 || 3 || 17 || 4 => 'Stock & Products',
    1 || 2 || 14 => 'Supplier Products',
    11 || 7 || 8 || 9 || 18 || 19 || 15 => 'Store Records',
    _ => 'Administration',
  };

  Widget _denied() => const AppStateView(
    icon: Icons.lock_outline,
    title: 'Owner permission required',
    message:
        'Lock the app and sign in with the owner PIN to open this section.',
  );

  Widget _phoneSalesHeader() => SafeArea(
    bottom: false,
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 58,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Open More',
                  onPressed: () => _select(-1),
                  icon: const Icon(Icons.menu),
                ),
                const Expanded(child: BrandLogo(horizontal: true, size: 34)),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Tooltip(
                    message: widget.role == UserRole.owner ? 'Owner' : 'Staff',
                    child: CircleAvatar(
                      radius: 17,
                      child: Icon(
                        Icons.person_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    ),
  );

  Widget _phoneMoreHub() {
    final owner = widget.role == UserRole.owner;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Future<void> openPage(Widget page) async {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
      if (mounted) setState(() {});
    }

    Widget group(
      String title,
      List<(String, IconData, VoidCallback, int?)> entries,
    ) {
      if (entries.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
                letterSpacing: .4,
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: colors.surface,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      leading: Icon(
                        entries[i].$2,
                        color: colors.primary,
                        size: 23,
                      ),
                      title: entries[i].$4 == 5
                          ? Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: entries[i].$1),
                                  TextSpan(
                                    text: '  ($productCount)',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Text(entries[i].$1),
                      trailing:
                          owner &&
                              AppPlanController.instance.plan == AppPlan.free &&
                              const {1, 2, 12, 15, 16}.contains(entries[i].$4)
                          ? const Chip(label: Text('PRO'))
                          : const Icon(Icons.chevron_right),
                      onTap: entries[i].$3,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Stack(
        children: [
          ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
                child: Text(
                  'More',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (owner)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR TINDAHAN',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colors.primary,
                          letterSpacing: .4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: colors.primaryContainer.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          key: const ValueKey('more-tindahan-profile'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 3,
                          ),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.storefront_outlined,
                              color: colors.onPrimary,
                            ),
                          ),
                          title: const Text('Tindahan Profile'),
                          subtitle: const Text(
                            'View and edit your store details',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => openPage(
                            TindahanProfileScreen(
                              settings: SettingsService(widget.database),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              group('STORE MANAGEMENT', [
                if (owner)
                  ('Products', Icons.inventory_2_outlined, () => _select(5), 5),
                ('Inventory', Icons.inventory_outlined, () => _select(3), 3),
                ('Restock', Icons.add_shopping_cart, () => _select(4), 4),
                if (owner)
                  (
                    'Categories',
                    Icons.category_outlined,
                    () => openPage(
                      CategoriesScreen(
                        repository: SqliteCategoryRepository(widget.database),
                      ),
                    ),
                    null,
                  ),
                if (owner)
                  (
                    'Supplier Contacts',
                    Icons.contact_phone_outlined,
                    () => _select(14),
                    14,
                  ),
              ]),
              group('MONEY', [
                ('Expenses', Icons.receipt_long_outlined, () => _select(7), 7),
                (
                  'GCash',
                  Icons.account_balance_wallet_outlined,
                  () => _select(12),
                  12,
                ),
                (
                  'Maya',
                  Icons.account_balance_wallet_outlined,
                  () => _select(16),
                  16,
                ),
                if (owner)
                  (
                    '5/6 Loan Management',
                    Icons.account_balance_outlined,
                    () => _select(15),
                    15,
                  ),
              ]),
              group('RECORDS & INSIGHTS', [
                ('Transaction History', Icons.history, () => _select(11), 11),
                if (owner)
                  ('Daily Closing', Icons.today_outlined, () => _select(8), 8),
                if (owner)
                  ('Reports', Icons.assessment_outlined, () => _select(9), 9),
                if (owner)
                  (
                    'Activity Logs',
                    Icons.history_toggle_off_outlined,
                    () => openPage(
                      ActivityLogsScreen(
                        repository: ActivityLogRepository(widget.database),
                        walletServicesAllowed: _walletServicesAllowed,
                      ),
                    ),
                    null,
                  ),
                if (owner)
                  (
                    'Staff Activity Summary',
                    Icons.groups_2_outlined,
                    () => openPage(
                      StaffActivityScreen(
                        repository: StaffActivityRepository(widget.database),
                        walletServicesAllowed: _walletServicesAllowed,
                      ),
                    ),
                    null,
                  ),
              ]),
              group('ADVANCED MANAGEMENT', [
                if (owner)
                  ('Managed Brands', Icons.sell_outlined, () => _select(1), 1),
                if (owner)
                  (
                    'Consignment',
                    Icons.handshake_outlined,
                    () => _select(2),
                    2,
                  ),
              ]),
              group('SYSTEM', [
                ('Settings', Icons.settings_outlined, () => _select(10), 10),
                (
                  'Help & Guide',
                  Icons.help_outline,
                  () => openPage(const HelpGuideScreen()),
                  null,
                ),
              ]),
              const SizedBox(height: 96),
            ],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              key: const ValueKey('more-lock-app'),
              heroTag: 'more-lock-app',
              onPressed: widget.lock,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Lock App'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _more() {
    final owner = widget.role == UserRole.owner;
    final items =
        <({String label, IconData icon, Widget? page, VoidCallback? action})>[
          if (owner)
            (
              label: 'Appearance',
              icon: Icons.dark_mode_outlined,
              page: null,
              action: _showAppearanceDialog,
            ),
          if (owner)
            (
              label: 'Security & Staff',
              icon: Icons.security,
              page: SecurityScreen(auth: AuthService(widget.database)),
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
              label: 'Check Data Integrity',
              icon: Icons.fact_check_outlined,
              page: IntegrityScreen(
                service: DataIntegrityService(widget.database),
              ),
              action: null,
            ),
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
        ).then((_) {
          if (mounted) setState(() {});
        });
      }
    }

    final appearance = items.where((x) => x.label == 'Appearance').toList();
    final security = items.where((x) => x.label == 'Security & Staff').toList();
    final maintenance = items
        .where(
          (x) => const {
            'Backup & Restore',
            'Storage Management',
            'Check Data Integrity',
          }.contains(x.label),
        )
        .toList();
    final about = items.where((x) => x.label == 'About TindaSari PH').toList();
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
        children: [
          section(
            'APP PREFERENCES',
            'Choose the light, dark, or device theme',
            appearance,
          ),
          section('SECURITY', 'Manage owner and staff access', security),
          section(
            'DATA & MAINTENANCE',
            'Protect and check your store records',
            maintenance,
          ),
          section('ABOUT', 'App information', about),
          if (showDeveloperPlanTools(debugBuild: kDebugMode, owner: owner))
            _developerPlanSection(),
        ],
      ),
    );
  }
}
