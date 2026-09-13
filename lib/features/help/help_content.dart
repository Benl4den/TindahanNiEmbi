import 'package:flutter/material.dart';

enum HelpTopicId {
  gettingStarted,
  dashboard,
  products,
  inventory,
  stockMovement,
  cashSale,
  utang,
  utangPayments,
  customers,
  gcash,
  cashIn,
  cashOut,
  expenses,
  selecta,
  consignment,
  reports,
  transactionHistory,
  dailyClosing,
  backupRestore,
  staffSecurity,
  lockApp,
  settings,
  appearance,
}

class HelpArticle {
  const HelpArticle({
    required this.id,
    required this.group,
    required this.title,
    required this.icon,
    required this.description,
    required this.steps,
    this.notes = const [],
    this.keywords = const [],
  });

  final HelpTopicId id;
  final String group;
  final String title;
  final IconData icon;
  final String description;
  final List<String> steps;
  final List<String> notes;
  final List<String> keywords;

  bool matches(String query) {
    final words =
        '$title $group $description ${steps.join(' ')} '
                '${notes.join(' ')} ${keywords.join(' ')}'
            .toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\\s+'))
        .where((word) => word.isNotEmpty)
        .every(words.contains);
  }
}

const helpGroups = [
  'Getting Started',
  'Sales & UTANG',
  'Inventory',
  'GCash & Money',
  'Reports & Closing',
  'Security & Backup',
];

const helpArticles = <HelpArticle>[
  HelpArticle(
    id: HelpTopicId.gettingStarted,
    group: 'Getting Started',
    title: 'Getting Started',
    icon: Icons.waving_hand_outlined,
    description: 'A quick way to begin using TindaSari PH for your store.',
    steps: [
      'Add your products and prices.',
      'Check stock in Inventory.',
      'Use Sales when a customer buys.',
      'Open Settings for reports, backup, and store tools.',
    ],
    keywords: ['start beginner first use'],
  ),
  HelpArticle(
    id: HelpTopicId.dashboard,
    group: 'Getting Started',
    title: 'Dashboard',
    icon: Icons.dashboard_outlined,
    description:
        'Use the dashboard to see important store information at a glance.',
    steps: [
      'Check sales and stock reminders.',
      'Open a card when you need more details.',
      'Use it as a quick starting point for your day.',
    ],
    keywords: ['overview home summary'],
  ),
  HelpArticle(
    id: HelpTopicId.cashSale,
    group: 'Sales & UTANG',
    title: 'Cash Sale',
    icon: Icons.point_of_sale_outlined,
    description: 'Use Cash Sale when the customer pays immediately.',
    steps: [
      'Select products.',
      'Choose the quantity or selling unit.',
      'Review the Current Sale.',
      'Choose Cash or GCash.',
      'Complete the sale.',
    ],
    notes: ['Review the payment method before completing the sale.'],
    keywords: ['sales sell cashier payment checkout'],
  ),
  HelpArticle(
    id: HelpTopicId.utang,
    group: 'Sales & UTANG',
    title: 'MGA UTANGAN',
    icon: Icons.people_alt_outlined,
    description:
        'Keep customer credit sales and remaining balances in one place.',
    steps: [
      'Choose an existing customer or add a new one.',
      'Create the UTANG sale.',
      'Review the customer balance in their account.',
    ],
    notes: ['Use clear customer names so the right account is easy to find.'],
    keywords: ['utang utangan credit debt customer account'],
  ),
  HelpArticle(
    id: HelpTopicId.utangPayments,
    group: 'Sales & UTANG',
    title: 'UTANG Payments',
    icon: Icons.payments_outlined,
    description: 'Record money paid by a customer toward their UTANG balance.',
    steps: [
      'Open the customer account.',
      'Choose Record Payment.',
      'Enter the amount and payment method.',
      'Save the payment.',
    ],
    notes: ['Confirm the amount with the customer before saving.'],
    keywords: ['utang payment pay balance collect'],
  ),
  HelpArticle(
    id: HelpTopicId.customers,
    group: 'Sales & UTANG',
    title: 'Customers',
    icon: Icons.person_outline,
    description: 'Manage customer accounts used for UTANG.',
    steps: [
      'Search for the customer first.',
      'Add a customer when needed.',
      'Open their account to view sales and payments.',
    ],
    keywords: ['customer name account'],
  ),
  HelpArticle(
    id: HelpTopicId.products,
    group: 'Inventory',
    title: 'Products',
    icon: Icons.inventory_2_outlined,
    description: 'Add, edit, archive, and review the products you sell.',
    steps: [
      'Search or filter the product list.',
      'Tap a product for its details.',
      'Use Edit to change current product information.',
      'Archive products you no longer sell.',
    ],
    notes: ['Low Stock Alert At is used only to show stock reminders.'],
    keywords: ['item price archive low stock alert'],
  ),
  HelpArticle(
    id: HelpTopicId.inventory,
    group: 'Inventory',
    title: 'Inventory',
    icon: Icons.inventory_outlined,
    description: 'Check what is available and the value of owned stock.',
    steps: [
      'Search for a product.',
      'Filter by In Stock, Low Stock, or Out of Stock.',
      'Use View Movement History to check a product’s stock activity.',
    ],
    notes: ['Consignment stock is separate from owned inventory value.'],
    keywords: ['stock quantity low out value profit'],
  ),
  HelpArticle(
    id: HelpTopicId.stockMovement,
    group: 'Inventory',
    title: 'Stock In & Adjustments',
    icon: Icons.swap_vert_outlined,
    description:
        'Use this guide to understand stock changes recorded by the app.',
    steps: [
      'Open Restock when products need replenishing.',
      'Use product movement history to review stock changes.',
      'Check the current quantity after a sale, restock, or correction.',
    ],
    notes: [
      'Use an adjustment only when the actual count differs from the saved count.',
    ],
    keywords: ['restock adjust movement stock in correction'],
  ),
  HelpArticle(
    id: HelpTopicId.selecta,
    group: 'Inventory',
    title: 'SELECTA',
    icon: Icons.sell_outlined,
    description: 'Manage products that belong to the SELECTA supplier group.',
    steps: [
      'Open Managed Brands.',
      'Choose SELECTA.',
      'Add or manage the connected products.',
    ],
    keywords: ['managed brand supplier'],
  ),
  HelpArticle(
    id: HelpTopicId.consignment,
    group: 'Inventory',
    title: 'Consignment',
    icon: Icons.handshake_outlined,
    description: 'Track products supplied by another company and the amount owed to them.',
    steps: [
      'Open the company.',
      'Receive the delivered products.',
      'Sell products normally.',
      'Review remittance when it is time to pay the supplier.',
    ],
    notes: ['Consignment stock is not included in owned inventory cost.'],
    keywords: ['supplier company receive remittance payable'],
  ),
  HelpArticle(
    id: HelpTopicId.gcash,
    group: 'GCash & Money',
    title: 'GCash',
    icon: Icons.account_balance_wallet_outlined,
    description: 'Track your store GCash balance, services, and adjustments.',
    steps: [
      'Check the current balance.',
      'Use Cash-In or Cash-Out for customer services.',
      'Review transaction history when needed.',
      'To record a balance change outside a sale or customer service, tap Add Adjustment.',
      'Choose the type, enter the amount and a short reason, then enter the Owner PIN and tap Save Adjustment. The GCash reference is optional.',
    ],
    notes: [
      'Opening Balance: record the GCash money you already have when you start using the app. You can set it only once.',
      'Adjustment In: add money to the saved GCash balance. Example: adding ₱500 raises the balance by ₱500.',
      'Adjustment Out: subtract money from the saved GCash balance. Example: taking out ₱200 lowers the balance by ₱200.',
      'Add Adjustment updates the balance shown in this app. It does not send or receive money through GCash, and it does not add service fee income.',
      'Only the owner can save an adjustment. Check the reason and amount so the same money is not recorded twice.',
    ],
    keywords: ['wallet balance gcash service adjustment opening add subtract'],
  ),
  HelpArticle(
    id: HelpTopicId.cashIn,
    group: 'GCash & Money',
    title: 'GCash Cash-In',
    icon: Icons.call_received_outlined,
    description:
        'Store sends GCash. The customer gives cash and receives GCash.',
    steps: [
      'Enter the GCash amount and service fee.',
      'Choose Fee Added or Fee Deducted.',
      'Check the customer amount and GCash amount in the summary.',
      'Confirm after receiving the cash.',
    ],
    notes: [
      'Fee Added: the customer pays the amount plus the fee. Fee Deducted: the fee is taken from the amount sent through GCash.',
    ],
    keywords: ['cash in fee added deducted send gcash'],
  ),
  HelpArticle(
    id: HelpTopicId.cashOut,
    group: 'GCash & Money',
    title: 'GCash Cash-Out',
    icon: Icons.call_made_outlined,
    description: 'Store gives cash. The customer sends GCash to the store.',
    steps: [
      'Enter the cash-out amount and service fee.',
      'Choose Fee Added or Fee Deducted.',
      'Check the customer amount and cash amount in the summary.',
      'Confirm after receiving the GCash.',
    ],
    notes: [
      'Fee Added: the customer sends the amount plus the fee. Fee Deducted: the fee is taken from the cash the customer receives.',
    ],
    keywords: ['cash out fee added deducted receive gcash'],
  ),
  HelpArticle(
    id: HelpTopicId.expenses,
    group: 'GCash & Money',
    title: 'Expenses',
    icon: Icons.receipt_long_outlined,
    description:
        'Record store expenses such as supplies, transport, or utilities.',
    steps: [
      'Add an expense.',
      'Choose the category and payment method.',
      'Enter a clear description and amount.',
      'Save after checking the details.',
    ],
    keywords: ['expense gastos cash gcash'],
  ),
  HelpArticle(
    id: HelpTopicId.reports,
    group: 'Reports & Closing',
    title: 'Reports',
    icon: Icons.assessment_outlined,
    description:
        'Review sales and inventory information over a selected period.',
    steps: [
      'Open Reports in Settings.',
      'Choose the report and date range.',
      'Use the results to review store activity.',
    ],
    keywords: ['report sales inventory analytics'],
  ),
  HelpArticle(
    id: HelpTopicId.transactionHistory,
    group: 'Reports & Closing',
    title: 'Transaction History',
    icon: Icons.history_outlined,
    description: 'Find previous sales, UTANG activity, payments, and other recorded transactions.',
    steps: [
      'Open Transaction History.',
      'Expand a date to see entries.',
      'Tap an entry to view its details.',
    ],
    keywords: ['history receipt past transaction'],
  ),
  HelpArticle(
    id: HelpTopicId.dailyClosing,
    group: 'Reports & Closing',
    title: 'Daily Closing',
    icon: Icons.today_outlined,
    description: 'Review the day’s store activity using clear money and stock summaries.',
    steps: [
      'Choose the date.',
      'Review Today’s Earnings, physical cash, GCash, UTANG, expenses, and consignment.',
      'Use Close Day only when you want to save a frozen record.',
    ],
    notes: [
      'Close Day is optional. Today’s Earnings includes product sales and GCash fees before product costs and expenses. Physical Cash and GCash differences show recorded change for the day.',
    ],
    keywords: ['closing close day cash difference earnings supplier payable'],
  ),
  HelpArticle(
    id: HelpTopicId.backupRestore,
    group: 'Security & Backup',
    title: 'Backup & Restore',
    icon: Icons.backup_outlined,
    description:
        'Keep a safe copy of your store records and restore one when needed.',
    steps: [
      'Open Backup & Restore in Settings.',
      'Create a backup regularly.',
      'Choose a backup carefully before restoring it.',
    ],
    notes: ['Restoring replaces current app data with the selected backup.'],
    keywords: ['backup restore data save'],
  ),
  HelpArticle(
    id: HelpTopicId.staffSecurity,
    group: 'Security & Backup',
    title: 'Staff & Security',
    icon: Icons.security_outlined,
    description:
        'Use Security settings to manage access controls for the store.',
    steps: [
      'Open Security in Settings.',
      'Review staff accounts and access.',
      'Keep owner access private.',
    ],
    keywords: ['staff owner permission access pin'],
  ),
  HelpArticle(
    id: HelpTopicId.lockApp,
    group: 'Security & Backup',
    title: 'Lock App',
    icon: Icons.lock_outline,
    description: 'Lock TindaSari PH when the tablet is unattended.',
    steps: [
      'Open Lock App from Settings or the sidebar.',
      'Choose the account when returning.',
      'Enter the correct PIN to continue.',
    ],
    keywords: ['lock pin security'],
  ),
  HelpArticle(
    id: HelpTopicId.settings,
    group: 'Security & Backup',
    title: 'Settings',
    icon: Icons.settings_outlined,
    description: 'Find store management, security, reports, and data tools.',
    steps: [
      'Open Settings.',
      'Choose the section you need.',
      'Use Help & Guide whenever you need instructions.',
    ],
    keywords: ['setting tools management'],
  ),
  HelpArticle(
    id: HelpTopicId.appearance,
    group: 'Security & Backup',
    title: 'Light & Dark Theme',
    icon: Icons.dark_mode_outlined,
    description: 'Choose the appearance that is easiest for you to use.',
    steps: [
      'Open Settings.',
      'Choose Appearance.',
      'Select System Default, Light, or Dark.',
    ],
    keywords: ['appearance theme dark light system'],
  ),
];

HelpArticle helpArticle(HelpTopicId id) =>
    helpArticles.firstWhere((article) => article.id == id);
