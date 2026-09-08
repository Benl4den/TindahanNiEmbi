import 'package:flutter/material.dart';

import '../../../models/customer.dart';
import '../../../core/formatters/number_format.dart';
import '../../../repositories/payment_repository.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.customer,
    required this.repository,
    this.onRecorded,
  });
  final Customer customer;
  final PaymentRepository repository;

  /// Lets the screen behind a dialog replace its displayed balance immediately.
  final void Function(int amountCentavos)? onRecorded;
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
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.payments_outlined),
        title: const Text('Confirm UTANG Payment'),
        content: Text(
          'Record ${standardMoney(cents)} from ${widget.customer.fullName}?\n\nRemaining balance: ${standardMoney(widget.customer.balanceCentavos - cents)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirm Payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => saving = true);
    try {
      await widget.repository.record(
        customerId: widget.customer.id,
        amountCentavos: cents,
      );
    } catch (exception, stackTrace) {
      // Keep the customer-facing error short, but retain the actual database
      // failure in the debug console for diagnosis.
      debugPrint('Unable to record UTANG payment: $exception\n$stackTrace');
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not record payment. Please try again.';
        });
      }
      return;
    }

    // A payment is committed at this point. Refresh is deliberately best
    // effort: it must never turn a successful payment into a false failure.
    try {
      widget.onRecorded?.call(cents);
    } catch (exception, stackTrace) {
      debugPrint(
        'UTANG payment saved; detail refresh will retry: '
        '$exception\n$stackTrace',
      );
    }
    if (mounted) Navigator.pop(context, true);
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
            'Total UTANG Balance: ${standardMoney(widget.customer.balanceCentavos)}',
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
            'Remaining: ${standardMoney((widget.customer.balanceCentavos - cents).clamp(0, widget.customer.balanceCentavos))}',
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
