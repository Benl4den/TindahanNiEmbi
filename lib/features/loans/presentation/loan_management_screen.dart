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

Widget _loanMetric(BuildContext context, String label, int amount) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(label, style: Theme.of(context).textTheme.bodyMedium),
    const SizedBox(height: 3),
    Text(standardMoney(amount), style: Theme.of(context).textTheme.titleMedium),
  ],
);

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
  late Future<List<Map<String, Object?>>> _loans;

  @override
  void initState() {
    super.initState();
    accessAllowed = widget.access.allows(ProFeature.fiveSixLoanManagement);
    _loans = widget.repository.loans();
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _loans = widget.repository.loans(completed: completed);
      });
    }
  }

  // Wait until the dialog has left the overlay before disposing its text
  // controllers, rebuilding this screen, or opening the next dialog.
  Future<T?> _showLoanDialog<T>(WidgetBuilder builder) {
    final route = DialogRoute<T>(context: context, builder: builder);
    Navigator.of(context).push(route);
    return route.completed;
  }

  Future<void> _details(Map<String, Object?> loan) async {
    final loanId = loan['id']! as int;
    Map<String, Object?>? paymentToCancel;
    var recordPayment = false;
    await _showLoanDialog<void>(
      (dialog) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loan['lender_name']! as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Loan details',
                    style: Theme.of(dialog).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close loan details',
              onPressed: () => Navigator.pop(dialog),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
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
                    Builder(
                      builder: (context) {
                        final borrowed =
                            loan['borrowed_amount_centavos']! as int;
                        final total = loan['agreed_repayment_centavos']! as int;
                        final paid = loan['paid_centavos']! as int;
                        final remaining = (total - paid).clamp(0, total);
                        final progress = total == 0
                            ? 0.0
                            : (paid / total).clamp(0.0, 1.0);
                        Widget metric(String label, int amount) => Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label),
                              const SizedBox(height: 4),
                              Text(
                                standardMoney(amount),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        );
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TOTAL TO REPAY',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  standardMoney(total),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                ),
                                const SizedBox(height: 22),
                                Row(
                                  children: [
                                    metric('Borrowed', borrowed),
                                    metric('Paid', paid),
                                    metric('Remaining', remaining),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Text(
                                      'Repayment progress',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${standardMoney(paid)} of ${standardMoney(total)} paid',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(value: progress),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Payment History',
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
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                standardMoney(
                                  payment['amount_centavos']! as int,
                                ),
                                style: Theme.of(dialog).textTheme.titleMedium,
                              ),
                            ),
                            Text(
                              PaymentMethod.fromDatabase(
                                payment['payment_method'],
                              ).label,
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${when == null ? 'Date unavailable' : MaterialLocalizations.of(dialog).formatMediumDate(when)}${when == null ? '' : ' • ${MaterialLocalizations.of(dialog).formatTimeOfDay(TimeOfDay.fromDateTime(when))}'} • ${reversed ? 'Reversed' : 'Completed'}${reversed ? '\nReason: ${payment['reversal_reason'] ?? 'Not recorded'}' : ''}',
                        ),
                        isThreeLine: reversed,
                        trailing: reversed
                            ? const Icon(Icons.history_outlined)
                            : PopupMenuButton<String>(
                                tooltip: 'Payment actions',
                                onSelected: (_) {
                                  paymentToCancel = payment;
                                  Navigator.pop(dialog);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'reverse',
                                    child: Text('Reverse Payment'),
                                  ),
                                ],
                                icon: const Icon(Icons.more_horiz),
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
          if (loan['status'] == 'ACTIVE')
            FilledButton.icon(
              onPressed: () async {
                recordPayment = true;
                Navigator.pop(dialog);
              },
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Record Payment'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (paymentToCancel != null) {
      await _cancelPayment(paymentToCancel!);
    } else if (recordPayment) {
      await _pay(loan);
    }
  }

  Future<void> _cancelPayment(Map<String, Object?> payment) async {
    final reason = TextEditingController();
    final pin = TextEditingController();
    var busy = false;
    var cancelled = false;
    String? error;
    await _showLoanDialog<void>(
      (dialog) => StatefulBuilder(
        builder: (_, update) => AlertDialog(
          scrollable: true,
          title: const Text('Reverse Payment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This restores ${standardMoney(payment['amount_centavos']! as int)} to the loan balance. The original payment remains in history as reversed.',
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
                        cancelled = true;
                        if (dialog.mounted) Navigator.pop(dialog);
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
              child: const Text('Reverse Payment'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    pin.dispose();
    if (cancelled) _reload();
  }

  Future<void> _pay(Map<String, Object?> loan) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    var method = PaymentMethod.cash;
    var busy = false;
    String? error;
    final saved = await _showLoanDialog<bool>(
      (d) => StatefulBuilder(
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
    if (saved == true) _reload();
  }

  Future<void> _addLender() async {
    if (!await widget.access.allows(ProFeature.fiveSixLoanManagement)) {
      return;
    }
    if (!mounted) return;
    final c = TextEditingController();
    String? error;
    var busy = false;
    final saved = await _showLoanDialog<bool>(
      (x) => StatefulBuilder(
        builder: (_, update) => AlertDialog(
          scrollable: true,
          title: const Text('Add Lender'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: c,
                autofocus: false,
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
              onPressed: busy
                  ? null
                  : () async {
                      if (c.text.trim().isEmpty) {
                        update(() => error = 'Enter a lender name.');
                        return;
                      }
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.repository.createLender(c.text);
                        if (x.mounted) Navigator.pop(x, true);
                      } catch (_) {
                        if (x.mounted) {
                          update(
                            () => error =
                                'Could not save lender. Please try again.',
                          );
                        }
                      } finally {
                        if (x.mounted) update(() => busy = false);
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    if (saved == true) _reload();
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
    final saved = await _showLoanDialog<bool>(
      (x) => StatefulBuilder(
        builder: (_, set) => AlertDialog(
          scrollable: true,
          title: const Text('Add 5/6 Loan'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(x).colorScheme.error),
                  ),
                Text(
                  'Lender and source',
                  style: Theme.of(x).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 14),
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
                const SizedBox(height: 6),
                Text(
                  source == 'NEW' ? 'Record money your store receives today.' : 'Track a loan you received earlier without adding money to today’s totals.',
                  style: Theme.of(x).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                Text('Loan amounts', style: Theme.of(x).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: borrowed,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount borrowed',
                    prefixText: '₱ ',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: agreed,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Total to repay',
                    prefixText: '₱ ',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Collection plan',
                  style: Theme.of(x).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 14),
                TextField(
                  controller: scheduled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Expected payment (optional)',
                    prefixText: '₱ ',
                  ),
                ),
                const SizedBox(height: 14),
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
                if (source == 'NEW') const SizedBox(height: 8),
                if (source == 'NEW')
                  Text(
                    'Choose where the borrowed money was received. This affects today’s cash or wallet record.',
                    style: Theme.of(x).textTheme.bodySmall,
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
                          () => error = 'Enter valid positive amounts. Total to repay must be at least the amount borrowed; use at most two decimals.',
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
                        if (x.mounted) Navigator.pop(x, true);
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
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('5/6 Loan Management')),
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
            title: '5/6 Loan Management',
            description: 'Track lender balances, daily or weekly collections, and payment history in one clear place.',
            icon: Icons.account_balance_outlined,
          );
        }
        return FutureBuilder<List<Map<String, Object?>>>(
          future: _loans,
          builder: (_, s) => s.hasError
              ? const Center(
                  child: Text('Could not load loans. Reopen this section.'),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Know what you owe and track every payment clearly.',
                                  style: Theme.of(c).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Keep lenders, repayment plans, and payment history in one place.',
                                  style: Theme.of(c).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            onPressed: _addLender,
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Add Lender'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: _add,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Loan'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                      child: Row(
                        children: [
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('Active'),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('Completed'),
                              ),
                            ],
                            selected: {completed},
                            onSelectionChanged: (selection) {
                              completed = selection.single;
                              _reload();
                            },
                          ),
                          const Spacer(),
                          if (s.hasData)
                            Text(
                              '${s.data!.length} ${completed ? 'completed' : 'active'} ${s.data!.length == 1 ? 'loan' : 'loans'}',
                            ),
                        ],
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
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              children: s.data!.map((r) {
                                final borrowed =
                                    r['borrowed_amount_centavos']! as int;
                                final agreed =
                                    r['agreed_repayment_centavos']! as int;
                                final paid = r['paid_centavos']! as int;
                                final remaining = (agreed - paid).clamp(
                                  0,
                                  agreed,
                                );
                                final progress = agreed == 0
                                    ? 0.0
                                    : (paid / agreed).clamp(0.0, 1.0);
                                return Card(
                                  child: InkWell(
                                    onTap: () => _details(r),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(22),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const CircleAvatar(
                                                child: Icon(
                                                  Icons
                                                      .account_balance_outlined,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      r['lender_name']!
                                                          as String,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Theme.of(c)
                                                          .textTheme
                                                          .titleLarge,
                                                    ),
                                                    Text(
                                                      '${r['collection_frequency'] == 'DAILY' ? 'Daily' : 'Weekly'} collection • ${r['source_kind'] == 'NEW' ? 'Received in store' : 'Existing loan'}',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (completed)
                                                const Chip(
                                                  label: Text('Completed'),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 22),
                                          Wrap(
                                            spacing: 36,
                                            runSpacing: 12,
                                            children: [
                                              _loanMetric(
                                                c,
                                                'Borrowed',
                                                borrowed,
                                              ),
                                              _loanMetric(
                                                c,
                                                'Total to Repay',
                                                agreed,
                                              ),
                                              _loanMetric(c, 'Paid', paid),
                                            ],
                                          ),
                                          const SizedBox(height: 18),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: LinearProgressIndicator(
                                                  value: progress,
                                                ),
                                              ),
                                              const SizedBox(width: 18),
                                              Text(
                                                '${standardMoney(paid)} of ${standardMoney(agreed)} paid',
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 18),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    completed
                                                        ? 'Completed'
                                                        : 'Remaining',
                                                    style: Theme.of(c)
                                                        .textTheme
                                                        .bodyMedium,
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    standardMoney(remaining),
                                                    style: Theme.of(c)
                                                        .textTheme
                                                        .headlineSmall,
                                                  ),
                                                ],
                                              ),
                                              const Spacer(),
                                              Text(
                                                'Tap for details',
                                                style: Theme.of(c)
                                                    .textTheme
                                                    .bodyMedium,
                                              ),
                                              const Icon(Icons.chevron_right),
                                            ],
                                          ),
                                        ],
                                      ),
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
