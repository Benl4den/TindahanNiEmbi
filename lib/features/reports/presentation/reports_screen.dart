import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../repositories/reports_repository.dart';
import '../../../widgets/app_state_view.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.repository});
  final ReportsRepository repository;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Store Reports'),
            Text(
              'Clear totals for everyday decisions',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        bottom: const TabBar(
          tabs: [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Inventory'),
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'UTANG'),
            Tab(icon: Icon(Icons.point_of_sale_outlined), text: 'Sales'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Expenses'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _inventory(context),
          _utang(context),
          _sales(context),
          _expenses(context),
        ],
      ),
    ),
  );
  Widget _inventory(
    BuildContext c,
  ) => FutureBuilder<List<Map<String, Object?>>>(
    future: repository.inventory(),
    builder: (_, s) {
      if (!s.hasData) {
        return const AppLoadingView(label: 'Loading inventory report…');
      }
      final rows = s.data!;
      final total = rows.fold<int>(
        0,
        (sum, row) => sum + (row['stock_value']! as int),
      );
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _reportIntro(
            c,
            'Owned Inventory',
            standardMoney(total),
            '${rows.length} active products • Consignment stock excluded',
            Icons.inventory_2_outlined,
          ),
          const SizedBox(height: 12),
          Text('Movement Records', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _open(
                c,
                'Stock-In History',
                repository.movements(outgoing: false),
              ),
              _open(
                c,
                'Stock-Out History',
                repository.movements(outgoing: true),
              ),
              _open(c, 'All Stock Movements', repository.movements()),
            ],
          ),
          const SizedBox(height: 20),
          Text('Product Valuation', style: Theme.of(c).textTheme.titleLarge),
          const Text(
            'Estimated cost uses the saved purchase package and its package price.',
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (r) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.inventory_2_outlined),
                ),
                title: Text(
                  r['name']! as String,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Stock: ${_quantity(r, 'current_quantity')}\nPurchase: ${standardMoney(r['purchase_price_centavos']! as int)} per ${r['purchase_package']} • Selling: ${standardMoney(r['selling_price_centavos']! as int)}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Estimated cost'),
                    Text(
                      standardMoney(r['stock_value']! as int),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                isThreeLine: true,
              ),
            ),
          ),
        ],
      );
    },
  );
  Widget _utang(BuildContext c) => FutureBuilder<List<Map<String, Object?>>>(
    future: repository.outstanding(),
    builder: (_, s) {
      if (!s.hasData) {
        return const AppLoadingView(label: 'Loading UTANG report…');
      }
      final rows = s.data!;
      final total = rows.fold<int>(
        0,
        (sum, row) => sum + (row['balance']! as int),
      );
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _reportIntro(
            c,
            'Outstanding UTANG',
            standardMoney(total),
            '${rows.length} ${rows.length == 1 ? 'UTANGAN' : 'UTANGAN accounts'} with balance',
            Icons.people_alt_outlined,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _open(c, 'UTANGAN Ledger', repository.customerLedger()),
              _open(c, 'UTANG History', repository.utangHistory()),
              _open(c, 'Payment History', repository.paymentHistory()),
            ],
          ),
          const SizedBox(height: 20),
          Text('Balances by UTANGAN', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...rows.map(
            (r) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(r['full_name']! as String),
                subtitle: const Text('Outstanding UTANG'),
                trailing: Text(
                  standardMoney(r['balance']! as int),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  Widget _sales(BuildContext c) => FutureBuilder<SalesPeriodSummary>(
    future: repository.salesPeriods(),
    builder: (_, s) {
      if (!s.hasData) return const AppLoadingView(label: 'Loading report…');
      final x = s.data!;
      return FutureBuilder<List<Map<String, Object?>>>(
        future: repository.frequentProducts(),
        builder: (_, f) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _reportIntro(
              c,
              "Today's Sales",
              standardMoney(x.daily),
              'Cash ${standardMoney(x.dailyCash)}  •  GCash ${standardMoney(x.dailyGCash)}',
              Icons.point_of_sale_outlined,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(width: 280, child: _total('This Week', x.weekly)),
                SizedBox(width: 280, child: _total('This Month', x.monthly)),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'GCash Service Income',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            FutureBuilder<Map<String, Object?>>(
              future: repository.gcashServiceSummary(),
              builder: (_, services) {
                if (!services.hasData) return const LinearProgressIndicator();
                final g = services.data!;
                final fees =
                    (g['cash_in_fees']! as int) + (g['cash_out_fees']! as int);
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 280,
                      child: _total(
                        'Cash-In (${g['cash_in_count']})',
                        g['cash_in_principal']! as int,
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: _total(
                        'Cash-Out (${g['cash_out_count']})',
                        g['cash_out_principal']! as int,
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: _total('Service Fee Income', fees),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Frequently Sold Products',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            ...?(f.data?.map(
              (r) => ListTile(
                title: Text(r['name']! as String),
                trailing: Text('${_quantity(r, 'quantity')} sold'),
              ),
            )),
          ],
        ),
      );
    },
  );
  Widget _total(String x, int v) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(title: Text(x), trailing: Text(standardMoney(v))),
  );
  Widget _reportIntro(
    BuildContext context,
    String title,
    String value,
    String detail,
    IconData icon,
  ) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.white, size: 42),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70)),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(detail, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ],
    ),
  );
  String _quantity(Map<String, Object?> row, String key) => baseQuantityText(
    row[key]! as int,
    baseUnitCode: row['base_unit_code'] as String? ?? 'PIECE',
    baseUnitLabel: row['base_unit_label'] as String? ?? 'piece',
  );
  Widget _expenses(BuildContext c) => _ExpenseReports(repository: repository);
  Widget _open(
    BuildContext context,
    String title,
    Future<List<Map<String, Object?>>> rows,
  ) => Card(
    child: SizedBox(
      width: 250,
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _RowsScreen(title: title, rows: rows),
          ),
        ),
      ),
    ),
  );
}

class _ExpenseReports extends StatefulWidget {
  const _ExpenseReports({required this.repository});
  final ReportsRepository repository;
  @override
  State<_ExpenseReports> createState() => _ExpenseReportsState();
}

class _ExpenseReportsState extends State<_ExpenseReports> {
  DateTimeRange? range;
  int? categoryId;
  late final Future<List<Map<String, Object?>>> categories = widget.repository
      .expenseCategories();
  DateTime? get from => range == null
      ? null
      : DateTime(range!.start.year, range!.start.month, range!.start.day);
  DateTime? get to => range == null
      ? null
      : DateTime(
          range!.end.year,
          range!.end.month,
          range!.end.day,
        ).add(const Duration(days: 1));

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Object>>(
    future: Future.wait<Object>([
      widget.repository.expenseSummary(
        from: from,
        to: to,
        categoryId: categoryId,
      ),
      widget.repository.expensesByCategory(
        from: from,
        to: to,
        categoryId: categoryId,
      ),
    ]),
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('Expense reports could not be loaded.'),
        );
      }
      if (!snapshot.hasData) {
        return const AppLoadingView(label: 'Loading report…');
      }
      final summary = snapshot.data![0] as Map<String, Object?>;
      final breakdown = snapshot.data![1] as List<Map<String, Object?>>;
      final count = summary['count']! as int, total = summary['total']! as int;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _expenseIntro(
            context,
            'Operating Expenses',
            standardMoney(total),
            '$count recorded ${count == 1 ? 'expense' : 'expenses'} for the selected period',
            Icons.receipt_long_outlined,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: Text(
                  range == null
                      ? 'All Dates'
                      : '${range!.start.month}/${range!.start.day}/${range!.start.year} – ${range!.end.month}/${range!.end.day}/${range!.end.year}',
                ),
              ),
              if (range != null)
                TextButton(
                  onPressed: () => setState(() => range = null),
                  child: const Text('Clear Dates'),
                ),
              SizedBox(
                width: 260,
                child: FutureBuilder<List<Map<String, Object?>>>(
                  future: categories,
                  builder: (_, snapshot) => DropdownButtonFormField<int?>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All Categories'),
                      ),
                      ...?snapshot.data?.map(
                        (x) => DropdownMenuItem<int?>(
                          value: x['id']! as int,
                          child: Text(
                            '${x['name']}${x['is_archived'] == 1 ? ' (Archived)' : ''}',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => categoryId = value),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _total('Total Operating Expenses', total),
          _total('Largest Expense', summary['largest']! as int),
          ListTile(
            title: const Text('Expense Count'),
            trailing: Text('$count'),
          ),
          ListTile(
            title: const Text('Average Expense'),
            trailing: Text(
              standardMoney(count == 0 ? 0 : (total / count).round()),
            ),
          ),
          const Divider(),
          Text(
            'Expenses by Category',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ...breakdown.map(
            (x) => ListTile(
              title: Text(x['name']! as String),
              subtitle: Text('${x['count']} expenses'),
              trailing: Text(standardMoney(x['total']! as int)),
            ),
          ),
        ],
      );
    },
  );

  Widget _total(String label, int value) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(title: Text(label), trailing: Text(standardMoney(value))),
  );
  Widget _expenseIntro(
    BuildContext context,
    String title,
    String value,
    String detail,
    IconData icon,
  ) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.white, size: 42),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70)),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(detail, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ],
    ),
  );
  Future<void> _pickRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: range,
    );
    if (selected != null) setState(() => range = selected);
  }
}

class _RowsScreen extends StatelessWidget {
  const _RowsScreen({required this.title, required this.rows});
  final String title;
  final Future<List<Map<String, Object?>>> rows;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: rows,
      builder: (_, snapshot) => snapshot.hasData
          ? ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: snapshot.data!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, index) {
                final row = snapshot.data![index];
                return Card(
                  child: ListTile(
                    title: Text(
                      (row['name'] ??
                              row['full_name'] ??
                              row['type'] ??
                              row['entry_type'])
                          .toString(),
                    ),
                    subtitle: Text(
                      row.entries
                          .where(
                            (e) => !const {'name', 'full_name'}.contains(e.key),
                          )
                          .where(
                            (e) => !const {
                              'base_unit_code',
                              'base_unit_label',
                            }.contains(e.key),
                          )
                          .map((e) => '${_rowLabel(e.key)}: ${_value(row, e)}')
                          .join('\n'),
                    ),
                  ),
                );
              },
            )
          : const AppLoadingView(label: 'Loading report…'),
    ),
  );

  String _rowLabel(String key) => switch (key) {
    'reference' => 'Reference',
    'occurred_at' || 'created_at' => 'Date and Time',
    'quantity' || 'quantity_change' => 'Quantity',
    'amount_centavos' || 'total_centavos' => 'Amount',
    'balance' => 'Balance',
    'notes' => 'Notes',
    'type' || 'entry_type' => 'Type',
    _ => key.replaceAll('_', ' '),
  };

  Object? _value(Map<String, Object?> row, MapEntry<String, Object?> entry) {
    if (entry.key == 'quantity' || entry.key == 'quantity_change') {
      final value = entry.value! as int;
      final sign = value < 0 ? '-' : '';
      return '$sign${baseQuantityText(value.abs(), baseUnitCode: row['base_unit_code'] as String? ?? 'PIECE', baseUnitLabel: row['base_unit_label'] as String? ?? 'piece')}';
    }
    return entry.value;
  }
}
