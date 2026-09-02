import 'package:sqflite/sqflite.dart';

class IntegrityResult {
  const IntegrityResult(this.sections);
  final List<IntegritySection> sections;
  List<String> get problems => sections.expand((x) => x.problems).toList();
  bool get healthy => problems.isEmpty;
}

class IntegritySection {
  const IntegritySection(this.name, this.problems);
  final String name;
  final List<String> problems;
  bool get healthy => problems.isEmpty;
}

class DataIntegrityService {
  const DataIntegrityService(this.db);
  final Database db;
  Future<IntegrityResult> check() async {
    final database = <String>[],
        inventory = <String>[],
        utangIssues = <String>[],
        consignmentIssues = <String>[],
        transactions = <String>[];
    const requiredTables = [
      'products',
      'inventory_movements',
      'cash_sales',
      'cash_sale_items',
      'utang_transactions',
      'utang_transaction_items',
      'utang_payments',
      'customer_ledger_entries',
      'consignment_batches',
      'consignment_allocations',
      'consignor_ledger_entries',
      'transaction_reversals',
      'transaction_corrections',
    ];
    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((x) => x['name']).toSet();
    final missing = requiredTables.where((x) => !tables.contains(x)).toList();
    if (missing.isNotEmpty) {
      database.add('Missing required tables: ${missing.join(', ')}.');
    }
    final fk = await db.rawQuery('PRAGMA foreign_key_check');
    if (fk.isNotEmpty) database.add('${fk.length} foreign-key problem(s).');
    final stock = await db.rawQuery(
      '''SELECT p.name FROM products p WHERE p.current_quantity<>COALESCE((SELECT SUM(quantity_change) FROM inventory_movements m WHERE m.product_id=p.id),0)''',
    );
    if (stock.isNotEmpty) {
      inventory.add('${stock.length} product stock balance mismatch(es).');
    }
    final cash = await db.rawQuery(
      '''SELECT s.id FROM cash_sales s WHERE s.total_centavos<>COALESCE((SELECT SUM(line_total_centavos) FROM cash_sale_items i WHERE i.cash_sale_id=s.id),0)''',
    );
    if (cash.isNotEmpty) {
      transactions.add('${cash.length} Cash Sale total mismatch(es).');
    }
    final utang = await db.rawQuery(
      '''SELECT u.id FROM utang_transactions u WHERE u.total_centavos<>COALESCE((SELECT SUM(line_total_centavos) FROM utang_transaction_items i WHERE i.utang_transaction_id=u.id),0)''',
    );
    if (utang.isNotEmpty) {
      transactions.add('${utang.length} UTANG total mismatch(es).');
    }
    final negative = await db.rawQuery(
      '''SELECT customer_id FROM customer_ledger_entries GROUP BY customer_id HAVING SUM(amount_change_centavos)<0''',
    );
    if (negative.isNotEmpty) {
      utangIssues.add('${negative.length} invalid customer ledger balance(s).');
    }
    final badUtangLinks = await db.rawQuery(
      """SELECT id FROM customer_ledger_entries WHERE
      (entry_type IN('UTANG','UTANG_REVERSAL') AND utang_transaction_id IS NULL) OR
      (entry_type IN('PAYMENT','PAYMENT_REVERSAL') AND payment_id IS NULL)""",
    );
    if (badUtangLinks.isNotEmpty) {
      utangIssues.add(
        '${badUtangLinks.length} customer ledger source-link problem(s).',
      );
    }
    final consignment = await db.rawQuery(
      '''SELECT b.id FROM consignment_batches b WHERE b.units_allocated<0 OR b.units_returned<0 OR b.units_allocated+b.units_returned>b.units_received''',
    );
    if (consignment.isNotEmpty) {
      consignmentIssues.add(
        '${consignment.length} consignment batch mismatch(es).',
      );
    }
    final missingSupplierLedger = await db.rawQuery(
      '''SELECT a.id FROM consignment_allocations a
      WHERE NOT EXISTS(SELECT 1 FROM consignor_ledger_entries l WHERE l.allocation_id=a.id)''',
    );
    if (missingSupplierLedger.isNotEmpty) {
      consignmentIssues.add(
        '${missingSupplierLedger.length} consignment allocation ledger problem(s).',
      );
    }
    final invalidRemittance = await db.rawQuery(
      '''SELECT consignor_id FROM consignor_ledger_entries
      GROUP BY consignor_id HAVING SUM(amount_change_centavos)<0''',
    );
    if (invalidRemittance.isNotEmpty) {
      consignmentIssues.add(
        '${invalidRemittance.length} invalid supplier payable balance(s).',
      );
    }
    return IntegrityResult([
      IntegritySection('Database', database),
      IntegritySection('Inventory', inventory),
      IntegritySection('UTANG', utangIssues),
      IntegritySection('Consignment', consignmentIssues),
      IntegritySection('Transactions', transactions),
    ]);
  }
}
