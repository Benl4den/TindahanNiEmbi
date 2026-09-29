import 'package:flutter/material.dart';

import '../../../core/formatters/display_labels.dart';
import '../../../core/formatters/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/customer.dart';

/// Presentation only: all balances come from the existing customer ledger.
class CustomerAccountDetailsView extends StatelessWidget {
  const CustomerAccountDetailsView({
    super.key,
    required this.details,
    required this.currentBalanceCentavos,
    required this.outstandingCount,
    required this.filter,
    required this.onFilterChanged,
    required this.onEditProfile,
    required this.onRecordPayment,
    required this.onNewUtang,
    this.onAddExisting,
    required this.onViewEntry,
  });

  final CustomerDetails details;
  final int currentBalanceCentavos;
  final int outstandingCount;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onEditProfile, onRecordPayment, onNewUtang;
  final VoidCallback? onAddExisting;
  final ValueChanged<CustomerLedgerEntry> onViewEntry;

  static const filters = ['All', 'UTANG', 'Payments', 'Products on UTANG'];

  @override
  Widget build(BuildContext context) {
    final entries = details.ledger.where((e) {
      if (filter == 'All') return true;
      if (filter == 'UTANG') return e.type.startsWith('UTANG');
      return filter == 'Payments' && e.type.startsWith('PAYMENT');
    }).toList();
    final balances = _balancesAfter(details.ledger);
    final groups = <String, List<CustomerLedgerEntry>>{};
    for (final entry in entries) {
      final day = entry.occurredAt.toLocal();
      groups
          .putIfAbsent('${day.year}-${day.month}-${day.day}', () => [])
          .add(entry);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        _profile(context),
        const SizedBox(height: 20),
        _balanceCard(context),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: filters.map((value) {
            final selected = value == filter;
            return ChoiceChip(
              label: Text(value),
              avatar: selected && value == 'All'
                  ? Icon(
                      Icons.check,
                      size: 18,
                      color: Theme.of(context).colorScheme.onPrimary,
                    )
                  : null,
              selected: selected,
              onSelected: (_) => onFilterChanged(value),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : null,
              ),
              selectedColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            );
          }).toList(),
        ),
        const SizedBox(height: 18),
        if (filter == 'Products on UTANG')
          if (details.products.isEmpty)
            _empty(context, 'No products on UTANG yet.')
          else
            ...details.products.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _surface(
                  context,
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        _icon(context, Icons.shopping_bag_outlined),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${item.quantity} ${item.option} • ${_dateTime(context, item.occurredAt.toLocal())}',
                              ),
                            ],
                          ),
                        ),
                        Text(
                          standardMoney(item.lineTotalCentavos),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
        else if (groups.isEmpty)
          _empty(context, 'No transactions in this view yet.')
        else
          ...groups.values.map(
            (group) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _historyCard(context, group, balances),
            ),
          ),
      ],
    );
  }

  Widget _profile(BuildContext context) {
    final customer = details.customer;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, box) {
        final edit = OutlinedButton.icon(
          onPressed: onEditProfile,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit Profile'),
        );
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: context.semanticColors.success.withValues(
                alpha: .22,
              ),
              foregroundColor: context.semanticColors.success,
              child: const Icon(Icons.person, size: 42),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.fullName,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  _profileLine(
                    Icons.phone_outlined,
                    customer.mobileNumber?.trim().isNotEmpty == true
                        ? customer.mobileNumber!.trim()
                        : 'No contact number',
                    muted,
                  ),
                  if (customer.address?.trim().isNotEmpty == true)
                    _profileLine(
                      Icons.location_on_outlined,
                      customer.address!.trim(),
                      muted,
                    ),
                ],
              ),
            ),
          ],
        );
        return box.maxWidth >= 620
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: identity),
                  const SizedBox(width: 16),
                  edit,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: edit),
                ],
              );
      },
    );
  }

  Widget _profileLine(IconData icon, String text, Color muted) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: muted)),
        ),
      ],
    ),
  );

  Widget _balanceCard(BuildContext context) => _surface(
    context,
    Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 880;
          final actionWidth = wide ? (box.maxWidth - 28) * 2 / 5 : box.maxWidth;
          final financial = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current UTANG Balance',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                standardMoney(currentBalanceCentavos),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: context.semanticColors.utang,
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, metricsBox) {
                  final metrics = [
                    _metric(
                      context,
                      'Outstanding UTANG',
                      '$outstandingCount ${outstandingCount == 1 ? 'transaction' : 'transactions'}',
                    ),
                    _metric(context, 'Last UTANG', _lastDate(context, 'UTANG')),
                    _metric(
                      context,
                      'Last Payment',
                      _lastDate(context, 'PAYMENT'),
                    ),
                  ];
                  return metricsBox.maxWidth >= 620
                      ? Row(
                          children: [
                            for (var i = 0; i < metrics.length; i++) ...[
                              if (i > 0)
                                Container(
                                  height: 42,
                                  width: 1,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                  ),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                              Expanded(child: metrics[i]),
                            ],
                          ],
                        )
                      : Wrap(
                          spacing: 26,
                          runSpacing: 14,
                          children: metrics
                              .map(
                                (m) => SizedBox(
                                  width: metricsBox.maxWidth >= 420
                                      ? 175
                                      : metricsBox.maxWidth,
                                  child: m,
                                ),
                              )
                              .toList(),
                        );
                },
              ),
            ],
          );
          final actions = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 58,
                child: FilledButton.icon(
                  onPressed: currentBalanceCentavos > 0
                      ? onRecordPayment
                      : null,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Record Payment'),
                ),
              ),
              const SizedBox(height: 10),
              if (actionWidth >= 540)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 54,
                        child: OutlinedButton.icon(
                          onPressed: onNewUtang,
                          icon: const Icon(Icons.add),
                          label: const Text('New UTANG Sale'),
                        ),
                      ),
                    ),
                    if (onAddExisting != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 54,
                          child: OutlinedButton.icon(
                            onPressed: onAddExisting,
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Add Existing UTANG Amount'),
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              else ...[
                SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: onNewUtang,
                    icon: const Icon(Icons.add),
                    label: const Text('New UTANG Sale'),
                  ),
                ),
                if (onAddExisting != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: onAddExisting,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Add Existing UTANG Amount'),
                    ),
                  ),
                ],
              ],
            ],
          );
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 3, child: financial),
                    const SizedBox(width: 28),
                    Expanded(flex: 2, child: actions),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [financial, const SizedBox(height: 20), actions],
                );
        },
      ),
    ),
  );

  Widget _metric(BuildContext context, String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 3),
      Text(
        value,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );

  Widget _historyCard(
    BuildContext context,
    List<CustomerLedgerEntry> group,
    Map<int, int> balances,
  ) {
    final date = group.first.occurredAt.toLocal();
    return _surface(
      context,
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(
            'utang-day-${date.year}-${date.month}-${date.day}',
          ),
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          iconColor: Theme.of(context).colorScheme.primary,
          collapsedIconColor: Theme.of(context).colorScheme.primary,
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            children: [
              Text(
                _shortDate(date),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${group.length} ${group.length == 1 ? 'transaction' : 'transactions'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          children: [
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            for (var i = 0; i < group.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              _entryRow(context, group[i], balances[group[i].id] ?? 0),
            ],
          ],
        ),
      ),
    );
  }

  Widget _entryRow(
    BuildContext context,
    CustomerLedgerEntry entry,
    int balanceAfter,
  ) {
    final isUtang = entry.type.startsWith('UTANG');
    final isReversal = entry.type.endsWith('REVERSAL');
    final positive = entry.amountCentavos >= 0;
    final title = switch (entry.type) {
      'UTANG_REVERSAL' => 'UTANG Sale Reversed',
      'PAYMENT_REVERSAL' => 'Payment Reversed',
      _ when entry.isExistingBalance => 'Existing UTANG',
      _ when isUtang => 'UTANG Sale',
      _ => 'Payment Received',
    };
    final amountLabel = isReversal
        ? positive
              ? 'Amount restored'
              : 'Amount reversed'
        : isUtang
        ? 'Amount added'
        : 'Amount paid';
    final amountText =
        '${positive ? '+' : '-'}${standardMoney(entry.amountCentavos.abs())}';
    final amountColor = positive
        ? context.semanticColors.utang
        : context.semanticColors.success;
    final time = TimeOfDay.fromDateTime(entry.occurredAt.toLocal())
        .format(context);
    final id = isUtang
        ? '${entry.isExistingBalance ? 'EXU' : 'UTG'}-${(entry.utangTransactionId ?? 0).toString().padLeft(6, '0')}'
        : 'PAY-${(entry.paymentId ?? 0).toString().padLeft(6, '0')}';
    final metadata = [
      time,
      if (!isUtang && entry.paymentMethod != null)
        DisplayLabels.paymentMethod(entry.paymentMethod),
      id,
      if (isUtang && !entry.isExistingBalance && entry.itemCount != null)
        '${entry.itemCount} ${entry.itemCount == 1 ? 'item' : 'items'}',
      if (!isUtang && entry.paymentReference?.isNotEmpty == true)
        entry.paymentReference!,
    ].join(' • ');
    final canView = isUtang
        ? entry.type == 'UTANG' && entry.utangTransactionId != null
        : entry.type == 'PAYMENT' && entry.paymentId != null;
    final info = Row(
      children: [
        _icon(
          context,
          isUtang ? Icons.receipt_long_outlined : Icons.payments_outlined,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text(metadata, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
    final balance = _metric(
      context,
      'Balance after',
      standardMoney(balanceAfter),
    );
    final button = canView
        ? OutlinedButton.icon(
            onPressed: () => onViewEntry(entry),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.chevron_right),
            label: const Text('View Details'),
          )
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth >= 900) {
            return Row(
              children: [
                Expanded(flex: 5, child: info),
                const SizedBox(width: 22),
                Expanded(
                  flex: 2,
                  child: _amountMetric(
                    context,
                    amountLabel,
                    amountText,
                    amountColor,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 1,
                  height: 44,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                const SizedBox(width: 22),
                Expanded(flex: 2, child: balance),
                if (button != null) ...[const SizedBox(width: 20), button],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              info,
              const SizedBox(height: 14),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _amountMetric(context, amountLabel, amountText, amountColor),
                  balance,
                  ?button,
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _amountMetric(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 3),
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    ],
  );

  Widget _icon(BuildContext context, IconData icon) => CircleAvatar(
    radius: 27,
    backgroundColor: context.semanticColors.success.withValues(alpha: .22),
    foregroundColor: context.semanticColors.success,
    child: Icon(icon),
  );

  Widget _surface(BuildContext context, Widget child) => Material(
    color: context.semanticColors.surfaceContainer,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: child,
  );

  Widget _empty(BuildContext context, String message) => _surface(
    context,
    Padding(padding: const EdgeInsets.all(24), child: Text(message)),
  );

  String _lastDate(BuildContext context, String type) {
    final matching = details.ledger.where((e) => e.type == type).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return matching.isEmpty
        ? 'None yet'
        : _dateTime(context, matching.first.occurredAt.toLocal());
  }

  String _dateTime(BuildContext context, DateTime date) =>
      '${_shortDate(date)} • ${TimeOfDay.fromDateTime(date).format(context)}';

  String _shortDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}';
  }

  Map<int, int> _balancesAfter(List<CustomerLedgerEntry> entries) {
    final chronological = entries.toList()
      ..sort((a, b) {
        final byTime = a.occurredAt.compareTo(b.occurredAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    var running = 0;
    return {
      for (final entry in chronological)
        entry.id: (running += entry.amountCentavos),
    };
  }
}
