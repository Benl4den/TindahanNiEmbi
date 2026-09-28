import 'package:flutter/material.dart';

import '../../../models/customer.dart';
import '../../../core/formatters/number_format.dart';
import '../../../models/payment_method.dart';
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
  final gcashReference = TextEditingController();
  PaymentMethod paymentMethod = PaymentMethod.cash;
  int cents = 0;
  bool saving = false;
  bool submitted = false;
  String? error;
  String? get amountError {
    if (!submitted) return null;
    if (amount.text.trim().isEmpty) return 'Enter a payment amount.';
    final value = parseMoneyCentavos(amount.text);
    if (value == null) return 'Use pesos with up to two decimal places.';
    if (value <= 0) return 'Amount must be greater than ₱0.00.';
    if (value > widget.customer.balanceCentavos) {
      return 'Cannot exceed ${standardMoney(widget.customer.balanceCentavos)}.';
    }
    return null;
  }

  @override
  void dispose() {
    amount.dispose();
    gcashReference.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => submitted = true);
    if (amountError != null) return;
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
        paymentMethod: paymentMethod,
        gcashReference: gcashReference.text,
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
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            28,
            28,
            28,
            28 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 56),
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
                SegmentedButton<PaymentMethod>(
                  segments: const [
                    ButtonSegment(
                      value: PaymentMethod.cash,
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Cash'),
                    ),
                    ButtonSegment(
                      value: PaymentMethod.gcash,
                      icon: Icon(Icons.phone_android),
                      label: Text('GCash'),
                    ),
                    ButtonSegment(
                      value: PaymentMethod.maya,
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: Text('Maya'),
                    ),
                  ],
                  selected: {paymentMethod},
                  onSelectionChanged: saving
                      ? null
                      : (value) => setState(() => paymentMethod = value.single),
                ),
                if (paymentMethod != PaymentMethod.cash) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: gcashReference,
                    decoration: InputDecoration(
                      labelText: paymentMethod == PaymentMethod.maya
                          ? 'Maya Reference (optional)'
                          : 'GCash Reference (optional)',
                      prefixIcon: Icon(Icons.tag),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 24),
                  decoration: InputDecoration(
                    labelText: 'Payment Amount',
                    prefixText: '₱ ',
                    border: const OutlineInputBorder(),
                    errorText: amountError,
                  ),
                  onChanged: (v) =>
                      setState(() => cents = parseMoneyCentavos(v) ?? 0),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  'Remaining: ${standardMoney((widget.customer.balanceCentavos - cents).clamp(0, widget.customer.balanceCentavos))}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: const Text('Record Payment'),
                ),
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
