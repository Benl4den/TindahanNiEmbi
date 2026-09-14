import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../repositories/staff_activity_repository.dart';
import '../../../services/app_refresh_controller.dart';

class StaffActivityScreen extends StatefulWidget {
  const StaffActivityScreen({super.key, required this.repository});
  final StaffActivityRepository repository;

  @override
  State<StaffActivityScreen> createState() => _StaffActivityScreenState();
}

class _StaffActivityScreenState extends State<StaffActivityScreen> {
  DateTime day = DateTime.now();
  late Future<List<StaffActivitySummary>> data;

  @override
  void initState() {
    super.initState();
    _reload();
    AppRefreshController.instance.addListener(_changed);
  }

  @override
  void dispose() {
    AppRefreshController.instance.removeListener(_changed);
    super.dispose();
  }

  void _reload() => data = widget.repository.forDay(day);

  void _changed() {
    if (mounted) setState(_reload);
  }

  Future<void> _pickDay() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: day,
    );
    if (selected != null && mounted) {
      setState(() {
        day = selected;
        _reload();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staff Activity Summary')),
    body: FutureBuilder<List<StaffActivitySummary>>(
      future: data,
      builder: (_, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final summaries = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    MaterialLocalizations.of(context).formatFullDate(day),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickDay,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Choose date'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Completed transactions only. Cancelled records are excluded. Older unnamed activity is grouped separately.',
            ),
            const SizedBox(height: 16),
            if (summaries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No staff accounts or staff activity for this date.',
                  ),
                ),
              ),
            for (final s in summaries) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _metric(
                            'Completed sales',
                            '${s.cashSales} • ${standardMoney(s.cashSalesAmount)}',
                          ),
                          _metric(
                            'UTANG sales',
                            '${s.utangSales} • ${standardMoney(s.utangSalesAmount)}',
                          ),
                          _metric(
                            'Payments collected',
                            '${s.payments} • ${standardMoney(s.paymentsAmount)}',
                          ),
                          _metric(
                            'GCash services',
                            '${s.cashIn} Cash-In • ${s.cashOut} Cash-Out',
                          ),
                          _metric(
                            'GCash fees earned',
                            standardMoney(s.serviceFees),
                          ),
                          _metric(
                            'Expenses recorded',
                            '${s.expenses} • ${standardMoney(s.expensesAmount)}',
                          ),
                          _metric('Adjustments recorded', '${s.adjustments}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    ),
  );

  Widget _metric(String label, String value) => Container(
    width: 190,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
