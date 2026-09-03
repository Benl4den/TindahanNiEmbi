import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/customer.dart';
import '../../../repositories/customer_repository.dart';
import '../../../repositories/payment_repository.dart';
import '../../payments/presentation/payment_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.repository,
    required this.payments,
    required this.customerId,
  });
  final CustomerRepository repository;
  final PaymentRepository payments;
  final int customerId;
  @override
  State<CustomerDetailScreen> createState() => _State();
}

class _State extends State<CustomerDetailScreen> {
  late Future<CustomerDetails> data;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => data = widget.repository.details(widget.customerId);
  String type(String x) => switch (x) {
    'UTANG' => 'UTANG Sale',
    'PAYMENT' => 'Payment',
    'UTANG_REVERSAL' => 'UTANG Reversal',
    'PAYMENT_REVERSAL' => 'Payment Reversal',
    _ => x,
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AppStrings.customers)),
    body: FutureBuilder<CustomerDetails>(
      future: data,
      builder: (context, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final d = s.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              d.customer.fullName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(AppStrings.totalUtang),
                    Text(
                      '₱${(d.customer.balanceCentavos / 100).toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    FilledButton(
                      onPressed: d.customer.balanceCentavos == 0
                          ? null
                          : () async {
                              final ok = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PaymentScreen(
                                    customer: d.customer,
                                    repository: widget.payments,
                                  ),
                                ),
                              );
                              if (ok == true && mounted) setState(reload);
                            },
                      child: const Text('Payment'),
                    ),
                  ],
                ),
              ),
            ),
            ...d.ledger.map(
              (e) => ListTile(
                title: Text(type(e.type)),
                subtitle: Text(e.occurredAt.toLocal().toString()),
                trailing: Text(
                  '${e.amountCentavos < 0 ? '-' : '+'}₱${(e.amountCentavos.abs() / 100).toStringAsFixed(2)}',
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
