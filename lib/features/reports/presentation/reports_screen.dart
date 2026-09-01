import 'package:flutter/material.dart';

import '../../../repositories/reports_repository.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.repository});
  final ReportsRepository repository;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Inventory'),
            Tab(text: 'UTANG'),
            Tab(text: 'Sales'),
          ],
        ),
      ),
      body: TabBarView(
        children: [_inventory(context), _utang(context), _sales(context)],
      ),
    ),
  );
  Widget _inventory(
    BuildContext c,
  ) => FutureBuilder<List<Map<String, Object?>>>(
    future: repository.inventory(),
    builder: (_, s) => s.hasData
        ? ListView(
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
              _open(c, 'Tanang Kausaban sa Stock', repository.movements()),
              ...s.data!.map(
                (r) => ListTile(
                  title: Text(r['name']! as String),
                  subtitle: Text(
                    'Stock: ${r['current_quantity']} • Cost: ₱${((r['purchase_price_centavos']! as int) / 100).toStringAsFixed(2)} • Selling: ₱${((r['selling_price_centavos']! as int) / 100).toStringAsFixed(2)}',
                  ),
                  trailing: Text(
                    '₱${((r['stock_value']! as int) / 100).toStringAsFixed(2)}',
                  ),
                ),
              ),
            ],
          )
        : const Center(child: CircularProgressIndicator()),
  );
  Widget _utang(BuildContext c) => FutureBuilder<List<Map<String, Object?>>>(
    future: repository.outstanding(),
    builder: (_, s) => s.hasData
        ? ListView(
            children: [
              _open(c, 'Customer Ledger', repository.customerLedger()),
              _open(c, 'UTANG History', repository.utangHistory()),
              _open(c, 'Payment History', repository.paymentHistory()),
              ...s.data!.map(
                (r) => ListTile(
                  title: Text(r['full_name']! as String),
                  trailing: Text(
                    '₱${((r['balance']! as int) / 100).toStringAsFixed(2)}',
                  ),
                ),
              ),
            ],
          )
        : const Center(child: CircularProgressIndicator()),
  );
  Widget _sales(BuildContext c) => FutureBuilder<SalesPeriodSummary>(
    future: repository.salesPeriods(),
    builder: (_, s) {
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final x = s.data!;
      return FutureBuilder<List<Map<String, Object?>>>(
        future: repository.frequentProducts(),
        builder: (_, f) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _total('Karon', x.daily),
            _total('Karong Semana', x.weekly),
            _total('Karong Bulan', x.monthly),
            const Divider(),
            const Text('Frequently Sold Products'),
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
    child: ListTile(
      title: Text(x),
      trailing: Text('₱${(v / 100).toStringAsFixed(2)}'),
    ),
  );
  Widget _open(
    BuildContext context,
    String title,
    Future<List<Map<String, Object?>>> rows,
  ) => ListTile(
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RowsScreen(title: title, rows: rows),
      ),
    ),
  );
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
          ? ListView(
              children: snapshot.data!
                  .map(
                    (row) => ListTile(
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
                              (e) =>
                                  !const {'name', 'full_name'}.contains(e.key),
                            )
                            .map((e) => '${e.key}: ${e.value}')
                            .join('\n'),
                      ),
                    ),
                  )
                  .toList(),
            )
          : const Center(child: CircularProgressIndicator()),
    ),
  );
}
