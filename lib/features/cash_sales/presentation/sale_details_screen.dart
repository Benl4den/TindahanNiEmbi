import 'package:flutter/material.dart';

import '../../../repositories/cash_sale_repository.dart';

class SaleDetailsScreen extends StatelessWidget {
  const SaleDetailsScreen({
    super.key,
    required this.repository,
    required this.saleId,
  });
  final CashSaleRepository repository;
  final int saleId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sale Details')),
    body: FutureBuilder<CashSaleDetails>(
      future: repository.details(saleId),
      builder: (_, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final d = s.data!, local = d.sale.occurredAt.toLocal();
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              d.sale.reference,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${MaterialLocalizations.of(context).formatFullDate(local)} • ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
            ),
            const SizedBox(height: 20),
            ...d.items.map(
              (x) => ListTile(
                title: Text(x['product_name_snapshot']! as String),
                subtitle: Text(
                  '${x['quantity']} × ₱${((x['unit_price_centavos']! as int) / 100).toStringAsFixed(2)}',
                ),
                trailing: Text(
                  '₱${((x['line_total_centavos']! as int) / 100).toStringAsFixed(2)}',
                ),
              ),
            ),
            const Divider(),
            Text('${d.sale.itemCount} items', textAlign: TextAlign.right),
            Text(
              'Total: ₱${(d.sale.totalCentavos / 100).toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        );
      },
    ),
  );
}
