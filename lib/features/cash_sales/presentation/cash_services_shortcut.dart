import 'package:flutter/material.dart';

import '../../../core/formatters/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/payment_method.dart';
import '../../../repositories/payment_accounting_repository.dart';
import '../../../services/feature_access_service.dart';
import '../../../widgets/feature_access_builder.dart';
import '../../../widgets/wallet_nav_logo.dart';

typedef CashServiceAction = Future<bool?> Function(
  PaymentMethod provider,
  String serviceType,
);

/// A presentation-only shortcut; service forms and posting stay in GCashScreen.
class CashServicesShortcut extends StatefulWidget {
  const CashServicesShortcut({
    super.key,
    required this.access,
    required this.gcash,
    required this.maya,
    required this.onService,
    required this.onHistory,
  });

  final FeatureAccessService access;
  final PaymentAccountingRepository gcash;
  final PaymentAccountingRepository maya;
  final CashServiceAction onService;
  final Future<void> Function(PaymentMethod provider) onHistory;

  @override
  State<CashServicesShortcut> createState() => _CashServicesShortcutState();
}

class _CashServicesShortcutState extends State<CashServicesShortcut> {
  bool _opening = false;

  Future<void> _open(bool allowed) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final choice = await showModalBottomSheet<_CashServicesChoice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 840),
        builder: (_) => _CashServicesSheet(
          allowed: allowed,
          gcash: widget.gcash,
          maya: widget.maya,
        ),
      );
      if (!mounted || choice == null) return;
      if (choice.serviceType != null) {
        final feature = choice.provider == PaymentMethod.maya
            ? ProFeature.mayaServices
            : ProFeature.gcashServices;
        if (await widget.access.allows(feature) && mounted) {
          await widget.onService(choice.provider!, choice.serviceType!);
        }
      } else if (choice.provider != null) {
        if (await widget.access.allows(
              choice.provider == PaymentMethod.maya
                  ? ProFeature.mayaServices
                  : ProFeature.gcashServices,
            ) &&
            mounted) {
          await widget.onHistory(choice.provider!);
        }
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => FeatureAccessBuilder(
    access: widget.access,
    feature: ProFeature.gcashServices,
    builder: (context, allowed) {
      final colors = Theme.of(context).colorScheme;
      return Semantics(
        button: true,
        label: allowed ? 'Cash Services' : 'Cash Services, Pro feature locked',
        child: Material(
          elevation: 3,
          color: allowed ? colors.primary : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: const ValueKey('cash-services-launcher'),
            borderRadius: BorderRadius.circular(16),
            onTap: _opening ? null : () => _open(allowed),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 21,
                      color: allowed ? colors.onPrimary : colors.onSurface,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cash Services',
                      style: TextStyle(
                        color: allowed ? colors.onPrimary : colors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!allowed) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: colors.onSurface,
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD879),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                            color: Color(0xFF312100),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _CashServicesChoice {
  const _CashServicesChoice(this.provider, this.serviceType);
  final PaymentMethod? provider;
  final String? serviceType;
}

class _CashServicesSheet extends StatefulWidget {
  const _CashServicesSheet({
    required this.allowed,
    required this.gcash,
    required this.maya,
  });

  final bool allowed;
  final PaymentAccountingRepository gcash;
  final PaymentAccountingRepository maya;

  @override
  State<_CashServicesSheet> createState() => _CashServicesSheetState();
}

class _CashServicesSheetState extends State<_CashServicesSheet> {
  late final Future<GCashSummary> _gcashBalance;
  late final Future<GCashSummary> _mayaBalance;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.allowed) {
      _gcashBalance = widget.gcash.summary();
      _mayaBalance = widget.maya.summary();
    }
  }

  void _choose(PaymentMethod? provider, String? type) {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).pop(_CashServicesChoice(provider, type));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(wide ? 22 : 16, 0, wide ? 22 : 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cash Services',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'Quick cash services',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close Cash Services',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!widget.allowed)
                _lockedView()
              else ...[
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _providerCard(
                          PaymentMethod.gcash,
                          _gcashBalance,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _providerCard(PaymentMethod.maya, _mayaBalance),
                      ),
                    ],
                  )
                else ...[
                  _providerCard(PaymentMethod.gcash, _gcashBalance),
                  const SizedBox(height: 12),
                  _providerCard(PaymentMethod.maya, _mayaBalance),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('cash-services-history'),
                  onPressed: () => _historyPicker(),
                  icon: const Icon(Icons.history),
                  label: const Text('View Service History'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: colors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _providerCard(PaymentMethod provider, Future<GCashSummary> balance) {
    final colors = Theme.of(context).colorScheme;
    final maya = provider == PaymentMethod.maya;
    final name = maya ? 'Maya' : 'GCash';
    return Container(
      key: ValueKey('cash-services-card-${provider.dbValue}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceElevated,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: WalletNavLogo(maya: maya),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium),
                    FutureBuilder<GCashSummary>(
                      future: balance,
                      builder: (_, snapshot) => Text(
                        snapshot.hasError
                            ? 'Balance unavailable'
                            : snapshot.hasData
                            ? 'Balance: ${standardMoney(snapshot.data!.balance)}'
                            : 'Loading balance…',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _action(
                  provider,
                  'CASH_IN',
                  'Cash-In',
                  Icons.arrow_downward,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _action(
                  provider,
                  'CASH_OUT',
                  'Cash-Out',
                  Icons.arrow_upward,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    PaymentMethod provider,
    String type,
    String label,
    IconData icon,
  ) {
    final colors = Theme.of(context).colorScheme;
    return FilledButton.tonalIcon(
      key: ValueKey('cash-services-${provider.dbValue}-$type'),
      onPressed: _leaving ? null : () => _choose(provider, type),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        minimumSize: const Size.fromHeight(48),
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.primary,
      ),
      icon: Icon(icon, size: 18),
      label: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
    );
  }

  Future<void> _historyPicker() async {
    if (_leaving) return;
    final provider = await showModalBottomSheet<PaymentMethod>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: const Text('GCash Service History'),
              leading: const WalletNavLogo(maya: false),
              onTap: () => Navigator.pop(context, PaymentMethod.gcash),
            ),
            ListTile(
              title: const Text('Maya Service History'),
              leading: const WalletNavLogo(maya: true),
              onTap: () => Navigator.pop(context, PaymentMethod.maya),
            ),
          ],
        ),
      ),
    );
    if (provider != null && mounted) _choose(provider, null);
  }

  Widget _lockedView() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cash Services',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Chip(label: Text('PRO')),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Use GCash and Maya for Cash-In and Cash-Out transactions.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Preview Pro'),
                    content: const Text(
                      'Pro subscriptions are not available yet. Your existing records stay safely on this device.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Preview Pro'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        for (final name in const ['GCash', 'Maya'])
          Card(
            child: ListTile(
              enabled: false,
              leading: WalletNavLogo(maya: name == 'Maya'),
              title: Text(name),
              subtitle: const Text('Cash-In / Cash-Out'),
              trailing: const Icon(Icons.lock_outline),
            ),
          ),
      ],
    );
  }
}
