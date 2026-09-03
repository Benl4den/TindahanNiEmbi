import 'package:flutter/material.dart';

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
  String? error;
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || cents <= 0 || cents > widget.customer.balanceCentavos) return;
    setState(() => saving = true);
    try {
      await widget.repository.record(
        customerId: widget.customer.id,
        amountCentavos: cents,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not record payment. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Record Payment')),
    body: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Total UTANG Balance: ₱${(widget.customer.balanceCentavos / 100).toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            widget.customer.fullName,
            style: Theme.of(context).textTheme.titleLarge,
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
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}
