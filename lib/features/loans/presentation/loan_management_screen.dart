import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../models/payment_method.dart';
import '../../../repositories/loan_repository.dart';
import '../../../services/feature_access_service.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/pro_feature_preview.dart';

int? _moneyCentavos(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final cents = parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0'));
  return whole * 100 + cents;
}

class LoanManagementScreen extends StatefulWidget {
  const LoanManagementScreen({
    super.key,
    required this.repository,
    required this.access,
  });
  final LoanRepository repository;
  final FeatureAccessService access;
  @override
  State<LoanManagementScreen> createState() => _LoanManagementScreenState();
}

class _LoanManagementScreenState extends State<LoanManagementScreen> {
  bool completed = false;
  late Future<bool> accessAllowed;

  @override
  void initState() {
    super.initState();
    accessAllowed = widget.access.allows(ProFeature.fiveSixLoanManagement);
  }

  Future<void> _details(Map<String, Object?> loan) async {
    final loanId = loan['id']! as int;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(loan['lender_name']! as String),
        content: SizedBox(
          width: 500,
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: widget.repository.paymentsFor(loanId),
            builder: (_, result) {
              if (result.hasError) {
                return const Text(
                  'Could not load payments. Close and try again.',
                );
              }
              if (!result.hasData) {
                return const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final rows = result.data!;
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      'Borrowed: ${standardMoney(loan['borrowed_amount_centavos']! as int)}',
                    ),
                    Text(
                      'Agreed repayment: ${standardMoney(loan['agreed_repayment_centavos']! as int)}',
                    ),
                    Text(
                      'Remaining: ${standardMoney((loan['agreed_repayment_centavos']! as int) - (loan['paid_centavos']! as int))}',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Payment history',
                      style: Theme.of(dialog).textTheme.titleMedium,
                    ),
                    if (rows.isEmpty) const Text('No payments recorded yet.'),
                    ...rows.map((payment) {
                      final reversed = payment['status'] == 'REVERSED';
                      final when = DateTime.tryParse(
                        payment['paid_at']! as String,
                      )?.toLocal();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${standardMoney(payment['amount_centavos']! as int)} • ${PaymentMethod.fromDatabase(payment['payment_method']).label}',
                        ),
                        subtitle: Text(
                          '${when == null ? 'Date unavailable' : MaterialLocalizations.of(dialog).formatMediumDate(when)} • ${reversed ? 'Cancelled' : 'Completed'}${reversed ? '\nReason: ${payment['reversal_reason'] ?? 'Not recorded'}' : ''}',
                        ),
                        isThreeLine: reversed,
                        trailing: reversed
                            ? null
                            : TextButton(
                                onPressed: () async {
                                  Navigator.pop(dialog);
                                  await _cancelPayment(payment);
                                },
                                child: const Text('Cancel record'),
                              ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Close'),
          ),
          if (loan['status'] == 'ACTIVE')
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialog);
                await _pay(loan);
              },
              child: const Text('Record Payment'),
            ),
        ],
      ),
    );
  }

  Future<void> _cancelPayment(Map<String, Object?> payment) async {
    final reason = TextEditingController();
    final pin = TextEditingController();
    var busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, update) => AlertDialog(
          scrollable: true,
          title: const Text('Cancel Loan Payment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This restores ${standardMoney(payment['amount_centavos']! as int)} to the loan balance. The original payment stays in history.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(
                  labelText: 'Reason (required)',
                ),
              ),
              TextField(
                controller: pin,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Owner PIN'),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(dialog).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog),
              child: const Text('Keep Payment'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (reason.text.trim().isEmpty ||
                          pin.text.trim().isEmpty) {
                        update(() => error = 'Enter a reason and Owner PIN.');
                        return;
                      }
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final role = await AuthService(widget.repository.db)
                            .verify(pin.text);
                        if (role != UserRole.owner) {
                          throw StateError('Incorrect Owner PIN.');
                        }
                        await widget.repository.reversePayment(
                          paymentId: payment['id']! as int,
                          reason: reason.text,
                          ownerPinAuthorized: true,
                        );
                        if (dialog.mounted) Navigator.pop(dialog);
                        if (mounted) setState(() {});
                      } catch (e) {
                        if (dialog.mounted) {
                          update(
                            () => error = e is StateError
                                ? e.message
                                : 'Could not cancel payment. Please try again.',
                          );
                        }
                      } finally {
                        if (dialog.mounted) update(() => busy = false);
                      }
                    },
              child: const Text('Cancel Payment Record'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    pin.dispose();
  }

  Future<void> _pay(Map<String, Object?> loan) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    var method = PaymentMethod.cash;
    var busy = false;
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          scrollable: true,
          title: const Text('Record Loan Payment'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Remaining: ${standardMoney((loan['agreed_repayment_centavos']! as int) - (loan['paid_centavos']! as int))}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Payment amount',
                    prefixText: '₱ ',
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<PaymentMethod>(
                  segments: const [
                    ButtonSegment(
                      value: PaymentMethod.cash,
                      label: Text('Cash'),
                    ),
                    ButtonSegment(
                      value: PaymentMethod.gcash,
                      label: Text('GCash'),
                    ),
                    ButtonSegment(
                      value: PaymentMethod.maya,
                      label: Text('Maya'),
                    ),
                  ],
                  selected: {method},
                  onSelectionChanged: (v) => setDialog(() => method = v.single),
                ),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Note or reference (optional)',
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(d).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final cents = _moneyCentavos(amount.text);
                      final remaining =
                          (loan['agreed_repayment_centavos']! as int) -
                          (loan['paid_centavos']! as int);
                      if (cents == null || cents <= 0 || cents > remaining) {
                        setDialog(
                          () => error =
                              'Enter an amount from ₱0.01 up to ${standardMoney(remaining)} (at most two decimals).',
                        );
                        return;
                      }
                      setDialog(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.repository.pay(
                          loanId: loan['id']! as int,
                          amount: cents,
                          method: method,
                          note: note.text,
                          reference: note.text,
                        );
                        if (d.mounted) Navigator.pop(d, true);
                      } catch (_) {
                        if (d.mounted) {
                          setDialog(
                            () => error = 'Could not record payment. Check the remaining balance and try again.',
                          );
                        }
                      } finally {
                        if (d.mounted) setDialog(() => busy = false);
                      }
                    },
              child: const Text('Record Payment'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    note.dispose();
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _addLender() async {
    if (!await widget.access.allows(ProFeature.fiveSixLoanManagement)) {
      return;
    }
    if (!mounted) return;
    final c = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (x) => StatefulBuilder(
        builder: (_, update) => AlertDialog(
          title: const Text('Add Lender'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: c,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Lender name'),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(x).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (c.text.trim().isEmpty) {
                  update(() => error = 'Enter a lender name.');
                  return;
                }
                try {
                  await widget.repository.createLender(c.text);
                  if (x.mounted) Navigator.pop(x);
                } catch (_) {
                  if (x.mounted) {
                    update(
                      () => error = 'Could not save lender. Please try again.',
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _add() async {
    if (!await widget.access.allows(ProFeature.fiveSixLoanManagement)) return;
    final lenders = await widget.repository.lenders();
    if (!mounted) return;
    if (lenders.isEmpty) {
      await _addLender();
      return;
    }
    int lender = (lenders.first['id']! as int);
    final borrowed = TextEditingController(),
        agreed = TextEditingController(),
        scheduled = TextEditingController();
    var source = 'NEW', freq = 'DAILY', method = PaymentMethod.cash;
    var busy = false;
    String? error;
    await showDialog(
      context: context,
      builder: (x) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          scrollable: true,
          title: const Text('Add 5-6 Loan'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(x).colorScheme.error),
                  ),
                DropdownButtonFormField<int>(
                  initialValue: lender,
                  items: lenders
                      .map(
                        (r) => DropdownMenuItem(
                          value: r['id']! as int,
                          child: Text(r['name']! as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => set(() => lender = v!),
                  decoration: const InputDecoration(labelText: 'Lender'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: source,
                  items: const [
                    DropdownMenuItem(
                      value: 'NEW',
                      child: Text('New loan received now'),
                    ),
                    DropdownMenuItem(
                      value: 'EXISTING',
                      child: Text('Existing loan to track'),
                    ),
                  ],
                  onChanged: (v) => set(() => source = v!),
                  decoration: const InputDecoration(labelText: 'Loan source'),
                ),
                TextField(
                  controller: borrowed,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount borrowed',
                    prefixText: '₱ ',
                  ),
                ),
                TextField(
                  controller: agreed,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Agreed total repayment',
                    prefixText: '₱ ',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: freq,
                  items: const [
                    DropdownMenuItem(
                      value: 'DAILY',
                      child: Text('Daily collection'),
                    ),
                    DropdownMenuItem(
                      value: 'WEEKLY',
                      child: Text('Weekly collection'),
                    ),
                  ],
                  onChanged: (v) => set(() => freq = v!),
                  decoration: const InputDecoration(
                    labelText: 'Collection frequency',
                  ),
                ),
                TextField(
                  controller: scheduled,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Expected payment (optional)',
                    prefixText: '₱ ',
                  ),
                ),
                if (source == 'NEW')
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: method,
                    items: PaymentMethod.values
                        .map(
                          (v) =>
                              DropdownMenuItem(value: v, child: Text(v.label)),
                        )
                        .toList(),
                    onChanged: (v) => set(() => method = v!),
                    decoration: const InputDecoration(
                      labelText: 'Money received through',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final borrowedCents = _moneyCentavos(borrowed.text);
                      final agreedCents = _moneyCentavos(agreed.text);
                      final scheduledCents = scheduled.text.trim().isEmpty
                          ? null
                          : _moneyCentavos(scheduled.text);
                      if (borrowedCents == null ||
                          borrowedCents <= 0 ||
                          agreedCents == null ||
                          agreedCents < borrowedCents ||
                          (scheduled.text.trim().isNotEmpty &&
                              (scheduledCents == null ||
                                  scheduledCents <= 0))) {
                        set(
                          () => error = 'Enter valid positive amounts. Agreed repayment must be at least the amount borrowed; use at most two decimals.',
                        );
                        return;
                      }
                      set(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.repository.create(
                          lenderId: lender,
                          borrowed: borrowedCents,
                          agreed: agreedCents,
                          sourceKind: source,
                          start: DateTime.now(),
                          frequency: freq,
                          scheduled: scheduledCents,
                          receivedMethod: source == 'NEW' ? method : null,
                        );
                        if (x.mounted) Navigator.pop(x);
                      } catch (_) {
                        if (x.mounted) {
                          set(
                            () => error = 'Could not save loan. Check the details and try again.',
                          );
                        }
                      } finally {
                        if (x.mounted) set(() => busy = false);
                      }
                    },
              child: const Text('Save Loan'),
            ),
          ],
        ),
      ),
    );
    borrowed.dispose();
    agreed.dispose();
    scheduled.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('5-6 Loan Management'),
      actions: [
        FutureBuilder<bool>(
          future: accessAllowed,
          builder: (_, result) => result.data != true
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    IconButton(
                      onPressed: _addLender,
                      tooltip: 'Add lender',
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                    ),
                    IconButton(
                      onPressed: _add,
                      tooltip: 'Add loan',
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
        ),
      ],
    ),
    body: FutureBuilder<bool>(
      future: accessAllowed,
      builder: (_, g) {
        if (g.hasError) {
          return const Center(
            child: Text('Could not check plan access. Reopen this section.'),
          );
        }
        if (!g.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!g.data!) {
          return const ProFeaturePreview(
            title: '5-6 Loan Management',
            description: 'Track lender balances, daily or weekly collections, and payment history in one clear place.',
            icon: Icons.account_balance_outlined,
          );
        }
        return FutureBuilder<List<Map<String, Object?>>>(
          future: widget.repository.loans(completed: completed),
          builder: (_, s) => s.hasError
              ? const Center(
                  child: Text('Could not load loans. Reopen this section.'),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ChoiceChip(
                        label: Text(
                          completed ? 'Completed loans' : 'Active loans',
                        ),
                        selected: true,
                        onSelected: (_) =>
                            setState(() => completed = !completed),
                      ),
                    ),
                    Expanded(
                      child: !s.hasData
                          ? const Center(child: CircularProgressIndicator())
                          : s.data!.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    completed
                                        ? 'No completed loans yet.'
                                        : 'No active loans yet.',
                                  ),
                                  if (!completed)
                                    TextButton.icon(
                                      onPressed: _add,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Add Loan'),
                                    ),
                                ],
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: s.data!.map((r) {
                                final remaining =
                                    (r['agreed_repayment_centavos']! as int) -
                                    (r['paid_centavos']! as int);
                                return Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(
                                        Icons.account_balance_outlined,
                                      ),
                                    ),
                                    title: Text(r['lender_name']! as String),
                                    subtitle: Text(
                                      '${r['collection_frequency']} collection • Borrowed ${standardMoney(r['borrowed_amount_centavos']! as int)}',
                                    ),
                                    onTap: () => _details(r),
                                    trailing: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        const Text('Remaining'),
                                        Text(
                                          standardMoney(remaining),
                                          style: Theme.of(c)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
        );
      },
    ),
  );
}
