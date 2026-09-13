import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../core/theme/app_theme.dart';

import '../../../models/customer.dart';

class UtangCustomerCard extends StatelessWidget {
  const UtangCustomerCard({
    super.key,
    required this.customer,
    required this.onTap,
  });
  final Customer customer;
  final VoidCallback onTap;
  String get initials => customer.fullName
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((x) => x[0].toUpperCase())
      .join();
  @override
  Widget build(BuildContext context) {
    final outstanding = customer.balanceCentavos > 0;
    final amountColor = outstanding
        ? context.semanticColors.utang
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      label: outstanding ? 'Outstanding UTANG' : 'Zero UTANG Balance',
      button: true,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: outstanding
                ? context.semanticColors.utang.withValues(alpha: .45)
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: context.semanticColors.utang.withValues(
                    alpha: .18,
                  ),
                  foregroundColor: context.semanticColors.utang,
                  child: Text(initials),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.fullName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (customer.nickname?.isNotEmpty == true)
                        Text(customer.nickname!),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          Text(
                            'Last UTANG Sale: ${_date(context, customer.lastUtangAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            'Last payment: ${_date(context, customer.lastPaymentAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            '${customer.transactionCount} transactions',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: outstanding
                            ? context.semanticColors.utang.withValues(
                                alpha: .18,
                              )
                            : Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        outstanding ? 'With balance' : 'Settled',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      standardMoney(customer.balanceCentavos),
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        color: amountColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _date(BuildContext context, DateTime? value) => value == null
      ? '—'
      : MaterialLocalizations.of(context).formatMediumDate(value.toLocal());
}
