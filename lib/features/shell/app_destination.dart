/// Sections handled by the app shell. The phone More hub is a section too,
/// but it does not appear in the tablet sidebar.
enum AppDestination {
  more,
  dashboard,
  sales,
  utang,
  gcashServices,
  mayaServices,
  products,
  inventory,
  categories,
  restock,
  managedBrands,
  consignment,
  supplierContacts,
  transactionHistory,
  expenses,
  dailyClosing,
  reports,
  activityLogs,
  staffActivity,
  loanManagement,
  tindahanProfile,
  settings,
  helpGuide;

  /// Only these sections are available to staff. New sections stay owner only
  /// until deliberately added here.
  bool get staffAllowed => const {
    AppDestination.sales,
    AppDestination.utang,
    AppDestination.gcashServices,
    AppDestination.mayaServices,
    AppDestination.inventory,
    AppDestination.restock,
    AppDestination.transactionHistory,
    AppDestination.expenses,
    AppDestination.settings,
    AppDestination.helpGuide,
  }.contains(this);

  bool get proLocked => const {
    AppDestination.managedBrands,
    AppDestination.consignment,
    AppDestination.gcashServices,
    AppDestination.mayaServices,
    AppDestination.loanManagement,
  }.contains(this);

  String get section => switch (this) {
    dashboard ||
    sales ||
    utang ||
    gcashServices ||
    mayaServices => 'Daily Selling',
    products || inventory || categories || restock => 'Stock & Products',
    managedBrands || consignment || supplierContacts => 'Supplier Products',
    transactionHistory ||
    expenses ||
    dailyClosing ||
    reports ||
    activityLogs ||
    staffActivity ||
    loanManagement => 'Store Records',
    _ => 'Administration',
  };
}
