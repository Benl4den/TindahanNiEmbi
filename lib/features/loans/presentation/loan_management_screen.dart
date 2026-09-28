import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../models/payment_method.dart';
import '../../../repositories/loan_repository.dart';
import '../../../services/feature_access_service.dart';
import '../../../services/auth_service.dart';
import '../../../widgets/pro_feature_preview.dart';
import '../../../widgets/feature_access_builder.dart';

typedef _LoanPageData = ({
  List<Map<String, Object?>> lenders,
  List<Map<String, Object?>> loans,
});
typedef _LenderEntry = ({
  Map<String, Object?> lender,
  Map<String, Object?>? loan,
});

int? _moneyCentavos(String input) => parseMoneyCentavos(input);

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
  String _search = '';
  String _sort = 'Recent';
  late Future<_LoanPageData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_LoanPageData> _load() async => (
    lenders: await widget.repository.lenders(),
    loans: await widget.repository.loans(completed: completed),
  );

  void _reload() {
    if (mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  List<_LenderEntry> _visibleEntries(_LoanPageData data) {
    final visible = <_LenderEntry>[];
    for (final lender in data.lenders) {
      final name = lender['name']! as String;
      final person = lender['contact_person'] as String? ?? '';
      if (!name.toLowerCase().contains(_search) &&
          !person.toLowerCase().contains(_search)) {
        continue;
      }
      final loans = data.loans.where(
        (loan) => loan['lender_id'] == lender['id'],
      );
      if (loans.isEmpty && !completed) {
        visible.add((lender: lender, loan: null));
      }
      for (final loan in loans) {
        visible.add((lender: lender, loan: loan));
      }
    }
    if (_sort == 'Name') {
      visible.sort(
        (a, b) => (a.lender['name']! as String).toLowerCase().compareTo(
          (b.lender['name']! as String).toLowerCase(),
        ),
      );
    } else if (_sort == 'Remaining') {
      int remaining(_LenderEntry entry) => entry.loan == null
          ? 0
          : (entry.loan!['agreed_repayment_centavos']! as int) -
                (entry.loan!['paid_centavos']! as int);
      visible.sort((a, b) => remaining(b).compareTo(remaining(a)));
    } else {
      String date(_LenderEntry entry) =>
          (entry.loan?['start_date'] ?? entry.lender['created_at'])
              as String? ??
          '';
      visible.sort((a, b) => date(b).compareTo(date(a)));
    }
    return visible;
  }

  String _nextCollectionLabel(List<Map<String, Object?>> loans) {
    DateTime? next;
    int? amount;
    final today = DateUtils.dateOnly(DateTime.now());
    for (final loan in loans) {
      final rawDate = loan['first_collection_date'] as String?;
      final scheduled = loan['scheduled_amount_centavos'] as int?;
      final first = rawDate == null
          ? null
          : DateTime.tryParse(rawDate)?.toLocal();
      if (first == null || scheduled == null) continue;
      final remaining =
          ((loan['agreed_repayment_centavos']! as int) -
                  (loan['paid_centavos']! as int))
              .clamp(0, 1 << 62);
      if (remaining == 0) continue;
      final step = loan['collection_frequency'] == 'WEEKLY' ? 7 : 1;
      var due = DateUtils.dateOnly(first);
      if (due.isBefore(today)) {
        final elapsed = today.difference(due).inDays;
        due = due.add(Duration(days: ((elapsed + step - 1) ~/ step) * step));
      }
      if (next == null || due.isBefore(next)) {
        next = due;
        amount = scheduled.clamp(0, remaining);
      }
    }
    if (next == null || amount == null) return 'Not scheduled';
    final when = DateUtils.isSameDay(next, today)
        ? 'Today'
        : '${next.month}/${next.day}/${next.year}';
    return '${standardMoney(amount)} • $when';
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
    var correctBorrowed = false;
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
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  alignment: WrapAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Repayment progress',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
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
          if (widget.repository.actorRole == 'OWNER' &&
              (loan['source_kind'] != 'NEW' ||
                  loan['received_payment_method'] == 'CASH'))
            OutlinedButton.icon(
              onPressed: () {
                correctBorrowed = true;
                Navigator.pop(dialog);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Loan'),
            ),
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
    } else if (correctBorrowed) {
      await _correctBorrowedAmount(loan);
    } else if (recordPayment) {
      await _pay(loan);
    }
  }

  Future<void> _correctBorrowedAmount(Map<String, Object?> loan) async {
    final oldBorrowed = loan['borrowed_amount_centavos']! as int;
    final agreed = loan['agreed_repayment_centavos']! as int;
    final amount = TextEditingController(
      text:
          '${oldBorrowed ~/ 100}.${(oldBorrowed % 100).toString().padLeft(2, '0')}',
    );
    final reason = TextEditingController();
    final pin = TextEditingController();
    var busy = false;
    var corrected = false;
    String? error;
    var submitted = false;
    String? pinError;
    await _showLoanDialog<void>(
      (dialog) => StatefulBuilder(
        builder: (_, update) => AlertDialog(
          scrollable: true,
          title: const Text('Correct Borrowed Amount'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Currently recorded: ${standardMoney(oldBorrowed)}'),
                Text('Total to repay: ${standardMoney(agreed)}'),
                Text(
                  'Payments already made: ${standardMoney(loan['paid_centavos']! as int)}',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: amount,
                  onChanged: (_) => update(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Correct amount borrowed',
                    prefixText: '₱ ',
                    errorText:
                        submitted &&
                            (_moneyCentavos(amount.text) == null ||
                                _moneyCentavos(amount.text)! <= 0 ||
                                _moneyCentavos(amount.text)! > agreed ||
                                _moneyCentavos(amount.text)! == oldBorrowed)
                        ? 'Enter a different amount from ₱0.01 to ${standardMoney(agreed)}.'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  onChanged: (_) => update(() {}),
                  decoration: InputDecoration(
                    labelText: 'Reason for correction',
                    errorText: submitted && reason.text.trim().isEmpty
                        ? 'Enter a reason.'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pin,
                  onChanged: (_) => update(() => pinError = null),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Owner PIN',
                    errorText:
                        pinError ??
                        (submitted && pin.text.trim().isEmpty
                            ? 'Enter the Owner PIN.'
                            : null),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  loan['source_kind'] == 'NEW'
                      ? 'This also corrects the original cash received total. Payments and total to repay stay unchanged. Closed days and wallet-funded loans cannot be corrected here.'
                      : 'Payments and total to repay stay unchanged. The original amount and correction reason remain in activity history.',
                  style: Theme.of(dialog).textTheme.bodySmall,
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(dialog).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (busy) return;
                      final cents = _moneyCentavos(amount.text);
                      if (cents == null ||
                          cents <= 0 ||
                          cents > agreed ||
                          cents == oldBorrowed ||
                          reason.text.trim().isEmpty ||
                          pin.text.trim().isEmpty) {
                        update(() => submitted = true);
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
                          if (dialog.mounted) {
                            update(() => pinError = 'Incorrect Owner PIN.');
                          }
                          return;
                        }
                        await widget.repository.correctBorrowedAmount(
                          loanId: loan['id']! as int,
                          borrowed: cents,
                          reason: reason.text,
                          ownerPinAuthorized: true,
                        );
                        corrected = true;
                        if (dialog.mounted) Navigator.pop(dialog);
                      } catch (e) {
                        if (dialog.mounted) {
                          update(
                            () => error = e is StateError
                                ? e.message
                                : e is ArgumentError
                                ? e.message?.toString() ?? 'Check the amount.'
                                : 'Could not correct the loan. Please try again.',
                          );
                        }
                      } finally {
                        if (dialog.mounted) update(() => busy = false);
                      }
                    },
              child: const Text('Save Correction'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    reason.dispose();
    pin.dispose();
    if (corrected) _reload();
  }

  Future<void> _cancelPayment(Map<String, Object?> payment) async {
    final reason = TextEditingController();
    final pin = TextEditingController();
    var busy = false;
    var cancelled = false;
    String? error;
    var submitted = false;
    String? pinError;
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
                onChanged: (_) => update(() {}),
                decoration: InputDecoration(
                  labelText: 'Reason (required)',
                  errorText: submitted && reason.text.trim().isEmpty
                      ? 'Enter a reason.'
                      : null,
                ),
              ),
              TextField(
                controller: pin,
                onChanged: (_) => update(() => pinError = null),
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Owner PIN',
                  errorText:
                      pinError ??
                      (submitted && pin.text.trim().isEmpty
                          ? 'Enter the Owner PIN.'
                          : null),
                ),
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
                        update(() => submitted = true);
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
                          if (dialog.mounted) {
                            update(() => pinError = 'Incorrect Owner PIN.');
                          }
                          return;
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
    var submitted = false;
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
                  onChanged: (_) => setDialog(() {}),
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Payment amount',
                    prefixText: '₱ ',
                    errorText:
                        submitted &&
                            (_moneyCentavos(amount.text) == null ||
                                _moneyCentavos(amount.text)! <= 0 ||
                                _moneyCentavos(amount.text)! >
                                    (loan['agreed_repayment_centavos']!
                                            as int) -
                                        (loan['paid_centavos']! as int))
                        ? 'Enter ₱0.01 to ${standardMoney((loan['agreed_repayment_centavos']! as int) - (loan['paid_centavos']! as int))}.'
                        : null,
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
                        setDialog(() => submitted = true);
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
    final name = TextEditingController();
    final person = TextEditingController();
    final contact = TextEditingController();
    final notes = TextEditingController();
    var frequency = 'DAILY';
    var method = 'COLLECTOR_VISITS';
    String? error;
    var busy = false;
    var submitted = false;
    final saved = await _showLoanDialog<bool>(
      (x) => StatefulBuilder(
        builder: (_, update) => AlertDialog(
          scrollable: true,
          title: Row(
            children: [
              const Expanded(child: Text('Add Lender')),
              IconButton(
                tooltip: 'Close',
                onPressed: busy ? null : () => Navigator.pop(x),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  onChanged: (_) => update(() {}),
                  decoration: InputDecoration(
                    labelText: 'Lender Name *',
                    errorText: submitted && name.text.trim().isEmpty
                        ? 'Enter a lender name.'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: frequency,
                  decoration: const InputDecoration(
                    labelText: 'Collection Schedule',
                  ),
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
                  onChanged: busy
                      ? null
                      : (value) => update(() => frequency = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Collection Method',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'COLLECTOR_VISITS',
                      child: Text('Collector visits store'),
                    ),
                    DropdownMenuItem(
                      value: 'OWNER_PAYS',
                      child: Text('Owner pays lender'),
                    ),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => update(() => method = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: person,
                  decoration: const InputDecoration(
                    labelText: 'Contact Person (Optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contact,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact Number (Optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(x).colorScheme.error),
                  ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: busy ? null : () => Navigator.pop(x),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        update(() => submitted = true);
                        return;
                      }
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await widget.repository.createLender(
                          name.text,
                          frequency: frequency,
                          method: method,
                          contactPerson: person.text,
                          contact: contact.text,
                          notes: notes.text,
                        );
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
              child: const Text('Save Lender'),
            ),
          ],
        ),
      ),
    );
    final addedName = name.text.trim();
    name.dispose();
    person.dispose();
    contact.dispose();
    notes.dispose();
    if (saved == true && mounted) {
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✓ $addedName added to your lenders.')),
      );
    }
  }

  Future<void> _add({int? lenderId}) async {
    if (!await widget.access.allows(ProFeature.fiveSixLoanManagement)) return;
    final lenders = await widget.repository.lenders();
    if (!mounted) return;
    if (lenders.isEmpty) {
      await _addLender();
      return;
    }
    final selected = lenders.firstWhere(
      (row) => row['id'] == lenderId,
      orElse: () => lenders.first,
    );
    int lender = selected['id']! as int;
    final borrowed = TextEditingController(),
        agreed = TextEditingController(),
        scheduled = TextEditingController();
    var source = 'NEW',
        freq = selected['collection_frequency'] == 'WEEKLY'
            ? 'WEEKLY'
            : 'DAILY',
        method = PaymentMethod.cash;
    var busy = false;
    String? error;
    var submitted = false;
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
                  onChanged: (v) => set(() {
                    lender = v!;
                    final profile = lenders.firstWhere((row) => row['id'] == v);
                    freq = profile['collection_frequency'] == 'WEEKLY'
                        ? 'WEEKLY'
                        : 'DAILY';
                  }),
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
                  onChanged: (_) => set(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount borrowed',
                    prefixText: '₱ ',
                    errorText:
                        submitted &&
                            (_moneyCentavos(borrowed.text) == null ||
                                _moneyCentavos(borrowed.text)! <= 0)
                        ? 'Enter an amount greater than ₱0 (up to two decimals).'
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: agreed,
                  onChanged: (_) => set(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Total to repay',
                    prefixText: '₱ ',
                    errorText:
                        submitted &&
                            (_moneyCentavos(agreed.text) == null ||
                                _moneyCentavos(agreed.text)! <= 0 ||
                                (_moneyCentavos(borrowed.text) != null &&
                                    _moneyCentavos(agreed.text)! <
                                        _moneyCentavos(borrowed.text)!))
                        ? 'Enter a valid amount at least equal to the amount borrowed.'
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Collection plan',
                  style: Theme.of(x).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('loan-frequency-$lender'),
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
                  onChanged: (_) => set(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Expected payment (optional)',
                    prefixText: '₱ ',
                    errorText:
                        submitted &&
                            scheduled.text.trim().isNotEmpty &&
                            (_moneyCentavos(scheduled.text) == null ||
                                _moneyCentavos(scheduled.text)! <= 0)
                        ? 'Enter a valid amount or leave this blank.'
                        : null,
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
                      if (busy) return;
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
                        set(() => submitted = true);
                        return;
                      }
                      set(() {
                        busy = true;
                        error = null;
                      });
                      if (agreedCents > borrowedCents * 3) {
                        final confirmed = await showDialog<bool>(
                          context: x,
                          builder: (warningContext) => AlertDialog(
                            title: const Text('Check these loan amounts'),
                            content: Text(
                              'Amount borrowed: ${standardMoney(borrowedCents)}\n'
                              'Total to repay: ${standardMoney(agreedCents)}\n\n'
                              'The repayment is more than three times the borrowed amount. Check for a missing digit before saving.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(warningContext, false),
                                child: const Text('Edit Amounts'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(warningContext, true),
                                child: const Text('Amounts Are Correct'),
                              ),
                            ],
                          ),
                        );
                        if (!x.mounted) return;
                        if (confirmed != true) {
                          set(() => busy = false);
                          return;
                        }
                      }
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

  String _schedule(Map<String, Object?> lender, Map<String, Object?>? loan) {
    final value =
        loan?['collection_frequency'] ?? lender['collection_frequency'];
    return switch (value) {
      'WEEKLY' => 'Weekly collection',
      _ => 'Daily collection',
    };
  }

  String _method(Map<String, Object?> lender) =>
      switch (lender['collection_method']) {
        'OWNER_PAYS' => 'Owner pays lender',
        'OTHER' => 'Other',
        _ => 'Collector visits store',
      };

  Widget _overviewMetric(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview(BuildContext context, List<Map<String, Object?>> loans) {
    final scheme = Theme.of(context).colorScheme;
    final borrowed = loans.fold<int>(
      0,
      (sum, loan) => sum + (loan['borrowed_amount_centavos']! as int),
    );
    final remaining = loans.fold<int>(
      0,
      (sum, loan) =>
          sum +
          ((loan['agreed_repayment_centavos']! as int) -
                  (loan['paid_centavos']! as int))
              .clamp(0, 1 << 62),
    );
    final metrics = [
      _overviewMetric(
        context,
        'Total Borrowed',
        standardMoney(borrowed),
        Icons.account_balance_outlined,
        scheme.primary,
      ),
      _overviewMetric(
        context,
        'Remaining Balance',
        standardMoney(remaining),
        Icons.bar_chart_outlined,
        scheme.error,
      ),
      _overviewMetric(
        context,
        'Next Collection',
        _nextCollectionLabel(loans),
        Icons.calendar_month_outlined,
        scheme.tertiary,
      ),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: .07),
          scheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Loan Overview',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text('As of today', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (_, size) {
              final columns = size.maxWidth >= 720
                  ? 3
                  : size.maxWidth >= 450
                  ? 2
                  : 1;
              final width = (size.maxWidth - 10 * (columns - 1)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: metrics
                    .map((metric) => SizedBox(width: width, child: metric))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _lenderCard(BuildContext context, _LenderEntry entry) {
    final lender = entry.lender;
    final loan = entry.loan;
    final scheme = Theme.of(context).colorScheme;
    final name = lender['name']! as String;
    final borrowed = loan?['borrowed_amount_centavos'] as int? ?? 0;
    final agreed = loan?['agreed_repayment_centavos'] as int? ?? 0;
    final paid = loan?['paid_centavos'] as int? ?? 0;
    final remaining = (agreed - paid).clamp(0, agreed);
    final progress = agreed <= 0 ? 0.0 : (paid / agreed).clamp(0.0, 1.0);
    final lenderId = lender['id']! as int;
    void open() {
      if (loan == null) {
        _add(lenderId: lenderId);
      } else {
        _details(loan);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primary.withValues(alpha: .14),
                    child: Icon(
                      Icons.account_balance_outlined,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${_schedule(lender, loan)} • ${_method(lender)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: loan == null
                          ? scheme.secondaryContainer
                          : scheme.primary.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      loan == null
                          ? 'No active loan'
                          : completed
                          ? 'Completed'
                          : 'Active',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: loan == null
                            ? scheme.onSecondaryContainer
                            : scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Lender actions',
                    onSelected: (_) => open(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'open',
                        child: Text(loan == null ? 'Add Loan' : 'View Loan'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (loan == null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: LayoutBuilder(
                    builder: (_, size) => Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          color: scheme.onSecondaryContainer,
                          size: 30,
                        ),
                        SizedBox(
                          width: size.maxWidth >= 580
                              ? size.maxWidth - 195
                              : size.maxWidth - 48,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No active loan yet',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const Text(
                                'Add a loan to start tracking collections for this lender.',
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _add(lenderId: lenderId),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Loan'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                LayoutBuilder(
                  builder: (_, size) {
                    final columns = size.maxWidth >= 660 ? 4 : 2;
                    final width =
                        (size.maxWidth - 12 * (columns - 1)) / columns;
                    Widget value(
                      String label,
                      int amount, {
                      bool prominent = false,
                    }) => SizedBox(
                      width: width,
                      child: prominent
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  standardMoney(amount),
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            )
                          : _loanMetric(context, label, amount),
                    );
                    return Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        value('Borrowed', borrowed),
                        value('Total to Repay', agreed),
                        value('Paid', paid),
                        value('Remaining', remaining, prominent: true),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '${standardMoney(paid)} of ${standardMoney(agreed)} paid',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _proPage(BuildContext context) => FutureBuilder<_LoanPageData>(
    future: _data,
    builder: (_, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: Text('Could not load lenders and loans. Reopen this section.'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      final entries = _visibleEntries(data);
      return Column(
        children: [
          if (!completed) _overview(context, data.loans),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _addLender,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add Lender'),
                ),
                FilledButton.icon(
                  onPressed: () => _add(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Loan'),
                ),
                SizedBox(
                  width: 205,
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search lenders...',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        setState(() => _search = value.trim().toLowerCase()),
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Active')),
                    ButtonSegment(value: true, label: Text('Completed')),
                  ],
                  selected: {completed},
                  onSelectionChanged: (selection) {
                    completed = selection.single;
                    _reload();
                  },
                ),
                DropdownButton<String>(
                  value: _sort,
                  items: const [
                    DropdownMenuItem(
                      value: 'Recent',
                      child: Text('Sort: Recent'),
                    ),
                    DropdownMenuItem(value: 'Name', child: Text('Sort: Name')),
                    DropdownMenuItem(
                      value: 'Remaining',
                      child: Text('Sort: Remaining'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _sort = value ?? 'Recent'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lenders & Loans',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${data.lenders.length} lenders • ${data.loans.length} ${completed ? 'completed' : 'active'} loans',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      _search.isNotEmpty
                          ? 'No lenders match your search.'
                          : completed
                          ? 'No completed loans yet.'
                          : 'No lenders yet. Add a lender to get started.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                    itemCount: entries.length,
                    itemBuilder: (_, index) =>
                        _lenderCard(context, entries[index]),
                  ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 70,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('5/6 Loan Management'),
          Text(
            'Manage your lenders, loans, and collections.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
    body: FeatureAccessBuilder(
      access: widget.access,
      feature: ProFeature.fiveSixLoanManagement,
      builder: (_, allowed) => allowed
          ? _proPage(context)
          : const ProFeaturePreview(
              title: 'Manage your 5/6 loans in one place',
              description: 'Track the money you borrowed, scheduled collections, remaining balance, and every payment you make.',
              icon: Icons.account_balance_outlined,
              metrics: [
                'Total Borrowed',
                'Remaining Balance',
                'Next Collection',
              ],
              benefits: [
                'Manage lenders',
                'Daily or weekly collection schedules',
                'Record partial and full payments',
                'Track remaining balances',
                'View complete payment history',
              ],
            ),
    ),
  );
}
