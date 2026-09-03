import 'package:flutter/material.dart';

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
        title: const Text('Reports'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Inventory'),
            Tab(text: 'UTANG'),
            Tab(text: 'Sales'),
            Tab(text: 'Expenses'),
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
    builder: (_, s) => s.hasData
        ? ListView(
            padding: const EdgeInsets.all(20),
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
              ...s.data!.map(
                (r) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(r['name']! as String),
                    subtitle: Text(
                      'Stock: ${r['current_quantity']} • Cost: ₱${((r['purchase_price_centavos']! as int) / 100).toStringAsFixed(2)} • Selling: ₱${((r['selling_price_centavos']! as int) / 100).toStringAsFixed(2)}',
                    ),
                    trailing: Text(
                      '₱${((r['stock_value']! as int) / 100).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          )
        : const AppLoadingView(label: 'Loading report…'),
  );
  Widget _utang(BuildContext c) => FutureBuilder<List<Map<String, Object?>>>(
    future: repository.outstanding(),
    builder: (_, s) => s.hasData
        ? ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _open(c, 'UTANGAN Ledger', repository.customerLedger()),
              _open(c, 'UTANG History', repository.utangHistory()),
              _open(c, 'Payment History', repository.paymentHistory()),
              ...s.data!.map(
                (r) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(r['full_name']! as String),
                    subtitle: const Text('Outstanding UTANG'),
                    trailing: Text(
                      '₱${((r['balance']! as int) / 100).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          )
        : const AppLoadingView(label: 'Loading report…'),
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
            _total('Today', x.daily),
            _total('This Week', x.weekly),
            _total('This Month', x.monthly),
            const Divider(),
            Text(
              'Frequently Sold Products',
              style: Theme.of(c).textTheme.titleLarge,
            ),
            ...?(f.data?.map(
              (r) => ListTile(
                title: Text(r['name']! as String),
                trailing: Text('${r['quantity']} sold'),
              ),
            )),
          ],
        ),
      );
    },
  );
  Widget _total(String x, int v) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      title: Text(x),
      trailing: Text('₱${(v / 100).toStringAsFixed(2)}'),
    ),
  );
  Widget _expenses(BuildContext c) => _ExpenseReports(repository: repository);
  Widget _open(
    BuildContext context,
    String title,
    Future<List<Map<String, Object?>>> rows,
  ) => Card(
    margin: const EdgeInsets.only(bottom: 10),
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
              '₱${(count == 0 ? 0 : total / count / 100).toStringAsFixed(2)}',
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
              trailing: Text(
                '₱${((x['total']! as int) / 100).toStringAsFixed(2)}',
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _total(String label, int value) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      title: Text(label),
      trailing: Text('₱${(value / 100).toStringAsFixed(2)}'),
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
                          .map((e) => '${_rowLabel(e.key)}: ${e.value}')
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
}
