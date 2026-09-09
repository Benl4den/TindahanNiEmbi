import 'package:flutter/material.dart';

import '../../../widgets/day_history.dart';

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
  late Future<int> feeTotal;
  late Future<List<GCashServiceTransaction>> serviceHistory;
  int historyLimit = 100;

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
    // Repository commits notify synchronously.  A service commit can happen
    // while its review dialog is still being popped; rebuilding inherited
    // widgets at that exact moment causes Flutter's _dependents assertion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_reload);
    });
  }

  void _reload() {
    feeTotal = widget.services.totalFeeIncome();
    serviceHistory = widget.services.recent(limit: historyLimit);
    data =
        Future.wait<Object>([
          widget.repository.summary(),
          widget.repository.history(limit: historyLimit),
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
          return Center(
            child: TextButton(
              onPressed: () => setState(_reload),
              child: const Text(
                'GCash records could not be loaded. Tap to retry.',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (summary, entries) = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            setState(_reload);
            await Future.wait([data, feeTotal, serviceHistory]);
          },
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
              FutureBuilder<int>(
                future: feeTotal,
                builder: (_, snapshot) => snapshot.hasError
                    ? _retryHistory()
                    : !snapshot.hasData
                    ? const LinearProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _metric(
                          'Service fees earned • All time',
                          snapshot.data ?? 0,
                          Colors.green.shade800,
                        ),
                      ),
              ),
              FutureBuilder<List<GCashServiceTransaction>>(
                future: serviceHistory,
                builder: (_, snapshot) => snapshot.hasError
                    ? _retryHistory()
                    : !snapshot.hasData
                    ? const LinearProgressIndicator()
                    : DayHistory<GCashServiceTransaction>(
                        storageKey: 'gcash-services',
                        items: snapshot.data ?? [],
                        date: (s) => s.createdAt,
                        itemBuilder: (service) => ExpansionTile(
                          key: PageStorageKey('gcash-service-${service.id}'),
                          title: Text(
                            '${service.type == 'CASH_IN' ? 'Cash-In' : 'Cash-Out'} • ${service.status}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Principal: ${standardMoney(service.principalCentavos)} • Fee: ${standardMoney(service.feeCentavos)}',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(service.reference),
                                  Text(_when(service.createdAt.toLocal())),
                                  Text(
                                    'GCash movement: ${standardMoney(service.gcashChangeCentavos)}',
                                  ),
                                  Text(
                                    'Cash movement: ${standardMoney(service.physicalCashChangeCentavos)}',
                                  ),
                                  if (service.gcashReference != null)
                                    Text(
                                      'GCash reference: ${service.gcashReference}',
                                    ),
                                  if (service.notes != null)
                                    Text(service.notes!),
                                  if (service.status == 'POSTED')
                                    TextButton.icon(
                                      onPressed: () => _reverseService(service),
                                      icon: const Icon(Icons.undo),
                                      label: const Text('Reverse service'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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
                DayHistory<GCashLedgerEntry>(
                  storageKey: 'gcash-wallet',
                  items: entries,
                  date: (e) => e.occurredAt,
                  itemBuilder: (entry) => Card(
                    child: ExpansionTile(
                      key: PageStorageKey('gcash-entry-${entry.id}'),
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
                        '${entry.amountChangeCentavos > 0 ? '+' : '-'}${standardMoney(entry.amountChangeCentavos.abs())}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: entry.amountChangeCentavos > 0
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${_when(entry.occurredAt.toLocal())}'
                              '${entry.gcashReference == null ? '' : '\nReference: ${entry.gcashReference}'}'
                              '${entry.notes == null ? '' : '\n${entry.notes}'}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Text(
                'Showing up to $historyLimit latest entries in each history. Fees above include all dates.',
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  historyLimit += 100;
                  _reload();
                }),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load older transactions'),
              ),
              if (summary.balance < 0)
                const Text(
                  'Recorded GCash is negative. Reconcile it against your actual wallet before making further payments.',
                  style: TextStyle(color: Colors.red),
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
    'SERVICE_REVERSAL' => 'Service Reversal',
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

  Widget _retryHistory() => TextButton(
    onPressed: () => setState(_reload),
    child: const Text('Could not load records. Tap to retry.'),
  );

  Future<void> _adjust() async {
    bool hasOpening;
    try {
      hasOpening = await widget.repository.hasOpeningBalance();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load adjustment settings. Please retry.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final amount = TextEditingController();
    final reason = TextEditingController();
    final reference = TextEditingController();
    final pin = TextEditingController();
    var type = 'ADJUSTMENT_IN', busy = false, error = '';
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setDialog) => PopScope(
          canPop: !busy,
          child: AlertDialog(
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
                      items: [
                        DropdownMenuItem(
                          enabled: !hasOpening,
                          value: 'OPENING_BALANCE',
                          child: Text(
                            hasOpening
                                ? 'Opening Balance (already set)'
                                : 'Opening Balance',
                          ),
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
                      isExpanded: true,
                      onChanged: busy
                          ? null
                          : (value) => setDialog(() => type = value!),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amount,
                      enabled: !busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '₱ ',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reason,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Reason (required)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reference,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'GCash Reference (optional)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: pin,
                      enabled: !busy,
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
                        if (busy) return;
                        FocusScope.of(dialog).unfocus();
                        setDialog(() {
                          busy = true;
                          error = '';
                        });
                        try {
                          final cents = parseMoneyCentavos(amount.text);
                          if (cents == null ||
                              cents <= 0 ||
                              reason.text.trim().isEmpty) {
                            throw const PaymentAccountingException(
                              'Enter a positive amount (up to two decimals) and a reason.',
                            );
                          }
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
      ),
    );
    final saved = await Navigator.of(context).push(route);
    // Route pop completes before its exit animation; fields still use these
    // controllers until the route is actually removed from the overlay.
    await route.completed;
    amount.dispose();
    reason.dispose();
    reference.dispose();
    pin.dispose();
    if (saved == true && mounted) setState(_reload);
  }

  Future<void> _service(String type) async {
    final requestId = GCashServiceRepository.newRequestId();
    final principal = TextEditingController();
    final fee = TextEditingController(text: '0');
    final reference = TextEditingController();
    final notes = TextEditingController();
    String? error;
    var reviewing = false, saving = false, principalCents = 0, feeCents = 0;
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setDialog) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reviewing
                      ? 'Review GCash Service'
                      : type == 'CASH_IN'
                      ? 'GCash Cash-In'
                      : 'GCash Cash-Out',
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: reviewing
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Principal: ${standardMoney(principalCents)}'),
                          Text(
                            'Service Fee (Cash): ${standardMoney(feeCents)}',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            type == 'CASH_IN'
                                ? 'Customer Pays Cash: ${standardMoney(principalCents + feeCents)}\nGCash Sent: ${standardMoney(principalCents)}'
                                : 'Customer Sends GCash: ${standardMoney(principalCents)}\nCash Given: ${standardMoney(principalCents)}\nCash Fee Received: ${standardMoney(feeCents)}',
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 16),
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
                          const SizedBox(height: 16),
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
                          const SizedBox(height: 16),
                          TextField(
                            controller: reference,
                            decoration: const InputDecoration(
                              labelText: 'GCash Reference (optional)',
                            ),
                          ),
                          const SizedBox(height: 16),
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
                        ],
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => reviewing
                          ? setDialog(() {
                              reviewing = false;
                              error = null;
                            })
                          : Navigator.of(dialog).pop(false),
                child: Text(reviewing ? 'Back' : 'Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (saving) return;
                        FocusScope.of(dialog).unfocus();
                        if (!reviewing) {
                          final p = parseMoneyCentavos(principal.text),
                              f = parseMoneyCentavos(fee.text);
                          if (p == null ||
                              f == null ||
                              p <= 0 ||
                              (type == 'CASH_OUT' && f >= p)) {
                            setDialog(
                              () => error = 'Enter a valid amount (up to two decimals). Cash-Out fee must be less than principal.',
                            );
                            return;
                          }
                          if (type == 'CASH_IN') {
                            setDialog(() => saving = true);
                            int available;
                            try {
                              available = await widget.services
                                  .availableGCashBalance();
                            } catch (_) {
                              if (dialog.mounted) {
                                setDialog(() {
                                  saving = false;
                                  error = 'Could not check GCash balance. Please retry.';
                                });
                              }
                              return;
                            }
                            if (!dialog.mounted) return;
                            setDialog(() => saving = false);
                            if (p > available) {
                              if (dialog.mounted) {
                                setDialog(
                                  () => error =
                                      'Insufficient GCash Balance\nAvailable: ${standardMoney(available)}\nRequired: ${standardMoney(p)}\nShort: ${standardMoney(p - available)}',
                                );
                              }
                              return;
                            }
                          }
                          if (dialog.mounted) {
                            setDialog(() {
                              principalCents = p;
                              feeCents = f;
                              error = null;
                              reviewing = true;
                            });
                          }
                          return;
                        }
                        setDialog(() => saving = true);
                        try {
                          await widget.services.record(
                            type: type,
                            requestId: requestId,
                            principalCentavos: principalCents,
                            feeCentavos: feeCents,
                            gcashReference: reference.text,
                            notes: notes.text,
                            physicalCashAvailabilityAcknowledged:
                                type == 'CASH_OUT',
                          );
                          if (dialog.mounted) {
                            Navigator.of(dialog).pop(true);
                          }
                        } catch (e) {
                          if (dialog.mounted) {
                            setDialog(() {
                              saving = false;
                              error = e.toString();
                            });
                          }
                        }
                      },
                child: Text(
                  saving
                      ? 'Saving…'
                      : reviewing
                      ? 'Confirm'
                      : 'Review',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final saved = await Navigator.of(context).push(route);
    await route.completed;
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
    var busy = false;
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setDialog) => PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: const Text('Reverse GCash Service'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${service.reference} • ${service.type == 'CASH_IN' ? 'Cash-In' : 'Cash-Out'}',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      enabled: !busy,
                      controller: reason,
                      decoration: const InputDecoration(
                        labelText: 'Reason (required)',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      enabled: !busy,
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
                        FocusScope.of(dialog).unfocus();
                        setDialog(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          if (await widget.auth.verify(pin.text) !=
                              UserRole.owner) {
                            throw const GCashServiceException(
                              'Incorrect Owner PIN.',
                            );
                          }
                          await widget.services.reverse(
                            service.id,
                            reason: reason.text,
                            ownerPinAuthorized: true,
                          );
                          if (dialog.mounted) Navigator.pop(dialog, true);
                        } catch (e) {
                          if (dialog.mounted) {
                            setDialog(() {
                              busy = false;
                              error = e.toString();
                            });
                          }
                        }
                      },
                child: Text(busy ? 'Saving…' : 'Reverse'),
              ),
            ],
          ),
        ),
      ),
    );
    final reversed = await Navigator.of(context).push(route);
    await route.completed;
    reason.dispose();
    pin.dispose();
    if (reversed == true && mounted) setState(_reload);
  }
}
