import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../repositories/payment_accounting_repository.dart';
import '../../../repositories/gcash_service_repository.dart';
import '../../../services/auth_service.dart';
import '../../../services/app_refresh_controller.dart';

class GCashScreen extends StatefulWidget {
  const GCashScreen({
    super.key,
    required this.repository,
    required this.services,
    required this.auth,
  });
  final PaymentAccountingRepository repository;
  final GCashServiceRepository services;
  final AuthService auth;

  @override
  State<GCashScreen> createState() => _GCashScreenState();
}

class _GCashScreenState extends State<GCashScreen> {
  late Future<(GCashSummary, List<GCashLedgerEntry>)> data;

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

  void _changed() {
    if (mounted) setState(_reload);
  }

  void _reload() {
    data =
        Future.wait<Object>([
          widget.repository.summary(),
          widget.repository.history(),
        ]).then(
          (values) =>
              (values[0] as GCashSummary, values[1] as List<GCashLedgerEntry>),
        );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GCash'),
          Text(
            'Digital wallet activity and balance',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
          ),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _adjust,
      icon: const Icon(Icons.add_card),
      label: const Text('Add Adjustment'),
    ),
    body: FutureBuilder<(GCashSummary, List<GCashLedgerEntry>)>(
      future: data,
      builder: (_, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('GCash records could not be loaded.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (summary, entries) = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => setState(_reload),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Colors.blue.shade700,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CURRENT GCASH BALANCE',
                      style: TextStyle(color: Colors.white70),
                    ),
                    Text(
                      standardMoney(summary.balance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric('Today’s Money In', summary.todayIn, Colors.green),
                  _metric('Today’s Money Out', summary.todayOut, Colors.red),
                  _metric(
                    'Today’s Net Change',
                    summary.todayNet,
                    summary.todayNet < 0 ? Colors.red : Colors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'GCash Services',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => _service('CASH_IN'),
                    icon: const Icon(Icons.call_made),
                    label: const Text('Cash-In'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _service('CASH_OUT'),
                    icon: const Icon(Icons.call_received),
                    label: const Text('Cash-Out'),
                  ),
                ],
              ),
              FutureBuilder<List<GCashServiceTransaction>>(
                future: widget.services.recent(limit: 8),
                builder: (_, services) =>
                    services.hasData && services.data!.isNotEmpty
                    ? Column(
                        children: services.data!
                            .map(
                              (service) => Card(
                                child: ListTile(
                                  onTap: service.status == 'POSTED'
                                      ? () => _reverseService(service)
                                      : null,
                                  leading: Icon(
                                    service.type == 'CASH_IN'
                                        ? Icons.call_made
                                        : Icons.call_received,
                                  ),
                                  title: Text(
                                    'GCash ${service.type == 'CASH_IN' ? 'Cash-In' : 'Cash-Out'} • ${service.reference}',
                                  ),
                                  subtitle: Text(
                                    'Principal ${standardMoney(service.principalCentavos)} • Fee ${standardMoney(service.feeCentavos)}',
                                  ),
                                  trailing: Text(
                                    '${service.gcashChangeCentavos >= 0 ? '+' : '-'}${standardMoney(service.gcashChangeCentavos.abs())}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),
              Text(
                'Transaction History',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No GCash activity yet.')),
                  ),
                )
              else
                ...entries.map(
                  (entry) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: entry.amountChangeCentavos > 0
                            ? Colors.green.shade50
                            : Colors.red.shade50,
                        child: Icon(
                          entry.amountChangeCentavos > 0
                              ? Icons.south_west
                              : Icons.north_east,
                          color: entry.amountChangeCentavos > 0
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                      title: Text(_label(entry.type)),
                      subtitle: Text(
                        '${_when(entry.occurredAt.toLocal())}'
                        '${entry.gcashReference == null ? '' : '\nReference: ${entry.gcashReference}'}'
                        '${entry.notes == null ? '' : '\n${entry.notes}'}',
                      ),
                      trailing: Text(
                        '${entry.amountChangeCentavos > 0 ? '+' : '-'}${standardMoney(entry.amountChangeCentavos.abs())}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: entry.amountChangeCentavos > 0
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 90),
            ],
          ),
        );
      },
    ),
  );

  Widget _metric(String label, int amount, Color color) => SizedBox(
    width: 230,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Text(
              standardMoney(amount),
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  String _label(String type) => switch (type) {
    'SALE' => 'Sale',
    'UTANG_PAYMENT' => 'UTANG Payment',
    'EXPENSE' => 'Expense',
    'CONSIGNOR_REMITTANCE' => 'Consignor Remittance',
    'OPENING_BALANCE' => 'Opening Balance',
    'ADJUSTMENT_IN' => 'Adjustment In',
    'ADJUSTMENT_OUT' => 'Adjustment Out',
    'REVERSAL' => 'Reversal',
    _ => type,
  };

  String _when(DateTime value) =>
      '${MaterialLocalizations.of(context).formatMediumDate(value)} • ${TimeOfDay.fromDateTime(value).format(context)}';

  Future<void> _adjust() async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final reference = TextEditingController();
    final pin = TextEditingController();
    var type = 'ADJUSTMENT_IN', busy = false, error = '';
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('GCash Adjustment'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'OPENING_BALANCE',
                        child: Text('Opening Balance'),
                      ),
                      DropdownMenuItem(
                        value: 'ADJUSTMENT_IN',
                        child: Text('Adjustment In'),
                      ),
                      DropdownMenuItem(
                        value: 'ADJUSTMENT_OUT',
                        child: Text('Adjustment Out'),
                      ),
                    ],
                    onChanged: busy ? null : (value) => type = value!,
                  ),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₱ ',
                    ),
                  ),
                  TextField(
                    controller: reason,
                    decoration: const InputDecoration(
                      labelText: 'Reason (required)',
                    ),
                  ),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'GCash Reference (optional)',
                    ),
                  ),
                  TextField(
                    controller: pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Owner PIN'),
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final cents = ((double.tryParse(amount.text) ?? 0) * 100)
                          .round();
                      setDialog(() {
                        busy = true;
                        error = '';
                      });
                      try {
                        final role = await widget.auth.verify(pin.text);
                        if (role != UserRole.owner) {
                          throw const PaymentAccountingException(
                            'Incorrect Owner PIN.',
                          );
                        }
                        await widget.repository.addManual(
                          type: type,
                          amountCentavos: cents,
                          reason: reason.text,
                          gcashReference: reference.text,
                          ownerPinAuthorized: true,
                        );
                        if (dialog.mounted) Navigator.pop(dialog, true);
                      } catch (exception) {
                        if (dialog.mounted) {
                          setDialog(() {
                            busy = false;
                            error = exception is PaymentAccountingException
                                ? exception.message
                                : 'Adjustment could not be saved.';
                          });
                        }
                      }
                    },
              child: Text(busy ? 'Saving…' : 'Save Adjustment'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    reason.dispose();
    reference.dispose();
    pin.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _service(String type) async {
    final principal = TextEditingController();
    final fee = TextEditingController(text: '0');
    final reference = TextEditingController();
    final notes = TextEditingController();
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: Text(type == 'CASH_IN' ? 'GCash Cash-In' : 'GCash Cash-Out'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: principal,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Principal Amount',
                      prefixText: '₱ ',
                    ),
                  ),
                  TextField(
                    controller: fee,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Service Fee',
                      prefixText: '₱ ',
                    ),
                  ),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'GCash Reference (optional)',
                    ),
                  ),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                  if (type == 'CASH_OUT')
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Confirm that there is enough physical cash in the drawer before continuing.',
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                int cents(String value) =>
                    ((double.tryParse(value.trim()) ?? -1) * 100).round();
                final p = cents(principal.text), f = cents(fee.text);
                if (p <= 0 || f < 0) {
                  setDialog(
                    () => error = 'Enter a valid principal and service fee.',
                  );
                  return;
                }
                final total = p + f;
                final review = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (reviewContext) => AlertDialog(
                    title: const Text('Review GCash Service'),
                    content: Text(
                      type == 'CASH_IN'
                          ? 'Principal: ${standardMoney(p)}\nService Fee: ${standardMoney(f)}\nCustomer Pays Cash: ${standardMoney(total)}\nGCash Sent: ${standardMoney(p)}'
                          : 'Principal: ${standardMoney(p)}\nService Fee: ${standardMoney(f)}\nCustomer Sends GCash: ${standardMoney(total)}\nCash Given: ${standardMoney(p)}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(reviewContext, false),
                        child: const Text('Back'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(reviewContext, true),
                        child: const Text('Confirm'),
                      ),
                    ],
                  ),
                );
                if (review != true) return;
                try {
                  await widget.services.record(
                    type: type,
                    principalCentavos: p,
                    feeCentavos: f,
                    gcashReference: reference.text,
                    notes: notes.text,
                    physicalCashAvailabilityAcknowledged: type == 'CASH_OUT',
                  );
                  if (context.mounted) Navigator.pop(dialog, true);
                } catch (e) {
                  setDialog(() => error = e.toString());
                }
              },
              child: const Text('Review'),
            ),
          ],
        ),
      ),
    );
    principal.dispose();
    fee.dispose();
    reference.dispose();
    notes.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _reverseService(GCashServiceTransaction service) async {
    final reason = TextEditingController();
    final pin = TextEditingController();
    String? error;
    final reversed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Reverse GCash Service'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${service.reference} • ${service.type == 'CASH_IN' ? 'Cash-In' : 'Cash-Out'}',
                ),
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
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  if (await widget.auth.verify(pin.text) != UserRole.owner) {
                    throw const GCashServiceException('Incorrect Owner PIN.');
                  }
                  await widget.services.reverse(
                    service.id,
                    reason: reason.text,
                    ownerPinAuthorized: true,
                  );
                  if (dialog.mounted) Navigator.pop(dialog, true);
                } catch (e) {
                  setDialog(() => error = e.toString());
                }
              },
              child: const Text('Reverse'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    pin.dispose();
    if (reversed == true && mounted) setState(_reload);
  }
}
