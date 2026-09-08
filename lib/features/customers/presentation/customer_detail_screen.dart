import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/formatters/number_format.dart';
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
  int? visibleBalanceCentavos;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() => data = widget.repository.details(widget.customerId);
  Future<void> refreshDetailsNow() async {
    final refreshed = await widget.repository.details(widget.customerId);
    if (!mounted) return;
    setState(() {
      data = Future.value(refreshed);
      visibleBalanceCentavos = null;
    });
  }

  void applyCommittedPayment(int previousBalance, int amountCentavos) {
    if (!mounted) return;
    setState(() {
      visibleBalanceCentavos = (previousBalance - amountCentavos).clamp(
        0,
        previousBalance,
      );
    });
    refreshDetailsNow();
  }

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
        final currentBalance =
            visibleBalanceCentavos ?? d.customer.balanceCentavos;
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
                      standardMoney(currentBalance),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    FilledButton(
                      onPressed: currentBalance == 0
                          ? null
                          : () async {
                              final ok = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PaymentScreen(
                                    customer: d.customer,
                                    repository: widget.payments,
                                    onRecorded: (amount) =>
                                        applyCommittedPayment(
                                          currentBalance,
                                          amount,
                                        ),
                                  ),
                                ),
                              );
                              if (ok == true && mounted) {
                                await refreshDetailsNow();
                              }
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
                  '${e.amountCentavos < 0 ? '-' : '+'}${standardMoney(e.amountCentavos.abs())}',
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
