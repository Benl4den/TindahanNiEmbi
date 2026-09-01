import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../models/customer.dart';
import '../../../repositories/payment_repository.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.customer,
    required this.repository,
  });
  final Customer customer;
  final PaymentRepository repository;
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final amount = TextEditingController();
  int cents = 0;
  bool saving = false;
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || cents <= 0 || cents > widget.customer.balanceCentavos) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Record this payment?'),
        content: Text(
          'Total UTANG: ₱${(widget.customer.balanceCentavos / 100).toStringAsFixed(2)}\nPayment: ₱${(cents / 100).toStringAsFixed(2)}\nRemaining: ₱${((widget.customer.balanceCentavos - cents) / 100).toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(AppStrings.back),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save Payment'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => saving = true);
    try {
      await widget.repository.record(
        customerId: widget.customer.id,
        amountCentavos: cents,
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment')),
    body: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Total UTANG: ₱${(widget.customer.balanceCentavos / 100).toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24),
            decoration: const InputDecoration(
              labelText: 'Payment Amount',
              prefixText: '₱ ',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(
              () => cents = ((double.tryParse(v) ?? 0) * 100).round(),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Remaining: ₱${((widget.customer.balanceCentavos - cents).clamp(0, widget.customer.balanceCentavos) / 100).toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed:
                cents > 0 && cents <= widget.customer.balanceCentavos && !saving
                ? save
                : null,
            child: const Text('Record Payment'),
          ),
        ],
      ),
    ),
  );
}
